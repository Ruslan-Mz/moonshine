// One commit's scan, shared by the pre-push hook (pre-push.mjs) and the CI guard
// (scripts/ci/guard-scan.mjs), so both look at a commit the same way: its message lines, the names
// of the files it changes, binary or non-UTF-8 files not on the allowlist, and its added lines. A
// finding names the commit and the file and line, never the matched text. The caller passes its
// own `git(args, options)`, which returns stdout and must not return on a failure.
import { readFileSync } from "node:fs";
import { match, printable, unreadable } from "./matcher.mjs";

const zero = /^0+$/;
const diffOptions = ["--no-commit-id", "--root", "--first-parent", "-m", "--no-renames"];

/// The paths a binary-allowlist.txt names, one per line; `#` starts a comment line. `stop` is
/// called with a message (no path) and must not return.
export function binaryAllowlist(path, stop) {
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    stop("No readable binary-allowlist.txt.");
  }
  return new Set(text.split(/\r?\n/).filter((line) => line !== "" && !line.startsWith("#")));
}

/// What a commit changes (against its first parent): each path exactly as stored, and the new
/// blob, or null for a deletion or a submodule.
function changes(git, sha) {
  const fields = git(["diff-tree", ...diffOptions, "-r", "--raw", "-z", sha]).split("\0");
  const result = [];
  for (let index = 0; index + 1 < fields.length; index += 2) {
    // ":<old mode> <new mode> <old blob> <new blob> <status>", then the path
    const [, mode, , blob] = fields[index].slice(1).split(" ");
    const kept = !zero.test(blob) && mode !== "160000";
    result.push({ path: fields[index + 1], blob: kept ? blob : null });
  }
  return result;
}

/// Added lines of one file in one commit, with their line numbers in that commit.
function* addedLines(git, sha, path) {
  const diff = git([
    "diff-tree", ...diffOptions, "-p", "--unified=0", "--no-color", "--no-ext-diff", "--no-textconv", "--text", sha,
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

/// Appends one line per match in commit `sha` to `findings`.
export function scan(git, sha, entries, allowed, findings) {
  const short = sha.slice(0, 9);
  git(["log", "-1", "--format=%B", sha])
    .split("\n")
    .forEach((text, index) => {
      const kind = match(text, entries);
      if (kind) findings.push(`commit ${short}, message line ${index + 1}: ${kind}`);
    });
  for (const { path, blob } of changes(git, sha)) {
    const kind = match(path, entries);
    if (kind) findings.push(`commit ${short}, a file name: ${kind}`);
    const where = printable(path, entries);
    if (blob !== null && !allowed.has(path)) {
      const why = unreadable(git(["cat-file", "blob", blob], { encoding: "buffer" }));
      if (why) findings.push(`commit ${short}, ${where}: ${why}`);
    }
    for (const added of addedLines(git, sha, path)) {
      const kind = match(added.text, entries);
      if (kind) findings.push(`commit ${short}, ${where}:${added.line}: ${kind}`);
    }
  }
}
