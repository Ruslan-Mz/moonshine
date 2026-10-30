// Tests for scripts/install-guard.sh on throwaway repositories: node --test scripts/install-guard.test.mjs
// Each test runs the repository's own copy of the installer into a temporary HOME
// (scripts/guard-fixture.mjs).
import assert from "node:assert/strict";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { commit, denyListFile, git, install, installed, ok, repository, slug } from "./guard-fixture.mjs";

function setUp() {
  const work = repository();
  work.env = { MOONSHINE_SCRATCH_BASE: join(work.root, "scratch") };
  work.denyList = denyListFile(work, "zephyrine\n");
  return work;
}

function refused(work, result, expected) {
  assert.equal(result.status, 1, result.stderr);
  assert.ok(result.stderr.includes(expected), `missing "${expected}" in:\n${result.stderr}`);
  assert.ok(!existsSync(installed(work)), "nothing may be written");
  assert.notEqual(git(work, "config", "--get", "core.hooksPath").status, 0, "core.hooksPath must stay unset");
}

test("a good install writes the guard, the config and the hook, and sets core.hooksPath last", () => {
  const work = setUp();
  const result = install(work, [work.denyList]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readdirSync(installed(work, "guard")).sort(), [
    "binary-allowlist.txt",
    "config.json",
    "gh-post.mjs",
    "matcher.mjs",
    "pre-push.mjs",
  ]);
  assert.deepEqual(JSON.parse(readFileSync(installed(work, "guard", "config.json"), "utf8")), {
    denyList: work.denyList,
    scratchRoots: [join(work.root, "scratch", slug(work.cwd))],
  });
  assert.equal(ok(work, "config", "--get", "core.hooksPath").trim(), installed(work, "hooks"));
});

test("every live worktree gets a scratchpad root; a prunable one does not", () => {
  const work = setUp();
  ok(work, "worktree", "add", "-q", join(work.root, "wt-2"), "-b", "two");
  ok(work, "worktree", "add", "-q", join(work.root, "wt-gone"), "-b", "gone");
  rmSync(join(work.root, "wt-gone"), { recursive: true });
  assert.equal(install(work, [work.denyList]).status, 0);
  const config = JSON.parse(readFileSync(installed(work, "guard", "config.json"), "utf8"));
  assert.deepEqual(config.scratchRoots, [
    join(work.root, "scratch", slug(work.cwd)),
    join(work.root, "scratch", slug(join(work.root, "wt-2"))),
  ]);
});

test("a reinstall replaces the guard folder and leaves no staging folder", () => {
  const work = setUp();
  assert.equal(install(work, [work.denyList]).status, 0);
  appendFileSync(installed(work, "guard", "matcher.mjs"), "\n// edited\n");
  writeFileSync(installed(work, "guard", "stray.txt"), "x");
  const again = install(work, [work.denyList]);
  assert.equal(again.status, 0, again.stderr);
  assert.ok(!readFileSync(installed(work, "guard", "matcher.mjs"), "utf8").includes("// edited"));
  assert.ok(!existsSync(installed(work, "guard", "stray.txt")));
  assert.deepEqual(readdirSync(installed(work)).sort(), ["bin", "guard", "hooks"]);
});

for (const [name, args, expected] of [
  ["no argument", [], "usage"],
  ["two arguments", ["/a", "/b"], "usage"],
  ["a relative path", ["deny-list.txt"], "not absolute"],
  ["a path with a quote", ["/tmp/it's"], "a quote, a backslash or a control character"],
  ["a path with a control character", ["/tmp/a\u0001b"], "a quote, a backslash or a control character"],
]) {
  test(`${name} is refused`, () => {
    const work = setUp();
    refused(work, install(work, args), expected);
  });
}

test("a deny-list path that is a folder is refused", () => {
  const work = setUp();
  refused(work, install(work, [work.root]), "not a readable file");
});

test("a missing deny-list file is refused", () => {
  const work = setUp();
  refused(work, install(work, [join(work.root, "none.txt")]), "not a readable file");
});

test("an uncommitted change in scripts/guard is refused", () => {
  const work = setUp();
  appendFileSync(join(work.cwd, "scripts", "guard", "matcher.mjs"), "\n// edited\n");
  refused(work, install(work, [work.denyList]), "differs from origin's main");
});

test("a committed change in scripts/guard that is not on origin's main is refused", () => {
  const work = setUp();
  commit(work, "scripts/guard/matcher.mjs", "// replaced\n", "edit the guard");
  refused(work, install(work, [work.denyList]), "differs from origin's main");
});

test("a change to the installer itself is refused", () => {
  const work = setUp();
  commit(work, "scripts/install-guard.sh", `${readFileSync(join(work.cwd, "scripts", "install-guard.sh"), "utf8")}\n# edited\n`, "edit");
  refused(work, install(work, [work.denyList]), "differs from origin's main");
});

test("an untracked file in scripts/guard is refused", () => {
  const work = setUp();
  writeFileSync(join(work.cwd, "scripts", "guard", "extra.mjs"), "// extra\n");
  refused(work, install(work, [work.denyList]), "not on origin's main");
});

test("a stale local origin/main is refused: the remote's main is not here yet", () => {
  const work = setUp();
  const other = { ...work, cwd: join(work.root, "other") };
  ok({ ...work, cwd: work.root }, "clone", "-q", work.remote, other.cwd);
  commit(other, "b.md", "later\n", "later");
  ok(other, "push", "-q", "origin", "main");
  refused(work, install(work, [work.denyList]), "git fetch origin");
});

test("a moved local origin/main does not stand in for the remote's", () => {
  const work = setUp();
  commit(work, "scripts/guard/matcher.mjs", "// replaced\n", "edit the guard");
  ok(work, "update-ref", "refs/remotes/origin/main", "HEAD");
  refused(work, install(work, [work.denyList]), "differs from origin's main");
});

test("a remote without main is refused", () => {
  const work = setUp();
  ok({ ...work, cwd: work.remote }, "update-ref", "-d", "refs/heads/main");
  refused(work, install(work, [work.denyList]), "origin has no main");
});

test("running the installer from another repository is refused", () => {
  const work = setUp();
  const elsewhere = join(work.root, "elsewhere");
  mkdirSync(elsewhere);
  ok({ ...work, cwd: elsewhere }, "init", "-q");
  refused(work, install(work, [work.denyList], elsewhere), "the repository that holds it");
});
