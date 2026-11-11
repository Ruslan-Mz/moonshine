// Tests for gh-post on throwaway repositories with a fake `gh`: node --test scripts/gh-post.test.mjs
// Each test installs the guard with the repository's copy of scripts/install-guard.sh into its own
// temporary HOME (scripts/guard-fixture.mjs); the fake gh records its arguments and stdin. Every
// entry is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, linkSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { denyListFile, environment, install, installed, ok, repository, secret, slug, vault } from "./guard-fixture.mjs";

/// A repository on branch `slice/one` with the guard installed; `worktrees` are added (next to it)
/// before the install, `prunable` ones removed again so that git reports them as prunable.
function setUp({ withGh = true, worktrees = [], prunable = [] } = {}) {
  const work = repository();
  const scratchBase = join(work.root, "scratch");
  work.env = { MOONSHINE_SCRATCH_BASE: scratchBase };
  const bin = join(work.root, "bin");
  mkdirSync(bin);
  const log = join(work.root, "gh.log");
  if (withGh) {
    // It prints FAKE_GH_OUT, as gh prints what it created, and exits with FAKE_GH_STATUS.
    writeFileSync(
      join(bin, "gh"),
      `#!/bin/sh\nprintf '%s\\n' "$@" > '${log}'\ncat >> '${log}'\nprintf '%s' "$FAKE_GH_OUT"\nexit "\${FAKE_GH_STATUS:-0}"\n`,
      { mode: 0o755 },
    );
  } else {
    const git = spawnSync("/bin/sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
    symlinkSync(process.execPath, join(bin, "node"));
    symlinkSync(git, join(bin, "git"));
  }
  ok(work, "switch", "-q", "-c", "slice/one");
  for (const name of [...worktrees, ...prunable]) ok(work, "worktree", "add", "-q", join(work.root, name), "-b", name);
  for (const name of prunable) rmSync(join(work.root, name), { recursive: true });
  const installedResult = install(work, [denyListFile(work, `${secret}\nmirelbrook\n`)]);
  assert.equal(installedResult.status, 0, installedResult.stderr);
  const scratchRoot = join(scratchBase, slug(work.cwd));
  const scratchpad = join(scratchRoot, "session-1", "scratchpad");
  mkdirSync(scratchpad, { recursive: true });
  const env = environment(work.home, { PATH: `${bin}:${process.env.PATH}` });
  const postWith = (extra, ...args) =>
    spawnSync(installed(work, "bin", "gh-post"), args, {
      cwd: work.cwd,
      // Without the fake gh, PATH holds only links to node and git: a real gh is never reachable.
      env: withGh ? { ...env, ...extra } : { ...env, PATH: bin },
      encoding: "utf8",
    });
  const post = (...args) => postWith({}, ...args);
  const file = (name, text, folder = scratchpad) => {
    mkdirSync(folder, { recursive: true });
    const path = join(folder, name);
    writeFileSync(path, text);
    return path;
  };
  const sent = () => (existsSync(log) ? readFileSync(log, "utf8") : null);
  const git = (...args) => ok(work, ...args);
  const posts = () => {
    const path = installed(work, "state", "posts.jsonl");
    return existsSync(path) ? readFileSync(path, "utf8") : "";
  };
  return { root: work.root, work, scratchBase, scratchRoot, post, postWith, file, sent, git, posts };
}

function refused(context, result, ...expected) {
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /gh-post: refused/);
  for (const text of expected) assert.ok(result.stderr.includes(text), `missing "${text}" in:\n${result.stderr}`);
  for (const leak of ["quolltail", "mirelbrook"]) {
    assert.ok(!result.stderr.toLowerCase().includes(leak), `the matched text must not be printed:\n${result.stderr}`);
  }
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
    const path = join(context.scratchRoot, ...parts);
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

function editConfig(context, change) {
  const path = installed(context.work, "guard", "config.json");
  const value = JSON.parse(readFileSync(path, "utf8"));
  change(value);
  writeFileSync(path, JSON.stringify(value));
}

test("a config.json without the deny-list path refuses", () => {
  const context = setUp();
  editConfig(context, (value) => delete value.denyList);
  refused(context, context.post("comment", "27", context.file("body.md", "clean\n")), "config.json names no absolute deny-list path");
});

for (const [name, roots] of [["empty", []], ["not a list", "/tmp/x"], ["relative", ["scratch/x"]]]) {
  test(`scratchpad roots that are ${name} refuse`, () => {
    const context = setUp();
    editConfig(context, (value) => (value.scratchRoots = roots));
    refused(context, context.post("comment", "27", context.file("body.md", "clean\n")), "config.json names no absolute scratchpad roots");
  });
}

test("a file in the scratchpad of another worktree of this repository is sent", () => {
  const context = setUp({ worktrees: ["wt-2"] });
  const folder = join(context.scratchBase, slug(join(context.root, "wt-2")), "session-2", "scratchpad");
  const result = context.post("comment", "27", context.file("body.md", "from the worktree\n", folder));
  assert.equal(result.status, 0, result.stderr);
  assert.ok(context.sent().endsWith("from the worktree\n"));
});

test("a folder that only starts with the project's name is refused", () => {
  const context = setUp();
  const folder = join(`${context.scratchRoot}-x`, "session-2", "scratchpad");
  refused(context, context.post("comment", "27", context.file("body.md", "clean\n", folder)), "not inside a session scratchpad");
});

test("a prunable worktree's scratchpad is refused", () => {
  const context = setUp({ prunable: ["wt-gone"] });
  const folder = join(context.scratchBase, slug(join(context.root, "wt-gone")), "session-2", "scratchpad");
  refused(context, context.post("comment", "27", context.file("body.md", "clean\n", folder)), "not inside a session scratchpad");
});

for (const [name, content, kind] of [
  ["a NUL byte", Buffer.from("all\u0000 fixed\n"), "binary data"],
  ["UTF-16LE", Buffer.from(`\uFEFF${secret}\n`, "utf16le"), "binary data"],
  ["invalid UTF-8", Buffer.from("caf\u00e9\n", "latin1"), "invalid UTF-8"],
]) {
  test(`a body with ${name} is refused`, () => {
    const context = setUp();
    refused(context, context.post("comment", "27", context.file("body.md", content)), `The file holds ${kind}`);
  });
}

test("a body with tab, form feed and CRLF is sent", () => {
  const context = setUp();
  const result = context.post("comment", "27", context.file("body.md", "a\tb\r\nc\fd\r\n"));
  assert.equal(result.status, 0, result.stderr);
});

test("a body with a vertical tab is refused", () => {
  const context = setUp();
  refused(context, context.post("comment", "27", context.file("body.md", "a\u000bb\n")), "The file holds binary data");
});

test("an unknown command prints usage", () => {
  const context = setUp();
  const result = context.post("deploy", "27");
  assert.equal(result.status, 2);
  assert.equal(context.sent(), null);
});

test("a hard link in the scratchpad to a file outside is refused", () => {
  const context = setUp();
  const outside = join(context.root, "outside.md");
  writeFileSync(outside, "clean\n");
  const link = join(dirname(context.file("x", "")), "hard.md");
  linkSync(outside, link);
  refused(context, context.post("comment", "27", link), "more than one hard link");
});

test("pr-create on a branch whose name matches is refused", () => {
  const context = setUp();
  context.git("switch", "-q", "-c", "feat/mirelbrook-notes");
  refused(context, context.post("pr-create", "a title", context.file("body.md", "clean\n")), "the branch name: a deny-list entry");
});

test("pr-edit with a matching title is refused", () => {
  const context = setUp();
  refused(context, context.post("pr-edit", "27", context.file("body.md", "clean\n"), `about ${secret}`), "the title: a deny-list entry");
});

test("a gh that cannot be started is reported, and nothing is sent", () => {
  const context = setUp({ withGh: false });
  const result = context.post("comment", "27", context.file("body.md", "clean\n"));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /gh could not be started \(ENOENT\); nothing was sent/);
});

/// The one state line, without its time.
function onlyPost(context) {
  const lines = context.posts().split("\n").filter((line) => line !== "");
  assert.equal(lines.length, 1, context.posts());
  const { time, ...rest } = JSON.parse(lines[0]);
  assert.ok(!Number.isNaN(Date.parse(time)), lines[0]);
  return rest;
}

test("a sent comment is recorded with its PR, id and session, and none of its text", () => {
  const context = setUp();
  const out = "https://github.com/o/r/pull/27#issuecomment-555\n";
  const result = context.postWith({ FAKE_GH_OUT: out }, "comment", "27", context.file("body.md", "the answer text\n"));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, out);
  assert.deepEqual(onlyPost(context), { kind: "comment", pr: 27, id: 555, session: "session-1" });
  assert.ok(!context.posts().includes("answer text"));
});

test("a sent review is recorded with the id GitHub gave it", () => {
  const context = setUp();
  const out = JSON.stringify({ id: 901, body: "the review text" });
  const result = context.postWith({ FAKE_GH_OUT: out }, "review", "27", context.file("review.json", '{"event":"COMMENT","body":"ok"}'));
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(onlyPost(context), { kind: "review", pr: 27, id: 901, session: "session-1" });
  assert.ok(!context.posts().includes("review text"));
});

test("a created PR is recorded with its number", () => {
  const context = setUp();
  const out = "https://github.com/o/r/pull/31\n";
  const result = context.postWith({ FAKE_GH_OUT: out }, "pr-create", "a title", context.file("body.md", "text\n"));
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(onlyPost(context), { kind: "pr-create", pr: 31, id: 31, session: "session-1" });
});

test("a PR edit is not recorded", () => {
  const context = setUp();
  const result = context.postWith({ FAKE_GH_OUT: "https://github.com/o/r/pull/27\n" }, "pr-edit", "27", context.file("body.md", "x\n"));
  assert.equal(result.status, 0, result.stderr);
  assert.equal(context.posts(), "");
});

test("output gh-post cannot read records nothing and says so", () => {
  const context = setUp();
  for (const [kind, file] of [["comment", "body.md"], ["review", "review.json"]]) {
    const result = context.postWith({ FAKE_GH_OUT: "{ not an id" }, kind, "27", context.file(file, "{}"));
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /not recorded in the state file; gh-post merge refuses this PR/);
  }
  assert.equal(context.posts(), "");
});

test("a failed post records nothing", () => {
  const context = setUp();
  const result = context.postWith(
    { FAKE_GH_OUT: "https://github.com/o/r/pull/27#issuecomment-555\n", FAKE_GH_STATUS: "1" },
    "comment",
    "27",
    context.file("body.md", "x\n"),
  );
  assert.equal(result.status, 1);
  assert.equal(context.posts(), "");
});

test("the installer creates the state folder", () => {
  const context = setUp();
  assert.ok(existsSync(installed(context.work, "state")));
});
