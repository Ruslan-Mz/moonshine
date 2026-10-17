// Tests for the pre-push guard on throwaway repositories: node --test scripts/pre-push.test.mjs
// Each test installs the guard with scripts/install-guard.sh into its own temporary HOME; git reads
// no global or system config. Every deny-list entry here is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, cpSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const install = join(dirname(fileURLToPath(import.meta.url)), "install-guard.sh");
const guard = join(dirname(fileURLToPath(import.meta.url)), "guard");
const secret = "Zephyrine Quolltail";
const vault = "Obsidian" + "V"; // spelled in two parts so this file passes the guard itself

function environment(home) {
  const env = { ...process.env, HOME: home, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  delete env.MOONSHINE_GUARD_DIR; // would send the install outside the temporary HOME
  delete env.MOONSHINE_SCRATCH_ROOT;
  return env;
}

function git(work, ...args) {
  return spawnSync(
    "git",
    ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "init.defaultBranch=main", ...args],
    { cwd: work.cwd ?? work, env: environment(work.home), encoding: "utf8" },
  );
}

function ok(work, ...args) {
  const result = git(work, ...args);
  assert.equal(result.status, 0, `git ${args.join(" ")}\n${result.stderr}`);
  return result.stdout;
}

/// A working repository with one pushed commit on `main`, a bare remote, the installed guard and a
/// deny-list, on branch `feature`.
function setUp({ denyList = `${secret}\n\nкирилл тест\nmirelbrook\n`, configure = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), "pre-push-"));
  const home = join(root, "home");
  mkdirSync(home);
  const remote = join(root, "remote.git");
  const work = { cwd: join(root, "work"), home, root };
  ok({ cwd: root, home }, "init", "-q", "--bare", remote);
  ok({ cwd: root, home }, "init", "-q", work.cwd);
  ok(work, "remote", "add", "origin", remote);
  commit(work, "README.md", "hello\n", "first");
  ok(work, "push", "-q", "origin", "main");
  ok(work, "fetch", "-q", "origin");
  ok(work, "switch", "-q", "-c", "feature");
  const installed = spawnSync("/bin/sh", [install], { cwd: work.cwd, env: environment(home), encoding: "utf8" });
  assert.equal(installed.status, 0, installed.stderr);
  if (configure) {
    const list = join(root, "deny-list.txt");
    if (denyList !== null) writeFileSync(list, denyList);
    ok(work, "config", "moonshine.denyList", list);
  }
  return work;
}

function commit(work, path, text, message) {
  mkdirSync(dirname(join(work.cwd, path)), { recursive: true });
  writeFileSync(join(work.cwd, path), text);
  ok(work, "add", "--", path);
  ok(work, "commit", "-q", "-m", message);
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
  mkdirSync(join(work.cwd, "scripts"));
  cpSync(guard, join(work.cwd, "scripts", "guard"), { recursive: true }); // untracked, never committed
  commit(work, "a.md", "clean\n", "clean");
  const same = push(work);
  passes(same);
  assert.doesNotMatch(same.stderr, /differs/);

  appendFileSync(join(work.home, ".config", "moonshine", "guard", "gh-post.mjs"), "\n// changed\n");
  commit(work, "b.md", "clean\n", "clean");
  const stale = push(work);
  passes(stale);
  assert.match(stale.stderr, /installed guard differs .* after the change is merged, from an up-to-date main .* never install from a branch/);
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
