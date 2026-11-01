// Tests for the CI guard (scripts/ci/guard-scan.mjs) on throwaway repositories:
// node --test scripts/guard-scan.test.mjs. Every deny-list entry here is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { defaultLimits, guardScan } from "./ci/guard-scan.mjs";
import { commit, environment, ok, repository, secret, vault } from "./guard-fixture.mjs";

const script = join(dirname(fileURLToPath(import.meta.url)), "ci", "guard-scan.mjs");
const denyList = `${secret}\n\nmirelbrook\n`;
const leaks = ["quolltail", "zephyrine", "mirelbrook"];

/// A repository whose `main` holds one commit, on branch `feature`.
function setUp() {
  const work = repository();
  ok(work, "switch", "-q", "-c", "feature");
  return work;
}

function head(work) {
  return ok(work, "rev-parse", "HEAD").trim();
}

function prEnv(work, extra = {}) {
  return {
    EVENT: "pull_request_target",
    BASE: "main",
    HEAD: head(work),
    PR_TITLE: "A title",
    PR_BODY: "A body\nwith two lines",
    HEAD_REF: "feature",
    HEAD_REPO: "owner/repo",
    REPOSITORY: "owner/repo",
    DENY_LIST: denyList,
    ...extra,
  };
}

function scanned(work, env, options = {}) {
  return guardScan({ env, cwd: work.cwd, gitEnv: environment(work.home, work.env), ...options });
}

function noLeak(result) {
  const text = result.lines.join("\n").toLowerCase();
  for (const leak of leaks) assert.ok(!text.includes(leak), `the matched text must not be printed:\n${text}`);
}

function found(result, ...expected) {
  assert.equal(result.status, 1, result.lines.join("\n"));
  const text = result.lines.join("\n");
  for (const part of expected) assert.ok(text.includes(part), `missing "${part}" in:\n${text}`);
  noLeak(result);
}

test("a clean PR passes and says how many commits it scanned", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\ntwo\n", "clean");
  const result = scanned(work, prEnv(work));
  assert.equal(result.status, 0, result.lines.join("\n"));
  assert.deepEqual(result.lines, ["guard: 1 commit(s) scanned, no match."]);
});

test("an entry in an added line is reported with file and line, not the text", () => {
  const work = setUp();
  commit(work, "docs/a.md", `one\nnote by ${secret.toUpperCase()}\n`, "add note");
  found(scanned(work, prEnv(work)), '"docs/a.md":2: a deny-list entry');
});

test("an entry in a commit message is reported", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", `subject\n\nthanks mirelbrook`);
  found(scanned(work, prEnv(work)), "message line 3: a deny-list entry");
});

test("an entry in a file name is reported without the name", () => {
  const work = setUp();
  commit(work, "docs/mirelbrook.md", "one\n", "add");
  found(scanned(work, prEnv(work)), "a file name: a deny-list entry");
});

test("the head branch name, the PR title and a body line are scanned", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const result = scanned(
    work,
    prEnv(work, { HEAD_REF: "fix-mirelbrook", PR_TITLE: `For ${secret}`, PR_BODY: "first\nsecond mirelbrook" }),
  );
  found(result, "the head branch name: a deny-list entry", "PR title: a deny-list entry", "PR body line 2: a deny-list entry");
});

test("a vault path in an added line is reported", () => {
  const work = setUp();
  commit(work, "docs/a.md", `see ~/${vault}/Notes/x.md\n`, "add");
  found(scanned(work, prEnv(work)), '"docs/a.md":1: a vault path');
});

test("a binary file is reported unless main's allowlist names it", () => {
  const work = setUp();
  commit(work, "assets/b.bin", "\u0000\u0001binary", "add");
  found(scanned(work, prEnv(work)), '"assets/b.bin": binary data');
  const allowlist = join(work.root, "allowlist.txt");
  writeFileSync(allowlist, "# reviewed\nassets/b.bin\n");
  assert.equal(scanned(work, prEnv(work), { allowlist }).status, 0);
});

test("a missing allowlist stops without a path", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const result = scanned(work, prEnv(work), { allowlist: join(work.root, "missing", "allowlist.txt") });
  assert.equal(result.status, 2);
  assert.ok(result.lines.join("\n").includes("binary-allowlist.txt"));
  assert.ok(!result.lines.join("\n").includes(work.root), "no path is printed");
});

test("commits already on main are not scanned again", () => {
  const work = setUp();
  ok(work, "switch", "-q", "main");
  commit(work, "docs/old.md", "by mirelbrook\n", "older, already public");
  ok(work, "switch", "-q", "feature");
  ok(work, "reset", "-q", "--hard", "main");
  commit(work, "docs/a.md", "one\n", "clean");
  assert.equal(scanned(work, prEnv(work)).status, 0);
});

for (const [name, headRepo] of [["another repository", "someone/repo"], ["a deleted fork", ""]]) {
  test(`a PR from ${name} fails without reading the deny-list`, () => {
    const work = setUp();
    commit(work, "docs/a.md", "one\n", "clean");
    const result = scanned(work, prEnv(work, { HEAD_REPO: headRepo, DENY_LIST: "" }));
    assert.equal(result.status, 1);
    assert.match(result.lines.join("\n"), /fork PR: not scanned/);
  });
}

test("an unset deny-list stops with the setup step", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const result = scanned(work, prEnv(work, { DENY_LIST: undefined }));
  assert.equal(result.status, 2);
  assert.match(result.lines.join("\n"), /DENY_LIST is not set/);
});

test("an unknown event stops", () => {
  const work = setUp();
  assert.equal(scanned(work, prEnv(work, { EVENT: "pull_request" })).status, 2);
});

test("a PR head that is not a full commit id stops", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  assert.equal(scanned(work, prEnv(work, { HEAD: "feature" })).status, 2);
});

test("the commit cap passes at the limit and fails above it", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "one");
  commit(work, "docs/b.md", "two\n", "two");
  const at = { ...defaultLimits, commits: 2 };
  assert.equal(scanned(work, prEnv(work), { limits: at }).status, 0);
  const result = scanned(work, prEnv(work), { limits: { ...at, commits: 1 } });
  assert.equal(result.status, 1);
  assert.match(result.lines.join("\n"), /too large to scan/);
});

test("the byte cap passes at the limit and fails one byte below what the scan reads", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n".repeat(50), "one");
  const full = scanned(work, prEnv(work));
  assert.equal(full.status, 0);
  assert.equal(scanned(work, prEnv(work), { limits: { ...defaultLimits, bytes: full.bytes } }).status, 0);
  const result = scanned(work, prEnv(work), { limits: { ...defaultLimits, bytes: full.bytes - 1 } });
  assert.equal(result.status, 1);
  assert.match(result.lines.join("\n"), /too large to scan/);
});

test("a push to main scans the range after the previous head", () => {
  const work = setUp();
  const before = ok(work, "rev-parse", "main").trim();
  commit(work, "docs/a.md", "by mirelbrook\n", "add");
  const env = { EVENT: "push", BEFORE: before, AFTER: head(work), DENY_LIST: denyList };
  found(scanned(work, env), '"docs/a.md":1: a deny-list entry');
});

test("a push whose previous head is unknown or not an ancestor fails", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const after = head(work);
  ok(work, "switch", "-q", "--orphan", "other");
  commit(work, "docs/b.md", "two\n", "unrelated");
  const unrelated = head(work);
  for (const before of ["0".repeat(40), unrelated]) {
    const result = scanned(work, { EVENT: "push", BEFORE: before, AFTER: after, DENY_LIST: denyList });
    assert.equal(result.status, 1);
    assert.match(result.lines.join("\n"), /cannot tell which commits are new/);
  }
});

test("a git failure prints the subcommand only, never a path or git's message", () => {
  const work = setUp();
  commit(work, "docs/mirelbrook.md", "one\n", "add");
  const blob = ok(work, "rev-parse", "HEAD:docs/mirelbrook.md").trim();
  rmSync(join(work.cwd, ".git", "objects", blob.slice(0, 2), blob.slice(2)));
  const result = scanned(work, prEnv(work));
  assert.equal(result.status, 2);
  assert.match(result.lines.join("\n"), /^git [a-z-]+ failed \(exit \d+\)\.$/);
  noLeak(result);
});

test("the command line prints the report and exits with its status", () => {
  const work = setUp();
  commit(work, "docs/a.md", "by mirelbrook\n", "add");
  const result = spawnSync(process.execPath, [script], {
    cwd: work.cwd,
    env: { ...environment(work.home, work.env), ...prEnv(work) },
    encoding: "utf8",
  });
  assert.equal(result.status, 1, result.stderr);
  assert.ok(result.stdout.includes('"docs/a.md":1: a deny-list entry'), result.stdout);
  assert.ok(!result.stdout.toLowerCase().includes("mirelbrook") && !result.stderr.toLowerCase().includes("mirelbrook"));
});
