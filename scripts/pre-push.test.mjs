// Tests for the pre-push guard on throwaway repositories: node --test scripts/pre-push.test.mjs
// Each test installs the guard with the repository's copy of scripts/install-guard.sh into its own
// temporary HOME (scripts/guard-fixture.mjs). Every deny-list entry here is invented.
import assert from "node:assert/strict";
import { appendFileSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { commit, denyListFile, install, installed, ok, git, repository, secret, vault } from "./guard-fixture.mjs";

/// A working repository on branch `feature`, with the guard installed and a deny-list.
function setUp({ denyList = `${secret}\n\nкирилл тест\nmirelbrook\n` } = {}) {
  const work = repository();
  ok(work, "switch", "-q", "-c", "feature");
  work.denyList = denyListFile(work, denyList);
  const result = install(work, [work.denyList]);
  assert.equal(result.status, 0, result.stderr);
  return work;
}

function push(work, ...refspecs) {
  return git(work, "push", "origin", ...(refspecs.length ? refspecs : ["feature"]));
}

function passes(result) {
  assert.equal(result.status, 0, result.stderr);
}

function blocked(result, ...expected) {
  assert.notEqual(result.status, 0, result.stderr);
  assert.match(result.stderr, /pre-push: push blocked/);
  for (const text of expected) assert.ok(result.stderr.includes(text), `missing "${text}" in:\n${result.stderr}`);
  const lower = result.stderr.toLowerCase();
  for (const leak of [secret.toLowerCase(), "quolltail", "кирилл", "mirelbrook", "projects/plan"]) {
    assert.ok(!lower.includes(leak), `the matched text must not be printed:\n${result.stderr}`);
  }
}

test("a clean commit pushes", () => {
  const work = setUp();
  commit(work, "docs/a.md", "line one\nline two\n", "clean");
  passes(push(work));
});

test("a deny-list line in an added line blocks with file and line, not the text", () => {
  const work = setUp();
  commit(work, "docs/a.md", `one\ntwo\nnote by ${secret.toUpperCase()} here\n`, "add note");
  blocked(push(work), '"docs/a.md":3', "a deny-list entry");
});

test("matching ignores case beyond ASCII", () => {
  const work = setUp();
  commit(work, "a.txt", "x КИРИЛЛ ТЕСТ y\n", "cyrillic");
  blocked(push(work), '"a.txt":1');
});

test("a line added in one commit and removed in the next still blocks", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "add");
  commit(work, "a.md", "clean\n", "remove");
  blocked(push(work), '"a.md":1');
});

test("a commit message line blocks", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", `subject\n\nbody mentions ${secret}`);
  blocked(push(work), "message line 3");
});

test("a matching file name is reported without the name", () => {
  const work = setUp();
  commit(work, `notes/${secret}.md`, "clean\n", "file");
  blocked(push(work), "a file name: a deny-list entry");
});

test("a matching name with a space and matching content prints neither", () => {
  const work = setUp();
  commit(work, `notes/${secret} draft.md`, `about ${secret}\n`, "file");
  blocked(push(work), "a file name: a deny-list entry", "a file whose name matches:1");
});

test("a matching name with a quote is flagged as a file name", () => {
  const work = setUp();
  commit(work, `notes/"${secret}".md`, `about ${secret}\n`, "file");
  blocked(push(work), "a file name: a deny-list entry", "a file whose name matches:1");
});

test("a clean name with a space and a quote is printed quoted", () => {
  const work = setUp();
  commit(work, 'notes/my "plan" a.md', `about ${secret}\n`, "file");
  blocked(push(work), '"notes/my \\"plan\\" a.md":1');
});

for (const [name, line] of [
  ["inside the vault", `see ~/${vault}/Projects/Plan.md`],
  ["an absolute vault path", `root /Users/someone/${vault} here`],
  ["a lower-case vault path", `see ~/${vault.toLowerCase()}/Projects/Plan.md`],
  ["a JSON-escaped vault path", `"\\/Users\\/someone\\/${vault}\\/Projects\\/Plan.md"`],
  ["a URL-encoded vault path", `~%2F${vault}%2FProjects%2FPlan.md`],
  ["an Obsidian link to a note", "obsidian" + "://open?vault=" + vault + "&file=" + "Projects%2FPlan"],
]) {
  test(`${name} blocks`, () => {
    const work = setUp();
    commit(work, "a.md", `${line}\n`, "path");
    blocked(push(work), '"a.md":1', "a vault path");
  });
}

test("the vault's default location and link templates pass", () => {
  const work = setUp();
  commit(
    work,
    "a.md",
    `the vault (\`~/${vault}\`) and ${vault}Vault types\nuses \`obsidian://open?vault=…&file=…\` and \`obsidian://open\`\n`,
    "default",
  );
  passes(push(work));
});

test("a root commit is scanned", () => {
  const work = setUp();
  ok(work, "switch", "-q", "--orphan", "fresh");
  commit(work, "a.md", `${secret}\n`, "root");
  blocked(push(work, "fresh"), '"a.md":1');
});

test("a line added by a merge commit is scanned", () => {
  const work = setUp();
  ok(work, "switch", "-q", "-c", "side");
  commit(work, "b.md", "side\n", "side");
  ok(work, "switch", "-q", "feature");
  commit(work, "c.md", "feature\n", "feature");
  ok(work, "merge", "-q", "--no-ff", "--no-commit", "side");
  writeFileSync(join(work.cwd, "d.md"), `${secret}\n`);
  ok(work, "add", "d.md");
  ok(work, "commit", "-q", "-m", "merge");
  blocked(push(work), '"d.md":1');
});

test("commits already on the remote are not scanned again", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "old");
  ok(work, "push", "-q", "--no-verify", "origin", "feature");
  ok(work, "fetch", "-q", "origin");
  commit(work, "b.md", "clean\n", "new");
  passes(push(work));
});

test("a new branch cut from a matching commit already on the remote pushes", () => {
  const work = setUp();
  ok(work, "switch", "-q", "main");
  commit(work, "a.md", `${secret}\n`, "old");
  ok(work, "push", "-q", "--no-verify", "origin", "main");
  ok(work, "fetch", "-q", "origin");
  ok(work, "switch", "-q", "-c", "fresh");
  commit(work, "b.md", "clean\n", "new");
  passes(push(work, "fresh"));
});

test("a matching branch name blocks without printing it", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work, "HEAD:refs/heads/feat/mirelbrook-notes"), "the remote ref name: a deny-list entry");
});

test("a push to main is blocked", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work, "feature:main"), "main changes through a merged pull request");
});

test("a push of two refs is blocked", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work, "HEAD:refs/heads/x", "+HEAD:refs/heads/other"), "updates 2 refs");
});

test("a tag is blocked", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  ok(work, "tag", "-a", "v1", "-m", "a tag");
  blocked(push(work, "refs/tags/v1"), "Only branches");
});

for (const refspec of [":feature", "+:refs/heads/feature"]) {
  test(`a deletion (${refspec}) is blocked`, () => {
    const work = setUp();
    commit(work, "a.md", "clean\n", "clean");
    passes(push(work));
    blocked(push(work, refspec), "Deleting a remote ref");
  });
}

test("a force push of the branch HEAD is on is allowed", () => {
  const work = setUp();
  commit(work, "a.md", "one\n", "one");
  passes(push(work));
  ok(work, "commit", "-q", "--amend", "-m", "rewritten");
  passes(push(work, "+feature"));
});

test("a non-fast-forward update of another branch is blocked", () => {
  const work = setUp();
  commit(work, "a.md", "one\n", "one");
  passes(push(work, "HEAD:refs/heads/victim"));
  ok(work, "fetch", "-q", "origin");
  ok(work, "commit", "-q", "--amend", "-m", "rewritten");
  blocked(push(work, "+HEAD:refs/heads/victim"), "non-fast-forward");
});

test("a fast-forward update of another branch is allowed", () => {
  const work = setUp();
  commit(work, "a.md", "one\n", "one");
  passes(push(work, "HEAD:refs/heads/other"));
  commit(work, "b.md", "two\n", "two");
  passes(push(work, "HEAD:refs/heads/other"));
});

test("an installed guard that differs from the checkout's warns but does not block", () => {
  const work = setUp();
  commit(work, "a.md", "clean\n", "clean");
  const same = push(work);
  passes(same);
  assert.doesNotMatch(same.stderr, /differs/);

  appendFileSync(installed(work, "guard", "gh-post.mjs"), "\n// changed\n");
  commit(work, "b.md", "clean\n", "clean");
  const stale = push(work);
  passes(stale);
  assert.match(stale.stderr, /installed guard differs .* after the change is merged .*installs main's guard/);
});

test("a config.json without the deny-list path blocks", () => {
  const work = setUp();
  const config = installed(work, "guard", "config.json");
  const value = JSON.parse(readFileSync(config, "utf8"));
  delete value.denyList;
  writeFileSync(config, JSON.stringify(value));
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "config.json names no absolute deny-list path");
});

test("a missing deny-list file blocks", () => {
  const work = setUp();
  rmSync(work.denyList);
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "cannot be read");
});

test("an empty deny-list blocks", () => {
  const work = setUp();
  writeFileSync(work.denyList, "\n  \n");
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "has no entries");
});

test("a folded spelling (a no-break space) blocks", () => {
  const work = setUp();
  commit(work, "a.md", "by Zephyrine\u00A0Quolltail\n", "nbsp");
  blocked(push(work), '"a.md":1', "a deny-list entry");
});

// A1: binary and non-UTF-8 files

for (const [name, content, kind] of [
  ["a UTF-16LE file holding an entry", Buffer.from(`\uFEFF${secret}\n`, "utf16le"), "binary data"],
  ["a UTF-16LE file without a BOM and without ASCII", Buffer.from("кирилл", "utf16le"), "binary data"],
  ["a Latin-1 file", Buffer.from("caf\u00e9 au lait\n", "latin1"), "invalid UTF-8"],
  ["an image", Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]), "binary data"],
]) {
  test(`${name} blocks`, () => {
    const work = setUp();
    commit(work, "a.bin", content, "binary");
    blocked(push(work), `"a.bin": ${kind}`);
  });
}

test("tab, form feed and CRLF pass the binary check", () => {
  const work = setUp();
  commit(work, "a.txt", "one\ttwo\r\nthree\fpage\r\n", "text");
  passes(push(work));
});

for (const [name, content] of [
  ["a vertical tab", "one\u000btwo\n"],
  ["an escape", "one\u001b[1mtwo\n"],
]) {
  test(`${name} counts as binary data`, () => {
    const work = setUp();
    commit(work, "a.txt", content, "control");
    blocked(push(work), '"a.txt": binary data');
  });
}

test("a binary file on the installed allowlist passes", () => {
  const work = setUp();
  appendFileSync(installed(work, "guard", "binary-allowlist.txt"), "assets/a.bin\n");
  commit(work, "assets/a.bin", Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0]), "binary");
  passes(push(work));
});

test("a binary file whose name matches prints the placeholder", () => {
  const work = setUp();
  commit(work, `notes/${secret}.bin`, Buffer.from([0, 1, 2]), "binary");
  blocked(push(work), "a file name: a deny-list entry", "a file whose name matches: binary data");
});

test("deleting a binary file already on the remote passes", () => {
  const work = setUp();
  commit(work, "a.bin", Buffer.from([0, 1, 2]), "binary");
  ok(work, "push", "-q", "--no-verify", "origin", "feature");
  ok(work, "rm", "-q", "a.bin");
  ok(work, "commit", "-q", "-m", "remove");
  passes(push(work));
});

test("a missing installed allowlist blocks", () => {
  const work = setUp();
  rmSync(installed(work, "guard", "binary-allowlist.txt"));
  commit(work, "a.md", "clean\n", "clean");
  blocked(push(work), "binary-allowlist.txt");
});

test("an installed guard without commit-scan.mjs fails the push", () => {
  const work = setUp();
  rmSync(installed(work, "guard", "commit-scan.mjs"));
  commit(work, "a.md", `note by ${secret}\n`, "match");
  const result = push(work);
  assert.notEqual(result.status, 0, result.stderr);
  assert.ok(!result.stderr.toLowerCase().includes("quolltail"), result.stderr);
});

// A4: only what the remote reports counts as already there

test("a local remote-tracking ref does not hide a commit", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "hidden");
  ok(work, "update-ref", "refs/remotes/origin/hidden", "HEAD");
  commit(work, "b.md", "clean\n", "clean");
  blocked(push(work), '"a.md":1');
});

test("commits on the fetch URL do not count for another push URL", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "old");
  ok(work, "push", "-q", "--no-verify", "origin", "feature");
  const other = join(work.root, "other.git");
  ok(work, "init", "-q", "--bare", other);
  ok(work, "config", "remote.origin.pushurl", other);
  commit(work, "b.md", "clean\n", "new");
  blocked(push(work), '"a.md":1');
});

test("a remote main that moved after the fetch adds the fetch hint to a block", () => {
  const work = setUp();
  ok(work, "switch", "-q", "main");
  commit(work, "a.md", `${secret}\n`, "old, already public");
  ok(work, "push", "-q", "--no-verify", "origin", "main");
  ok(work, "fetch", "-q", "origin");
  ok(work, "switch", "-q", "-c", "fresh");
  commit(work, "b.md", "clean\n", "new");
  const other = { ...work, cwd: join(work.root, "other") };
  ok({ ...work, cwd: work.root }, "clone", "-q", work.remote, other.cwd);
  commit(other, "c.md", "later\n", "merged elsewhere");
  ok(other, "push", "-q", "origin", "main");
  const moved = push(work, "fresh");
  blocked(moved, '"a.md":1', "run git fetch origin, then push again");
  ok(work, "fetch", "-q", "origin");
  passes(push(work, "fresh"));
});

test("a block with nothing missing locally has no fetch hint", () => {
  const work = setUp();
  commit(work, "a.md", `${secret}\n`, "add");
  assert.doesNotMatch(push(work).stderr, /git fetch origin/);
});
