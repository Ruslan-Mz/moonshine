// gh-post: the one way a session sends text to GitHub (CLAUDE.md → "Asking the owner"). The owner
// installs it with scripts/install-guard.sh; the installed copy reads `config.json` next to itself.
// Tests: node --test scripts/gh-post.test.mjs
//
//   gh-post comment <pr> <file>            a PR comment
//   gh-post review <pr> <file>             a review (JSON for POST …/pulls/<pr>/reviews)
//   gh-post pr-create <title> <file>       a PR from the current branch into main
//   gh-post pr-edit <pr> <file> [<title>]  a new PR body (and title)
//   gh-post merge <pr>                     merges a plain PR (merge.mjs), or refuses
//
// The file must resolve (after symlinks) to a file inside a session scratchpad of this repository:
// of its main checkout or of a worktree the installer listed. It must be UTF-8 text (no binary
// data). Its text, the title and the branch name are scanned with the deny-list and vault-path
// matcher; a match refuses the post and prints kinds and line numbers only. gh gets the bytes that
// were scanned, on stdin, so the file cannot change in between. After a comment, a review or a PR
// is sent, one line goes to the state file (merge.mjs): its kind, PR, id and session, no text.
import { spawnSync } from "node:child_process";
import { closeSync, constants, fstatSync, openSync, readFileSync, realpathSync } from "node:fs";
import { relative, sep } from "node:path";
import { config, denyList, match, unreadable } from "./matcher.mjs";
import { merge, recordPost } from "./merge.mjs";

const maxBytes = 1 << 20;
const maxTitle = 256;

function refuse(message) {
  process.stderr.write(`gh-post: refused. ${message}\n`);
  process.exit(1);
}

function usage() {
  process.stderr.write(
    "usage: gh-post comment <pr> <file> | review <pr> <file> | pr-create <title> <file> | pr-edit <pr> <file> [<title>] | merge <pr>\n",
  );
  process.exit(2);
}

function prNumber(text) {
  if (!/^[1-9][0-9]{0,6}$/.test(text ?? "")) refuse("The PR number must be a positive whole number below 10 000 000.");
  return text;
}

function checkTitle(title) {
  if (typeof title !== "string" || title.length === 0 || title.length > maxTitle || /[\u0000-\u001f\u007f]/.test(title)) {
    refuse(`The title must be 1 to ${maxTitle} characters on one line.`);
  }
  return title;
}

/// The scratchpad roots this copy was installed for, one per worktree
/// (/private/tmp/claude-<uid>/<project slug>), that exist.
function scratchRoots() {
  return config(refuse).scratchRoots.flatMap((root) => {
    try {
      return [realpathSync(root)];
    } catch {
      return []; // no session has run in that worktree yet
    }
  });
}

/// The file's text and its session folder's name, if it lies in <root>/<session>/scratchpad/ of
/// one of the roots.
function scratchpadText(file) {
  if (typeof file !== "string" || file === "") usage();
  let real;
  try {
    real = realpathSync(file);
  } catch {
    refuse("The file does not exist.");
  }
  let session = null;
  for (const root of scratchRoots()) {
    const parts = relative(root, real).split(sep);
    if (parts[0] !== ".." && parts.length >= 3 && parts[0] !== "" && parts[1] === "scratchpad") session = parts[0];
  }
  if (session === null) refuse("The file is not inside a session scratchpad of this project.");
  // Read through one descriptor, opened without following a link: a hard link has no path of its
  // own to check, so a file with more than one link is refused.
  let fd;
  try {
    fd = openSync(real, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch {
    refuse("The file cannot be opened.");
  }
  try {
    const info = fstatSync(fd);
    if (!info.isFile()) refuse("The path is not a regular file.");
    if (info.nlink !== 1) refuse("The file has more than one hard link.");
    if (info.size > maxBytes) refuse("The file is larger than 1 MB.");
    const bytes = readFileSync(fd);
    const why = unreadable(bytes);
    if (why) refuse(`The file holds ${why}.`);
    return { text: bytes.toString("utf8"), session };
  } finally {
    closeSync(fd);
  }
}

function scanText(text, label, entries, findings) {
  text.split("\n").forEach((line, index) => {
    const kind = match(line, entries);
    if (kind) findings.push(`${label} line ${index + 1}: ${kind}`);
  });
}

/// Every string in a review JSON, decoded: `\u` escapes would hide an entry from the line scan.
function scanJSON(text, entries, findings) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    refuse("The review file is not valid JSON.");
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) refuse("The review JSON must be an object.");
  let count = 0;
  const walk = (node) => {
    if (typeof node === "string") {
      const kind = match(node, entries);
      if (kind) count += 1;
    } else if (node !== null && typeof node === "object") {
      for (const [key, child] of Object.entries(node)) {
        walk(key);
        walk(child);
      }
    }
  };
  walk(value);
  if (count > 0) findings.push(`${count} decoded JSON string(s): a deny-list entry or a vault path`);
}

/// The id GitHub gave a posted review, from the JSON gh prints.
function reviewId(out) {
  try {
    const id = JSON.parse(out).id;
    return Number.isSafeInteger(id) && id > 0 ? String(id) : undefined;
  } catch {
    return undefined;
  }
}

function currentBranch() {
  const result = spawnSync("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], { encoding: "utf8" });
  const branch = result.status === 0 ? result.stdout.trim() : "";
  if (branch === "") refuse("HEAD is not on a branch.");
  return branch;
}

const [command, ...rest] = process.argv.slice(2);
let args;
let text;
let session;
let recorded = null; // the kind the state file records, and how gh's output names the post
const checks = [];
switch (command) {
  case "comment":
    if (rest.length !== 2) usage();
    ({ text, session } = scratchpadText(rest[1]));
    args = ["pr", "comment", prNumber(rest[0]), "--body-file", "-"];
    recorded = { kind: "comment", pr: rest[0], id: (out) => /#issuecomment-([1-9][0-9]*)\s*$/.exec(out)?.[1] };
    break;
  case "review":
    if (rest.length !== 2) usage();
    ({ text, session } = scratchpadText(rest[1]));
    args = ["api", "--method", "POST", `repos/{owner}/{repo}/pulls/${prNumber(rest[0])}/reviews`, "--input", "-"];
    checks.push("json");
    recorded = { kind: "review", pr: rest[0], id: reviewId };
    break;
  case "pr-create": {
    if (rest.length !== 2) usage();
    const branch = currentBranch();
    checks.push(["title", checkTitle(rest[0])], ["branch name", branch]);
    ({ text, session } = scratchpadText(rest[1]));
    recorded = { kind: "pr-create", pr: null, id: (out) => /\/pull\/([1-9][0-9]*)\s*$/.exec(out)?.[1] };
    args = ["pr", "create", "--base", "main", "--head", branch, "--title", rest[0], "--body-file", "-"];
    break;
  }
  case "pr-edit":
    if (rest.length !== 2 && rest.length !== 3) usage();
    ({ text, session } = scratchpadText(rest[1]));
    args = ["pr", "edit", prNumber(rest[0]), "--body-file", "-"];
    if (rest.length === 3) {
      checks.push(["title", checkTitle(rest[2])]);
      args.push("--title", rest[2]);
    }
    break;
  case "merge":
    if (rest.length !== 1) usage();
    process.exit(merge(prNumber(rest[0]), refuse));
  default:
    usage();
}

const entries = denyList(refuse);
const findings = [];
for (const check of checks) {
  if (check === "json") {
    scanJSON(text, entries, findings);
  } else {
    const kind = match(check[1], entries);
    if (kind) findings.push(`the ${check[0]}: ${kind}`);
  }
}
scanText(text, "body", entries, findings);
if (findings.length > 0) refuse(`${findings.length} match(es):\n${findings.map((f) => `  ${f}`).join("\n")}`);

const sent = spawnSync("gh", args, { input: text, stdio: ["pipe", "pipe", "inherit"], encoding: "utf8", maxBuffer: 1 << 26 });
if (sent.error) {
  process.stderr.write(`gh-post: gh could not be started (${sent.error.code ?? "unknown error"}); nothing was sent.\n`);
  process.exit(1);
}
process.stdout.write(sent.stdout ?? "");
if (sent.status === 0 && recorded) {
  // A created PR's number is the id; a comment and a review name their PR.
  const id = recorded.id(sent.stdout ?? "");
  if (!id || !recordPost(recorded.kind, Number(recorded.pr ?? id), Number(id), session)) {
    process.stderr.write("gh-post: sent, but not recorded in the state file; gh-post merge refuses this PR, and the owner merges it.\n");
  }
}
process.exit(sent.status ?? 1);
