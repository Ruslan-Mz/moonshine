// The guard in CI (CLAUDE.md → Commands → Guard; docs/setup/github.md). .github/workflows/guard.yml
// runs main's copy on every pull request (pull_request_target) and every push to main, with the
// deny-list from the `guard` environment's DENY_LIST secret, which only jobs on main receive. It
// scans what the pre-push hook scans (commit-scan.mjs: messages, file names, binary files, added
// lines) for the commits not yet on main, plus the PR's head branch name, title and body. Every
// input comes from the environment, never from the workflow's `run:` lines.
// Tests: node --test scripts/guard-scan.test.mjs
//
// A finding names the commit and the file and line, never the matched text: the log is public. A
// PR from another repository (a fork) fails unscanned; the owner scans it locally and re-pushes it
// as a branch here. A range above the limits, or a push whose previous head is not an ancestor,
// fails: the owner scans it locally. Exit 0 clean, 1 findings or not scanned, 2 setup or git error.
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { binaryAllowlist, scan } from "../guard/commit-scan.mjs";
import { match, parseDenyList } from "../guard/matcher.mjs";

export const defaultAllowlist = join(dirname(fileURLToPath(import.meta.url)), "..", "guard", "binary-allowlist.txt");
export const defaultLimits = { commits: 2000, bytes: 10 * 1024 * 1024 };
const reportLimit = 20;
const commitId = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
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

/// The scan of one event. `env` holds the event (below); `gitEnv` is the environment git runs with.
/// Returns the exit status, the lines to print and the bytes git returned.
///   EVENT=pull_request_target: BASE (main), HEAD (the PR head's commit id), HEAD_REF, HEAD_REPO,
///     REPOSITORY, PR_TITLE, PR_BODY;
///   EVENT=push: BEFORE, AFTER (commit ids);
///   DENY_LIST: the deny-list's text.
export function guardScan({ env, cwd, gitEnv = process.env, allowlist = defaultAllowlist, limits = defaultLimits }) {
  let bytes = 0;

  /// git with every byte it returns counted against the limit; stderr is never printed.
  function run(args, options = {}) {
    const result = spawnSync("git", args, {
      cwd,
      env: gitEnv,
      encoding: "utf8",
      maxBuffer: Math.max(limits.bytes - bytes, 1),
      ...options,
      stdio: ["pipe", "pipe", "ignore"],
    });
    if (result.error?.code === "ENOBUFS") stop(1, tooLarge);
    bytes += Buffer.byteLength(result.stdout ?? "");
    if (bytes > limits.bytes) stop(1, tooLarge);
    return result;
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
      stop(1, "fork PR: not scanned. The owner scans it locally and re-pushes it as a branch of this repository.");
    }
    if (!env.DENY_LIST?.trim()) stop(2, "DENY_LIST is not set: docs/setup/github.md, step 5.");
    const entries = parseDenyList(env.DENY_LIST, (message) => stop(2, message));
    const allowed = binaryAllowlist(allowlist, () => stop(2, "No readable scripts/guard/binary-allowlist.txt in main's checkout."));

    let range;
    if (event === "pull_request_target") {
      const base = env.BASE;
      if (typeof base !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(base)) stop(2, "BASE is missing or malformed.");
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

    const findings = [];
    for (const sha of commits) scan(git, sha, entries, allowed, findings);
    if (event === "pull_request_target") {
      const texts = [["the head branch name", env.HEAD_REF ?? ""], ["PR title", env.PR_TITLE ?? ""]];
      (env.PR_BODY ?? "").split(/\r?\n/).forEach((line, index) => texts.push([`PR body line ${index + 1}`, line]));
      for (const [label, text] of texts) {
        const kind = match(text, entries);
        if (kind) findings.push(`${label}: ${kind}`);
      }
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
