// Pre-push guard (CLAUDE.md rule 5 and "Asking the owner"). Git runs the installed copy (scripts/
// install-guard.sh, from main) with the remote name and URL as arguments and one line per pushed ref on stdin.
// Tests: node --test scripts/pre-push.test.mjs
//
// It blocks a push that updates more than one ref, targets anything outside refs/heads/, targets
// main, deletes a ref, or rewrites (non-fast-forward) a branch other than the one HEAD is on; a
// push whose ref names or commits (messages, file names, added lines) carry a deny-list line or a
// vault path; and one that adds or changes a binary or non-UTF-8 file whose path is not on the
// installed binary-allowlist.txt. Commits count as already on the remote only when `git ls-remote`
// on the push URL reports them. A finding names the commit and the file and line, never the
// matched text. A missing config, allowlist or deny-list, an empty deny-list, or a git error
// blocks the push. The commit scan itself is commit-scan.mjs, shared with the CI guard.
import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { binaryAllowlist, scan } from "./commit-scan.mjs";
import { denyList, match } from "./matcher.mjs";

const zero = /^0+$/;
const mainRef = "refs/heads/main";
const reportLimit = 20;
const guardFiles = [
  "matcher.mjs",
  "commit-scan.mjs",
  "pre-push.mjs",
  "gh-post.mjs",
  "merge.mjs",
  "plain-rules.mjs",
  "binary-allowlist.txt",
];

function block(message) {
  process.stderr.write(`pre-push: push blocked. ${message}\n`);
  process.exit(1);
}

function run(args, options = {}) {
  return spawnSync("git", args, { encoding: "utf8", maxBuffer: 1 << 30, ...options });
}

function git(args, options) {
  const result = run(args, options);
  if (result.status !== 0) block(`git ${args[0]} failed (exit ${result.status}).`);
  return result.stdout;
}

/// Warns, without blocking, when the installed guard is not the one in this checkout.
function warnIfStale() {
  const installed = dirname(fileURLToPath(import.meta.url));
  const top = run(["rev-parse", "--show-toplevel"]).stdout?.trim() ?? "";
  const checkout = join(top, "scripts", "guard");
  const read = (path) => {
    try {
      return readFileSync(path);
    } catch {
      return null;
    }
  };
  try {
    if (realpathSync(installed) === realpathSync(checkout)) return;
  } catch {
    // no guard folder in this checkout: compare below, which reports the difference
  }
  const differs = guardFiles.some((name) => {
    const a = read(join(installed, name));
    const b = read(join(checkout, name));
    return a === null || b === null || !a.equals(b);
  });
  if (differs) {
    process.stderr.write(
      "pre-push: warning: the installed guard differs from this checkout's scripts/guard. " +
        "Reinstall after the change is merged (CLAUDE.md → Commands → Guard); the installer always installs main's guard.\n",
    );
  }
}

function isAncestor(older, newer) {
  if (run(["cat-file", "-e", `${older}^{commit}`]).status !== 0) return false;
  return run(["merge-base", "--is-ancestor", older, newer]).status === 0;
}

/// The commits the push URL's repository reports (git ls-remote) that exist here: only these count
/// as already on the remote. A local refs/remotes/* ref never does. `missing` counts the reported
/// ids this checkout lacks (the remote moved after the last fetch).
function remoteCommits(url) {
  if (typeof url !== "string" || url === "" || url.startsWith("-")) block("git passed the hook no push URL.");
  const ids = new Set(
    git(["ls-remote", url])
      .split("\n")
      .map((line) => line.split("\t")[0])
      .filter((id) => /^[0-9a-f]{40,64}$/.test(id)),
  );
  if (ids.size === 0) return { present: [], missing: 0 };
  const objects = git(["cat-file", "--batch-check=%(objectname) %(objecttype)"], { input: [...ids].join("\n") + "\n" })
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => line.split(" "));
  return {
    present: objects.filter(([, type]) => type === "commit").map(([id]) => id),
    missing: objects.filter(([, type]) => type === "missing").length,
  };
}

/// The commits this push sends: reachable from the pushed commit, not from a commit on the remote.
function commits(localSha, onRemote) {
  const input = [localSha, ...onRemote.map((id) => `^${id}`)].join("\n") + "\n";
  return git(["rev-list", "--stdin"], { input })
    .split("\n")
    .filter((sha) => sha !== "");
}

warnIfStale();

const refs = readFileSync(0, "utf8")
  .split("\n")
  .filter((line) => line.trim() !== "")
  .map((line) => line.trim().split(/\s+/));

if (refs.length > 1) block(`The push updates ${refs.length} refs; push one branch at a time.`);
const current = run(["symbolic-ref", "--quiet", "HEAD"]).stdout?.trim() || null;
for (const [, localSha, remoteRef, remoteSha] of refs) {
  if (!remoteRef.startsWith("refs/heads/")) block("Only branches (refs/heads/) may be pushed.");
  if (remoteRef === mainRef) block("Pushes to main are not allowed; main changes through a merged pull request.");
  if (zero.test(localSha)) block("Deleting a remote ref is not allowed; ask the owner.");
  if (!zero.test(remoteSha) && remoteRef !== current && !isAncestor(remoteSha, localSha)) {
    block("A non-fast-forward update is allowed only for the branch HEAD is on.");
  }
}

const entries = denyList(block);
const allowed = binaryAllowlist(join(dirname(fileURLToPath(import.meta.url)), "binary-allowlist.txt"), () =>
  block("No binary-allowlist.txt next to the installed guard; reinstall the guard (CLAUDE.md → Commands → Guard)."),
);
const findings = [];
for (const [localRef, , remoteRef] of refs) {
  for (const [name, label] of [[localRef, "the local ref name"], [remoteRef, "the remote ref name"]]) {
    const kind = match(name, entries);
    if (kind) findings.push(`${label}: ${kind}`);
  }
}
const onRemote = refs.length > 0 ? remoteCommits(process.argv[3]) : { present: [], missing: 0 };
const seen = new Set();
for (const [, localSha] of refs) {
  for (const sha of commits(localSha, onRemote.present)) {
    if (seen.has(sha)) continue;
    seen.add(sha);
    scan(git, sha, entries, allowed, findings);
  }
}

if (findings.length > 0) {
  const shown = findings.slice(0, reportLimit).map((finding) => `  ${finding}`);
  const more = findings.length > reportLimit ? [`  … and ${findings.length - reportLimit} more`] : [];
  const hint =
    onRemote.missing > 0
      ? "\nThe remote has commits this checkout lacks, so these may be on it already: run git fetch origin, then push again."
      : "";
  block(`${findings.length} match(es); remove them and push again:\n${[...shown, ...more].join("\n")}${hint}`);
}
