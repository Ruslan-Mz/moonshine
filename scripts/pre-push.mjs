// Pre-push guard (CLAUDE.md rule 5): blocks a push whose commits add a line of the owner's deny-list
// or a path inside the vault, and any push to `main`. Git runs it through scripts/git-hooks/pre-push
// with the remote name and URL as arguments and one line per pushed ref on stdin.
// Install: CLAUDE.md → Commands. Tests: node --test scripts/pre-push.test.mjs
//
// A finding names the commit and the file and line, never the matched text: the push output goes to
// the terminal and to session logs. A missing setting, a missing or empty deny-list, or a git error
// blocks the push.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const zero = /^0+$/;
const mainRef = "refs/heads/main";
const reportLimit = 20;
// A path into the vault folder, or an absolute path to it: both can carry note names or the
// account name. The default location alone, as the docs write it, is allowed.
const vaultPaths = [/ObsidianV\/\S/, /\/Users\/[^/\s]+\/ObsidianV(?![\w])/];

function block(message) {
  process.stderr.write(`pre-push: push blocked. ${message}\n`);
  process.exit(1);
}

function git(args) {
  const result = spawnSync("git", ["-c", "core.quotePath=false", ...args], {
    encoding: "utf8",
    maxBuffer: 1 << 30,
  });
  if (result.status !== 0) block(`git ${args[0]} failed (exit ${result.status}).`);
  return result.stdout;
}

function denyList() {
  const result = spawnSync("git", ["config", "--path", "--get", "moonshine.denyList"], { encoding: "utf8" });
  const path = result.status === 0 ? result.stdout.trim() : "";
  if (path === "") block("Set the deny-list path: git config moonshine.denyList <absolute path>.");
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    block("The deny-list named by moonshine.denyList cannot be read.");
  }
  const entries = text
    .split(/\r?\n/)
    .map((line) => fold(line.trim()))
    .filter((line) => line !== "");
  if (entries.length === 0) block("The deny-list named by moonshine.denyList has no entries.");
  return entries;
}

function fold(text) {
  return text.normalize("NFC").toLowerCase();
}

/// What a line matches, as a kind: never the matched text.
function match(line, entries) {
  const folded = fold(line);
  if (entries.some((entry) => folded.includes(entry))) return "a deny-list entry";
  if (vaultPaths.some((pattern) => pattern.test(line))) return "a vault path";
  return null;
}

/// The commits this push sends: reachable from the pushed commit, not from the remote's old tip
/// and not from any remote-tracking ref (they are already on the remote).
function commits(localSha, remoteSha) {
  const exclude = ["--not", "--remotes"];
  if (!zero.test(remoteSha) && spawnSync("git", ["cat-file", "-e", `${remoteSha}^{commit}`]).status === 0) {
    exclude.push(remoteSha);
  }
  return git(["rev-list", localSha, ...exclude])
    .split("\n")
    .filter((sha) => sha !== "");
}

/// Added lines of one commit (against its first parent), with their file and line in that commit.
function* addedLines(sha) {
  const diff = git([
    "diff-tree", "--no-commit-id", "-p", "--root", "--first-parent", "-m", "--unified=0", "--no-color", "--no-ext-diff",
    "--no-renames", "--text", sha,
  ]);
  let path = null;
  let line = 0;
  let inHunk = false;
  for (const text of diff.split("\n")) {
    if (text.startsWith("diff --git ")) {
      inHunk = false;
      path = null;
    } else if (!inHunk && text.startsWith("+++ ")) {
      path = text === "+++ /dev/null" ? null : text.slice(4).replace(/^"?b\//, "").replace(/"$/, "");
    } else if (text.startsWith("@@ ")) {
      inHunk = true;
      line = Number(/\+(\d+)/.exec(text.slice(3))?.[1] ?? 0);
    } else if (inHunk && text.startsWith("+")) {
      yield { path, line, text: text.slice(1) };
      line += 1;
    }
  }
}

function changedPaths(sha) {
  return git(["diff-tree", "--no-commit-id", "-r", "--root", "--first-parent", "-m", "--name-only", "--no-renames", "--format=", sha])
    .split("\n")
    .filter((path) => path !== "");
}

function scan(sha, entries, findings) {
  const short = sha.slice(0, 9);
  git(["log", "-1", "--format=%B", sha])
    .split("\n")
    .forEach((text, index) => {
      const kind = match(text, entries);
      if (kind) findings.push(`commit ${short}, message line ${index + 1}: ${kind}`);
    });
  const unsafeNames = new Set();
  for (const path of changedPaths(sha)) {
    const kind = match(path, entries);
    if (kind) {
      unsafeNames.add(path);
      findings.push(`commit ${short}, a file name: ${kind}`);
    }
  }
  for (const added of addedLines(sha)) {
    const kind = match(added.text, entries);
    if (!kind) continue;
    const where = added.path === null || unsafeNames.has(added.path) ? "a file whose name is listed above" : added.path;
    findings.push(`commit ${short}, ${where}:${added.line}: ${kind}`);
  }
}

const refs = readFileSync(0, "utf8")
  .split("\n")
  .filter((line) => line.trim() !== "")
  .map((line) => line.trim().split(/\s+/));

for (const [, , remoteRef] of refs) {
  if (remoteRef === mainRef) block("Pushes to main are not allowed; main changes through a merged pull request.");
}

const entries = denyList();
const findings = [];
const seen = new Set();
for (const [, localSha, , remoteSha] of refs) {
  if (zero.test(localSha)) continue; // a deletion sends no commits
  for (const sha of commits(localSha, remoteSha)) {
    if (seen.has(sha)) continue;
    seen.add(sha);
    scan(sha, entries, findings);
  }
}

if (findings.length > 0) {
  const shown = findings.slice(0, reportLimit).map((finding) => `  ${finding}`);
  const more = findings.length > reportLimit ? [`  … and ${findings.length - reportLimit} more`] : [];
  block(`${findings.length} match(es); remove them from the commits and push again:\n${[...shown, ...more].join("\n")}`);
}
