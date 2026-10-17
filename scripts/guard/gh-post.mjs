// gh-post: the one way a session sends text to GitHub (CLAUDE.md → "Asking the owner"). The owner
// installs it with scripts/install-guard.sh; the installed copy reads `config.json` next to itself.
// Tests: node --test scripts/gh-post.test.mjs
//
//   gh-post comment <pr> <file>            a PR comment
//   gh-post review <pr> <file>             a review (JSON for POST …/pulls/<pr>/reviews)
//   gh-post pr-create <title> <file>       a PR from the current branch into main
//   gh-post pr-edit <pr> <file> [<title>]  a new PR body (and title)
//
// The file must resolve (after symlinks) to a file inside a session scratchpad of this project. Its
// text, the title and the branch name are scanned with the deny-list and vault-path matcher; a match
// refuses the post and prints kinds and line numbers only. gh gets the bytes that were scanned, on
// stdin, so the file cannot change in between.
import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { denyList, match } from "./matcher.mjs";

const maxBytes = 1 << 20;
const maxTitle = 256;

function refuse(message) {
  process.stderr.write(`gh-post: refused. ${message}\n`);
  process.exit(1);
}

function usage() {
  process.stderr.write(
    "usage: gh-post comment <pr> <file> | review <pr> <file> | pr-create <title> <file> | pr-edit <pr> <file> [<title>]\n",
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

/// The scratchpad root this copy was installed for: /private/tmp/claude-<uid>/<project slug>.
function scratchRoot() {
  let config;
  try {
    config = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "config.json"), "utf8"));
  } catch {
    refuse("No config.json next to gh-post; run scripts/install-guard.sh.");
  }
  if (typeof config?.scratchRoot !== "string" || config.scratchRoot === "") refuse("config.json names no scratchRoot.");
  try {
    return realpathSync(config.scratchRoot);
  } catch {
    refuse("The scratchpad root in config.json does not exist.");
  }
}

/// The file's text, if it lies in <root>/<session>/scratchpad/.
function scratchpadText(file) {
  if (typeof file !== "string" || file === "") usage();
  let real;
  try {
    real = realpathSync(file);
  } catch {
    refuse("The file does not exist.");
  }
  const parts = relative(scratchRoot(), real).split(sep);
  if (parts[0] === ".." || parts.length < 3 || parts[0] === "" || parts[1] !== "scratchpad") {
    refuse("The file is not inside a session scratchpad of this project.");
  }
  const info = statSync(real);
  if (!info.isFile()) refuse("The path is not a regular file.");
  if (info.size > maxBytes) refuse("The file is larger than 1 MB.");
  return readFileSync(real, "utf8");
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

function currentBranch() {
  const result = spawnSync("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], { encoding: "utf8" });
  const branch = result.status === 0 ? result.stdout.trim() : "";
  if (branch === "") refuse("HEAD is not on a branch.");
  return branch;
}

const [command, ...rest] = process.argv.slice(2);
let args;
let text;
const checks = [];
switch (command) {
  case "comment":
    if (rest.length !== 2) usage();
    text = scratchpadText(rest[1]);
    args = ["pr", "comment", prNumber(rest[0]), "--body-file", "-"];
    break;
  case "review":
    if (rest.length !== 2) usage();
    text = scratchpadText(rest[1]);
    args = ["api", "--method", "POST", `repos/{owner}/{repo}/pulls/${prNumber(rest[0])}/reviews`, "--input", "-"];
    checks.push("json");
    break;
  case "pr-create": {
    if (rest.length !== 2) usage();
    const branch = currentBranch();
    checks.push(["title", checkTitle(rest[0])], ["branch name", branch]);
    text = scratchpadText(rest[1]);
    args = ["pr", "create", "--base", "main", "--head", branch, "--title", rest[0], "--body-file", "-"];
    break;
  }
  case "pr-edit":
    if (rest.length !== 2 && rest.length !== 3) usage();
    text = scratchpadText(rest[1]);
    args = ["pr", "edit", prNumber(rest[0]), "--body-file", "-"];
    if (rest.length === 3) {
      checks.push(["title", checkTitle(rest[2])]);
      args.push("--title", rest[2]);
    }
    break;
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

const sent = spawnSync("gh", args, { input: text, stdio: ["pipe", "inherit", "inherit"] });
process.exit(sent.status ?? 1);
