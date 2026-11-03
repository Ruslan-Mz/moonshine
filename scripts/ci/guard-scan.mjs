// The guard in CI (CLAUDE.md → Commands → Guard; docs/setup/github.md). .github/workflows/guard.yml
// runs main's copy on every pull request (pull_request_target) and every push to main, with the
// deny-list from the `guard` environment's DENY_LIST secret, which only jobs on main receive. It
// scans what the pre-push hook scans (commit-scan.mjs: messages, file names, binary files, added
// lines) for the commits not yet on main, plus the PR's head branch name, title and body. Commit ids
// and names come from the environment, never from the workflow's `run:` lines; the branch name, the
// title and the body come from the event file ($GITHUB_EVENT_PATH), because the runner prints a
// step's `env:` values in the public log, which never prints the PR's title or body.
// Tests: node --test scripts/guard-scan.test.mjs
//
// A finding names the commit and the file and line, never the matched text: the log is public. A
// PR from another repository (a fork) fails unscanned; the owner scans it locally and re-pushes it
// here as a branch fork/<pr>-<slug>, which /review-pr reviews read-only. A range above the limits, or a push whose previous head is not an ancestor,
// fails: the owner scans it locally. Exit 0 clean, 1 findings or not scanned, 2 setup or git error.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { binaryAllowlist, scan } from "../guard/commit-scan.mjs";
import { match, parseDenyList } from "../guard/matcher.mjs";

export const defaultAllowlist = join(dirname(fileURLToPath(import.meta.url)), "..", "guard", "binary-allowlist.txt");
/// `bytes` bounds the diff output of the whole scan (messages, file lists, patches); `fileBytes`
/// bounds one file: its content, read whole for the binary check and not counted in `bytes`, and the
/// added lines of its patch (removed lines are never scanned, so a re-padded table counts once).
/// Both count raw bytes, before decoding. A file on the binary allowlist is not read at all.
export const defaultLimits = { commits: 2000, bytes: 10 * 1024 * 1024, fileBytes: 4 * 1024 * 1024 };
const reportLimit = 20;
const commitId = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const remoteRef = /^refs\/remotes\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)+$/;
const zero = /^0+$/;
const tooLarge = "too large to scan; the owner scans it locally.";

class Stop extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function stop(status, message) {
  throw new Stop(status, message);
}

/// The bytes of a patch's added lines: those starting with `+` after its first hunk header.
function addedBytes(patch) {
  let total = 0;
  let inHunk = false;
  let start = 0;
  while (start < patch.length) {
    let end = patch.indexOf(0x0a, start);
    if (end === -1) end = patch.length;
    if (patch[start] === 0x40 && patch[start + 1] === 0x40) inHunk = true;
    else if (inHunk && patch[start] === 0x2b) total += end - start;
    start = end + 1;
  }
  return total;
}

/// The PR's head branch name, title and body lines from the event file, each with its label.
function prTexts(path) {
  let pr;
  try {
    pr = JSON.parse(readFileSync(path, "utf8")).pull_request;
  } catch {
    stop(2, "The event file is missing or malformed.");
  }
  const { title, body, head } = pr ?? {};
  if (typeof title !== "string" || (body !== null && typeof body !== "string") || typeof head?.ref !== "string") {
    stop(2, "The event file is missing or malformed.");
  }
  const texts = [["the head branch name", head.ref], ["PR title", title]];
  (body ?? "").split(/\r?\n/).forEach((line, index) => texts.push([`PR body line ${index + 1}`, line]));
  return texts;
}

/// The scan of one event. `env` holds the event (below); `gitEnv` is the environment git runs with.
/// Returns the exit status, the lines to print and the diff bytes git returned.
///   EVENT=pull_request_target: BASE (refs/remotes/origin/main), HEAD (the PR head's commit id),
///     HEAD_REPO, REPOSITORY, GITHUB_EVENT_PATH (the event file: branch name, title, body);
///   EVENT=push: BEFORE, AFTER (commit ids);
///   DENY_LIST: the deny-list's text.
export function guardScan({ env, cwd, gitEnv = process.env, allowlist = defaultAllowlist, limits = defaultLimits }) {
  let bytes = 0;

  /// git with its output bounded in raw bytes, before decoding: a file's content by `fileBytes`
  /// alone, everything else by the rest of `bytes`, and a file's patch also by `fileBytes` of added
  /// lines. stderr is never printed.
  function run(args, options = {}) {
    const content = args[0] === "cat-file" && args[1] === "blob";
    const patch = args[0] === "diff-tree" && args.includes("-p");
    const budget = content ? limits.fileBytes : limits.bytes - bytes;
    const result = spawnSync("git", args, {
      cwd,
      env: gitEnv,
      maxBuffer: Math.max(budget, 1),
      ...options,
      ...(typeof options.input === "string" ? { input: Buffer.from(options.input) } : {}),
      encoding: "buffer",
      stdio: ["pipe", "pipe", "ignore"],
    });
    if (result.error?.code === "ENOBUFS") stop(1, tooLarge);
    const output = result.stdout ?? Buffer.alloc(0);
    if (output.length > budget) stop(1, tooLarge);
    if (!content) bytes += output.length;
    if (patch && addedBytes(output) > limits.fileBytes) stop(1, tooLarge);
    return { status: result.status, stdout: options.encoding === "buffer" ? output : output.toString("utf8") };
  }

  function git(args, options) {
    const result = run(args, options);
    if (result.status !== 0) stop(2, `git ${args[0]} failed (exit ${result.status}).`);
    return result.stdout;
  }

  function commitOf(id) {
    if (typeof id !== "string" || !commitId.test(id)) stop(2, "A commit id from the event is missing or malformed.");
    git(["cat-file", "-e", `${id}^{commit}`]);
    return id;
  }

  try {
    const event = env.EVENT;
    if (event !== "pull_request_target" && event !== "push") stop(2, "EVENT is neither pull_request_target nor push.");
    if (event === "pull_request_target" && (!env.REPOSITORY || env.HEAD_REPO !== env.REPOSITORY)) {
      stop(1, "fork PR: not scanned. The owner scans it locally and re-pushes it here as a branch fork/<pr>-<slug>.");
    }
    if (!env.DENY_LIST?.trim()) stop(2, "DENY_LIST is not set: docs/setup/github.md, step 5.");
    const entries = parseDenyList(env.DENY_LIST, (message) => stop(2, message));
    const allowed = binaryAllowlist(allowlist, () => stop(2, "No readable scripts/guard/binary-allowlist.txt in main's checkout."));

    let range;
    if (event === "pull_request_target") {
      // A full ref: a short name such as origin/main would resolve to a tag of that name first.
      const base = env.BASE;
      if (typeof base !== "string" || !remoteRef.test(base)) stop(2, "BASE is missing or malformed.");
      git(["rev-parse", "--verify", "--quiet", `${base}^{commit}`]);
      range = [commitOf(env.HEAD), `^${base}`];
    } else {
      if (typeof env.BEFORE !== "string" || zero.test(env.BEFORE)) stop(1, "cannot tell which commits are new on main; the owner scans locally.");
      const after = commitOf(env.AFTER);
      const before = commitOf(env.BEFORE);
      if (run(["merge-base", "--is-ancestor", before, after]).status !== 0) {
        stop(1, "cannot tell which commits are new on main; the owner scans locally.");
      }
      range = [after, `^${before}`];
    }
    const commits = git(["rev-list", "--stdin"], { input: range.join("\n") + "\n" })
      .split("\n")
      .filter((sha) => sha !== "");
    if (commits.length > limits.commits) stop(1, tooLarge);

    const texts = event === "pull_request_target" ? prTexts(env.GITHUB_EVENT_PATH ?? "") : [];
    const findings = [];
    for (const sha of commits) scan(git, sha, entries, allowed, findings);
    for (const [label, text] of texts) {
      const kind = match(text, entries);
      if (kind) findings.push(`${label}: ${kind}`);
    }

    if (findings.length === 0) return { status: 0, lines: [`guard: ${commits.length} commit(s) scanned, no match.`], bytes };
    const shown = findings.slice(0, reportLimit).map((finding) => `  ${finding}`);
    const more = findings.length > reportLimit ? [`  … and ${findings.length - reportLimit} more`] : [];
    return { status: 1, lines: [`guard: ${findings.length} match(es); remove them and push again:`, ...shown, ...more], bytes };
  } catch (error) {
    if (error instanceof Stop) return { status: error.status, lines: [error.message], bytes };
    return { status: 2, lines: ["guard-scan stopped on an internal error."], bytes };
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const { status, lines } = guardScan({ env: process.env, cwd: process.cwd() });
  process.stdout.write(lines.map((line) => `${line}\n`).join(""));
  process.exitCode = status;
}
