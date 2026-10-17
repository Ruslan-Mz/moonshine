// Pre-push guard (CLAUDE.md rule 5 and "Asking the owner"). Git runs the installed copy (scripts/
// install-guard.sh) with the remote name and URL as arguments and one line per pushed ref on stdin.
// Tests: node --test scripts/pre-push.test.mjs
//
// It blocks a push that updates more than one ref, targets anything outside refs/heads/, targets
// main, deletes a ref, or rewrites (non-fast-forward) a branch other than the one HEAD is on; and a
// push whose ref names or commits (messages, file names, added lines) carry a deny-list line or a
// vault path. A finding names the commit and the file and line, never the matched text. A missing
// setting, a missing or empty deny-list, or a git error blocks the push.
import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { denyList, match, printable } from "./matcher.mjs";

const zero = /^0+$/;
const mainRef = "refs/heads/main";
const reportLimit = 20;
const guardFiles = ["matcher.mjs", "pre-push.mjs", "gh-post.mjs"];

function block(message) {
  process.stderr.write(`pre-push: push blocked. ${message}\n`);
  process.exit(1);
}

function run(args) {
  return spawnSync("git", args, { encoding: "utf8", maxBuffer: 1 << 30 });
}

function git(args) {
  const result = run(args);
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
      "pre-push: warning: the installed guard differs from this checkout's scripts/guard; " +
        "run scripts/install-guard.sh from the repository root to update it.\n",
    );
  }
}

function isAncestor(older, newer) {
  if (run(["cat-file", "-e", `${older}^{commit}`]).status !== 0) return false;
  return run(["merge-base", "--is-ancestor", older, newer]).status === 0;
}

/// The commits this push sends: reachable from the pushed commit, not from the remote's old tip
/// and not from any remote-tracking ref (they are already on the remote).
function commits(localSha, remoteSha) {
  const exclude = ["--not", "--remotes"];
  if (!zero.test(remoteSha) && run(["cat-file", "-e", `${remoteSha}^{commit}`]).status === 0) {
    exclude.push(remoteSha);
  }
  return git(["rev-list", localSha, ...exclude])
    .split("\n")
    .filter((sha) => sha !== "");
}

const diffOptions = ["--no-commit-id", "--root", "--first-parent", "-m", "--no-renames"];

/// The paths a commit changes (against its first parent), exactly as stored.
function changedPaths(sha) {
  return git(["diff-tree", ...diffOptions, "-r", "--name-only", "-z", sha])
    .split("\0")
    .filter((path) => path !== "");
}

/// Added lines of one file in one commit, with their line numbers in that commit.
function* addedLines(sha, path) {
  const diff = git([
    "diff-tree", ...diffOptions, "-p", "--unified=0", "--no-color", "--no-ext-diff", "--text", sha,
    "--", `:(literal)${path}`,
  ]);
  let line = 0;
  let inHunk = false;
  for (const text of diff.split("\n")) {
    if (text.startsWith("@@ ")) {
      inHunk = true;
      line = Number(/\+(\d+)/.exec(text.slice(3))?.[1] ?? 0);
    } else if (inHunk && text.startsWith("+")) {
      yield { line, text: text.slice(1) };
      line += 1;
    }
  }
}

function scan(sha, entries, findings) {
  const short = sha.slice(0, 9);
  git(["log", "-1", "--format=%B", sha])
    .split("\n")
    .forEach((text, index) => {
      const kind = match(text, entries);
      if (kind) findings.push(`commit ${short}, message line ${index + 1}: ${kind}`);
    });
  for (const path of changedPaths(sha)) {
    const kind = match(path, entries);
    if (kind) findings.push(`commit ${short}, a file name: ${kind}`);
    const where = printable(path, entries);
    for (const added of addedLines(sha, path)) {
      const kind = match(added.text, entries);
      if (kind) findings.push(`commit ${short}, ${where}:${added.line}: ${kind}`);
    }
  }
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
const findings = [];
for (const [localRef, , remoteRef] of refs) {
  for (const [name, label] of [[localRef, "the local ref name"], [remoteRef, "the remote ref name"]]) {
    const kind = match(name, entries);
    if (kind) findings.push(`${label}: ${kind}`);
  }
}
const seen = new Set();
for (const [, localSha, , remoteSha] of refs) {
  for (const sha of commits(localSha, remoteSha)) {
    if (seen.has(sha)) continue;
    seen.add(sha);
    scan(sha, entries, findings);
  }
}

if (findings.length > 0) {
  const shown = findings.slice(0, reportLimit).map((finding) => `  ${finding}`);
  const more = findings.length > reportLimit ? [`  … and ${findings.length - reportLimit} more`] : [];
  block(`${findings.length} match(es); remove them and push again:\n${[...shown, ...more].join("\n")}`);
}
