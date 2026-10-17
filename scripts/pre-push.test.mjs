// Tests for the pre-push guard on throwaway repositories: node --test scripts/pre-push.test.mjs
// Every deny-list entry here is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const hooks = join(dirname(fileURLToPath(import.meta.url)), "git-hooks");
const secret = "Zephyrine Quolltail";
const vault = "Obsidian" + "V"; // spelled in two parts so this file passes the guard itself

function git(cwd, ...args) {
  const result = spawnSync(
    "git",
    ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "init.defaultBranch=main", ...args],
    { cwd, encoding: "utf8" },
  );
  return result;
}

function ok(cwd, ...args) {
  const result = git(cwd, ...args);
  assert.equal(result.status, 0, `git ${args.join(" ")}\n${result.stderr}`);
  return result.stdout;
}

/// A working repository with one pushed commit on `main`, a bare remote, the hook and a deny-list.
function setUp({ denyList = `${secret}\n\nкирилл тест\n`, configure = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), "pre-push-"));
  const remote = join(root, "remote.git");
  const work = join(root, "work");
  ok(root, "init", "--bare", remote);
  ok(root, "init", work);
  ok(work, "remote", "add", "origin", remote);
  commit(work, "README.md", "hello\n", "first");
  ok(work, "push", "origin", "main");
  ok(work, "fetch", "origin");
  ok(work, "switch", "-c", "feature");
  ok(work, "config", "core.hooksPath", hooks);
  if (configure) {
    const list = join(root, "deny-list.txt");
    if (denyList !== null) writeFileSync(list, denyList);
    ok(work, "config", "moonshine.denyList", list);
  }
  return work;
}

function commit(work, path, text, message) {
  mkdirSync(dirname(join(work, path)), { recursive: true });
  writeFileSync(join(work, path), text);
  ok(work, "add", "--", path);
  ok(work, "commit", "-q", "-m", message);
}

function push(work, refspec = "feature") {
  return git(work, "push", "origin", refspec);
}

function blocked(result, ...expected) {
  assert.notEqual(result.status, 0, result.stderr);
  assert.match(result.stderr, /pre-push: push blocked/);
  for (const text of expected) assert.ok(result.stderr.includes(text), `missing "${text}" in:\n${result.stderr}`);
  assert.ok(!result.stderr.toLowerCase().includes(secret.toLowerCase()), "the matched text must not be printed");
  assert.ok(!result.stderr.includes("кирилл"), "the matched text must not be printed");
}

test("a clean commit pushes", () => {
  const work = setUp();
  commit(work, "docs/a.md", "line one\nline two\n", "clean");
  const result = push(work);
  assert.equal(result.status, 0, result.stderr);
});

test("a deny-list line in an added line blocks with file and line, not the text", () => {
  const work = setUp();
  commit(work, "docs/a.md", `one\ntwo\nnote by ${secret.toUpperCase()} here\n`, "add note");
  blocked(push(work), "docs/a.md:3", "a deny-list entry");
});

test("matching ignores case beyond ASCII", () => {
  const work = setUp();
  commit(work, "a.txt", "x КИРИЛЛ ТЕСТ y\n", "cyrillic");
  blocked(push(work), "a.txt:1");
});

test("a line added in one commit and removed in the next still blocks", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "add");
  commit(work, "a.md", "clean\n", "remove");
  blocked(push(work), "a.md:1");
});

test("a commit message line blocks", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", `subject\n\nbody mentions ${secret}`);
  blocked(push(work), "message line 3");
});

test("a file name that matches is reported without the name", () => {
  const work = setUp();
  commit(work, `notes/${secret}.md`, "clean\n", "file");
  const result = push(work);
  blocked(result, "a file name: a deny-list entry");
});

test("a path inside the vault blocks; the vault's default location alone does not", () => {
  const inside = setUp();
  commit(inside, "a.md", `see ~/${vault}/Projects/Plan.md\n`, "path");
  blocked(push(inside), "a.md:1", "a vault path");

  const absolute = setUp();
  commit(absolute, "a.md", `root /Users/someone/${vault} here\n`, "path");
  blocked(push(absolute), "a.md:1", "a vault path");

  const root = setUp();
  commit(root, "a.md", `the vault (\`~/${vault}\`) and ${vault}Vault types\n`, "default");
  assert.equal(push(root).status, 0);
});

test("commits already on the remote are not scanned again", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "old");
  ok(work, "push", "--no-verify", "origin", "feature");
  ok(work, "fetch", "origin");
  commit(work, "b.md", "clean\n", "new");
  assert.equal(push(work).status, 0);
});

test("a push to main is blocked", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work, "feature:main"), "main changes through a merged pull request");
});

test("a deletion of a feature branch is allowed", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  assert.equal(push(work).status, 0);
  assert.equal(push(work, ":feature").status, 0);
});

test("a missing setting blocks", () => {
  const work = setUp({ configure: false });
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "git config moonshine.denyList");
});

test("a missing deny-list file blocks", () => {
  const work = setUp({ denyList: null });
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "cannot be read");
});

test("an empty deny-list blocks", () => {
  const work = setUp({ denyList: "\n  \n" });
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "has no entries");
});
