// Tests for gh-post on throwaway repositories with a fake `gh`: node --test scripts/gh-post.test.mjs
// Each test installs the guard with scripts/install-guard.sh into its own temporary HOME; git reads
// no global or system config; the fake gh records its arguments and stdin. Every entry is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const install = join(dirname(fileURLToPath(import.meta.url)), "install-guard.sh");
const secret = "Zephyrine Quolltail";
const vault = "Obsidian" + "V"; // spelled in two parts so this file passes the guard itself

function setUp({ configure = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), "gh-post-"));
  const home = join(root, "home");
  const bin = join(root, "bin");
  const work = join(root, "work");
  const scratchRoot = join(root, "scratch");
  const scratchpad = join(scratchRoot, "session-1", "scratchpad");
  for (const dir of [home, bin, work, scratchpad]) mkdirSync(dir, { recursive: true });
  const log = join(root, "gh.log");
  writeFileSync(join(bin, "gh"), `#!/bin/sh\nprintf '%s\\n' "$@" > '${log}'\ncat >> '${log}'\n`, { mode: 0o755 });
  const env = {
    ...process.env,
    HOME: home,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    PATH: `${bin}:${process.env.PATH}`,
    MOONSHINE_SCRATCH_ROOT: scratchRoot,
  };
  const git = (...args) => assert.equal(spawnSync("git", args, { cwd: work, env }).status, 0, args.join(" "));
  git("init", "-q", "-b", "slice/one");
  const installed = spawnSync("/bin/sh", [install], { cwd: work, env, encoding: "utf8" });
  assert.equal(installed.status, 0, installed.stderr);
  if (configure) {
    writeFileSync(join(root, "deny-list.txt"), `${secret}\n`);
    git("config", "moonshine.denyList", join(root, "deny-list.txt"));
  }
  const post = (...args) =>
    spawnSync(join(home, ".config", "moonshine", "bin", "gh-post"), args, { cwd: work, env, encoding: "utf8" });
  const file = (name, text) => {
    const path = join(scratchpad, name);
    writeFileSync(path, text);
    return path;
  };
  const sent = () => (existsSync(log) ? readFileSync(log, "utf8") : null);
  return { root, post, file, sent };
}

function refused(context, result, ...expected) {
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /gh-post: refused/);
  for (const text of expected) assert.ok(result.stderr.includes(text), `missing "${text}" in:\n${result.stderr}`);
  assert.ok(!result.stderr.toLowerCase().includes("quolltail"), `the matched text must not be printed:\n${result.stderr}`);
  assert.equal(context.sent(), null, "nothing may reach gh");
}

test("a clean comment is sent to gh on stdin", () => {
  const context = setUp();
  const result = context.post("comment", "27", context.file("body.md", "all fixed\n"));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(context.sent(), "pr\ncomment\n27\n--body-file\n-\nall fixed\n");
});

test("a review goes to the reviews endpoint", () => {
  const context = setUp();
  const result = context.post("review", "27", context.file("review.json", '{"event":"COMMENT","body":"ok"}'));
  assert.equal(result.status, 0, result.stderr);
  assert.ok(context.sent().startsWith("api\n--method\nPOST\nrepos/{owner}/{repo}/pulls/27/reviews\n--input\n-\n"));
});

test("a PR is created from the current branch into main", () => {
  const context = setUp();
  const result = context.post("pr-create", "chore: a title", context.file("body.md", "text\n"));
  assert.equal(result.status, 0, result.stderr);
  assert.ok(context.sent().startsWith("pr\ncreate\n--base\nmain\n--head\nslice/one\n--title\nchore: a title\n--body-file\n-\n"));
});

test("a PR body and title are edited", () => {
  const context = setUp();
  const result = context.post("pr-edit", "27", context.file("body.md", "text\n"), "new title");
  assert.equal(result.status, 0, result.stderr);
  assert.ok(context.sent().startsWith("pr\nedit\n27\n--body-file\n-\n--title\nnew title\n"));
});

test("a file outside the scratchpad is refused", () => {
  const context = setUp();
  const outside = join(context.root, "outside.md");
  writeFileSync(outside, "clean\n");
  refused(context, context.post("comment", "27", outside), "not inside a session scratchpad");
});

test("a symlink in the scratchpad that points outside is refused", () => {
  const context = setUp();
  const outside = join(context.root, "outside.md");
  writeFileSync(outside, "clean\n");
  const link = join(dirname(context.file("x", "")), "link.md");
  symlinkSync(outside, link);
  refused(context, context.post("comment", "27", link), "not inside a session scratchpad");
});

for (const parts of [["session-1", "body.md"], ["session-1", "notes", "body.md"]]) {
  test(`a file in a session folder but outside its scratchpad (${parts.join("/")}) is refused`, () => {
    const context = setUp();
    const path = join(context.root, "scratch", ...parts);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "clean\n");
    refused(context, context.post("comment", "27", path), "not inside a session scratchpad");
  });
}

test("a deny-list line in the body is refused with its line number only", () => {
  const context = setUp();
  refused(context, context.post("comment", "27", context.file("body.md", `ok\nby ${secret}\n`)), "body line 2: a deny-list entry");
});

test("a vault path in the body is refused", () => {
  const context = setUp();
  refused(context, context.post("comment", "27", context.file("body.md", `see ~/${vault}/Projects/Plan.md\n`)), "a vault path");
});

test("a matching title is refused", () => {
  const context = setUp();
  refused(context, context.post("pr-create", `about ${secret}`, context.file("body.md", "clean\n")), "the title: a deny-list entry");
});

test("an entry hidden by JSON escapes in a review is refused", () => {
  const context = setUp();
  const escaped = [...secret].map((c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`).join("");
  refused(context, context.post("review", "27", context.file("review.json", `{"body":"${escaped}"}`)), "decoded JSON string");
});

test("a bad PR number is refused", () => {
  const context = setUp();
  for (const pr of ["0", "-1", "27x", "123456789"]) {
    refused(context, context.post("comment", pr, context.file("body.md", "clean\n")), "PR number");
  }
});

test("a missing deny-list setting refuses", () => {
  const context = setUp({ configure: false });
  refused(context, context.post("comment", "27", context.file("body.md", "clean\n")), "git config moonshine.denyList");
});

test("an unknown command prints usage", () => {
  const context = setUp();
  const result = context.post("merge", "27");
  assert.equal(result.status, 2);
  assert.equal(context.sent(), null);
});
