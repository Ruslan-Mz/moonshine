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

const base = "refs/remotes/origin/main";

/// A repository whose `main` holds one commit, on branch `feature`.
function setUp() {
  const work = repository();
  ok(work, "switch", "-q", "-c", "feature");
  return work;
}

function head(work) {
  return ok(work, "rev-parse", "HEAD").trim();
}

/// The event of a PR from `feature`: commit ids in the environment, and the branch name, title and
/// body in an event file, as the workflow passes them. `origin/main` is set to `main` here, as the
/// workflow's checkout fetches it.
function prEnv(work, extra = {}, pr = {}) {
  ok(work, "update-ref", base, "main");
  const event = join(work.root, "event.json");
  const pull = { title: "A title", body: "A body\nwith two lines", head: { ref: "feature" }, ...pr };
  writeFileSync(event, JSON.stringify({ pull_request: pull }));
  return {
    EVENT: "pull_request_target",
    BASE: base,
    HEAD: head(work),
    HEAD_REPO: "owner/repo",
    REPOSITORY: "owner/repo",
    GITHUB_EVENT_PATH: event,
    DENY_LIST: denyList,
    ...extra,
  };
}

/// The scan run from a checkout of `main`, as the workflow runs it, so that a scan which read the
/// checkout's HEAD instead of the event's head would find nothing to scan.
function scanned(work, env, options = {}) {
  const branch = ok(work, "branch", "--show-current").trim();
  ok(work, "switch", "-q", "--detach", "main");
  try {
    return guardScan({ env, cwd: work.cwd, gitEnv: environment(work.home, work.env), ...options });
  } finally {
    try {
      ok(work, "switch", "-q", branch);
    } catch {
      // A test that removed an object of the branch cannot switch back; it scans once.
    }
  }
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
  commit(work, "docs/b.md", "three\n", "also clean");
  const result = scanned(work, prEnv(work));
  assert.equal(result.status, 0, result.lines.join("\n"));
  assert.deepEqual(result.lines, ["guard: 2 commit(s) scanned, no match."]);
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
    prEnv(work, {}, { head: { ref: "fix-mirelbrook" }, title: `For ${secret}`, body: "first\nsecond mirelbrook" }),
  );
  found(result, "the head branch name: a deny-list entry", "PR title: a deny-list entry", "PR body line 2: a deny-list entry");
});

test("the PR text comes from the event file, never from the environment", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const ignored = { HEAD_REF: "fix-mirelbrook", PR_TITLE: `For ${secret}`, PR_BODY: "mirelbrook" };
  assert.equal(scanned(work, prEnv(work, ignored, { body: null })).status, 0);
});

test("a missing or malformed event file stops", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n", "clean");
  const malformed = [{ GITHUB_EVENT_PATH: join(work.root, "missing.json") }, {}];
  for (const [index, pr] of [{}, { title: 7 }, { head: {} }, { body: ["x"] }].entries()) {
    const env = index === 0 ? prEnv(work, malformed[0]) : prEnv(work, {}, pr);
    const result = scanned(work, env);
    assert.equal(result.status, 2, JSON.stringify(pr));
    assert.deepEqual(result.lines, ["The event file is missing or malformed."]);
  }
});

test("a tag named like the base does not shadow it", () => {
  const work = setUp();
  commit(work, "docs/a.md", "by mirelbrook\n", "add");
  ok(work, "tag", "origin/main", "HEAD");
  found(scanned(work, prEnv(work)), '"docs/a.md":1: a deny-list entry');
  for (const short of ["origin/main", "main", "refs/heads/main", "refs/remotes/../main"]) {
    assert.equal(scanned(work, prEnv(work, { BASE: short })).status, 2, short);
  }
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
  const result = scanned(work, prEnv(work));
  assert.deepEqual(result.lines, ["guard: 1 commit(s) scanned, no match."]);
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

test("the diff budget passes at the limit and fails one byte below what the scan reads", () => {
  const work = setUp();
  commit(work, "docs/a.md", "one\n".repeat(50), "one");
  const full = scanned(work, prEnv(work));
  assert.equal(full.status, 0);
  assert.equal(scanned(work, prEnv(work), { limits: { ...defaultLimits, bytes: full.bytes } }).status, 0);
  const result = scanned(work, prEnv(work), { limits: { ...defaultLimits, bytes: full.bytes - 1 } });
  assert.equal(result.status, 1);
  assert.match(result.lines.join("\n"), /too large to scan/);
});

test("a large file that changes by a few lines counts its diff, not its content", () => {
  const work = setUp();
  const large = "a line of an invented log, long enough to add up\n".repeat(30_000);
  assert.ok(large.length > 1024 * 1024 && large.length < defaultLimits.fileBytes);
  for (let index = 0; index < 8; index += 1) commit(work, "docs/log.md", `${large}row ${index}\n`, `row ${index}`);
  const result = scanned(work, prEnv(work));
  assert.equal(result.status, 0, result.lines.join("\n"));
  assert.ok(8 * large.length > defaultLimits.bytes, "the contents alone would exceed the diff budget");
  assert.ok(result.bytes < defaultLimits.fileBytes, `diff bytes: ${result.bytes}`);
});

test("the per-file cap passes a file at the limit and fails one above it", () => {
  const work = setUp();
  ok(work, "switch", "-q", "main");
  commit(work, "docs/log.md", "an invented row\n".repeat(200), "a large file on main");
  ok(work, "switch", "-q", "feature");
  ok(work, "reset", "-q", "--hard", "main");
  commit(work, "docs/log.md", "an invented row\n".repeat(200) + "one more\n", "a few lines more");
  const size = Number(ok(work, "cat-file", "-s", "HEAD:docs/log.md").trim());
  assert.equal(scanned(work, prEnv(work), { limits: { ...defaultLimits, fileBytes: size } }).status, 0);
  const result = scanned(work, prEnv(work), { limits: { ...defaultLimits, fileBytes: size - 1 } });
  assert.equal(result.status, 1);
  assert.deepEqual(result.lines, ["too large to scan; the owner scans it locally."]);
});

test("a patch above the per-file cap fails though the file is below it", () => {
  const work = setUp();
  ok(work, "switch", "-q", "main");
  commit(work, "docs/a.md", "an invented row\n".repeat(200), "on main");
  ok(work, "switch", "-q", "feature");
  ok(work, "reset", "-q", "--hard", "main");
  commit(work, "docs/a.md", "another made-up\n".repeat(200), "every line replaced");
  const size = Number(ok(work, "cat-file", "-s", "HEAD:docs/a.md").trim());
  const limits = { ...defaultLimits, fileBytes: size + 500 };
  const result = scanned(work, prEnv(work), { limits });
  assert.equal(result.status, 1);
  assert.deepEqual(result.lines, ["too large to scan; the owner scans it locally."]);
});

test("a push to main scans the range after the previous head, and nothing before it", () => {
  const work = setUp();
  commit(work, "docs/old.md", "by mirelbrook\n", "older, already on main");
  const before = head(work);
  commit(work, "docs/a.md", "by mirelbrook\n", "add");
  const env = { EVENT: "push", BEFORE: before, AFTER: head(work), DENY_LIST: denyList };
  const result = scanned(work, env);
  found(result, '"docs/a.md":1: a deny-list entry');
  assert.ok(!result.lines.join("\n").includes("docs/old.md"), result.lines.join("\n"));
  commit(work, "docs/b.md", "clean\n", "clean");
  const clean = scanned(work, { ...env, BEFORE: env.AFTER, AFTER: head(work) });
  assert.deepEqual(clean.lines, ["guard: 1 commit(s) scanned, no match."]);
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
