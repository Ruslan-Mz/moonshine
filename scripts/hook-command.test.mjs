// The read-boundary hook fails closed, and the permission rules H1a and H1b added stay in the
// template (CLAUDE.md → Commands; H1a, 2026-10-29; H1b, 2026-10-30). Run: node --test scripts/hook-command.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repository = new URL("..", import.meta.url).pathname;
const read = (path) => JSON.parse(readFileSync(join(repository, path), "utf8"));
const settings = read(".claude/settings.json");
const template = read(".claude/settings.local.example.json");

const python = "/usr/bin/python3";
const command = `${python} "\${CLAUDE_PROJECT_DIR}/.claude/hooks/read-boundary.py" || exit 2`;

function readHook() {
  const entries = settings.hooks.PreToolUse.filter((entry) => entry.matcher === "Read|Grep|Glob");
  assert.equal(entries.length, 1);
  assert.equal(entries[0].hooks.length, 1);
  return entries[0].hooks[0];
}

test("the read-boundary hook command is pinned and ends in || exit 2", () => {
  assert.deepEqual(readHook(), { type: "command", command });
});

test("an interpreter that cannot start blocks the read (exit 2)", () => {
  const project = mkdtempSync(join(tmpdir(), "hook-command-"));
  try {
    const missing = readHook().command.replace(python, join(project, "no-such-python3"));
    const result = spawnSync("/bin/sh", ["-c", missing], {
      env: { PATH: "/usr/bin:/bin", CLAUDE_PROJECT_DIR: project },
      input: "{}",
    });
    assert.equal(result.status, 2);
  } finally {
    rmSync(project, { recursive: true, force: true });
  }
});

test("no wildcard rule for swift build, xcodegen or xcodebuild in the tracked settings", () => {
  for (const rule of settings.permissions.allow) {
    assert.doesNotMatch(rule, /^Bash\((?:swift build|xcodegen|xcodebuild)/, rule);
  }
});

test("the template keeps the deny rules of H1a", () => {
  const deny = new Set(template.permissions.deny);
  for (const rule of [
    "Edit(**/.git/config)",
    "Edit(**/.git/hooks/**)",
    "Edit(**/.git/commondir)",
    "Edit(./.claude/hooks/**)",
    "Edit(./.claude/settings.json)",
    "Bash(git *hooksPath*)",
    "Bash(git *hookspath*)",
    "Bash(git *HOOKSPATH*)",
    "Bash(git -c *)",
    "Bash(git -C * -c *)",
    "Bash(git *--config-env*)",
    "Bash(*GIT_CONFIG*)",
    "Bash(*GIT_DIR*)",
    "Bash(*GIT_COMMON_DIR*)",
    "Bash(*GIT_WORK_TREE*)",
    "Bash(git *--git-dir*)",
    "Bash(git *--work-tree*)",
    "Bash(git *denyList*)",
    "Bash(git *denylist*)",
    "Bash(git push *'*)",
    'Bash(git push *"*)',
    "Bash(git push *\\*)",
    "Bash(git push *$*)",
  ]) {
    assert.ok(deny.has(rule), rule);
  }
  // In the main checkout `.git` is a directory; denying it would deny every git write.
  for (const rule of ["Edit(**/.git/**)", "Edit(**/.git)", "Edit(./.git)"]) {
    assert.ok(!deny.has(rule), `${rule}: the whole .git is never denied, Edit denies are sandbox write denies`);
  }
});

test("the template keeps the rules of H1b", () => {
  const deny = new Set(template.permissions.deny);
  for (const rule of [
    "Bash(git tag -d*)",
    "Bash(git update-ref -d refs/heads/*)",
    "Bash(git update-ref -d refs/tags/*)",
    "Bash(git update-ref -d refs/remotes/origin/*)",
    "Bash(gh api graphql*)",
    "Bash(git branch -D*)",
  ]) {
    assert.ok(deny.has(rule), rule);
  }
  // Widened in H1b: the narrower spellings are gone.
  for (const rule of [
    "Bash(git *moonshine.denyList*)",
    "Bash(git *moonshine.denylist*)",
    "Bash(gh api graphql *)",
    "Bash(git branch -D *)",
  ]) {
    assert.ok(!deny.has(rule), `${rule} was widened`);
  }
  // Dropped in PR #38 round 1 (owner, 2026-10-31): git worktree add writes these (CLAUDE.md § Git).
  for (const rule of ["Edit(**/.git/worktrees/*/commondir)", "Edit(**/.git/worktrees/*/gitdir)"]) {
    assert.ok(!deny.has(rule), `${rule} was dropped`);
  }
  // Live runs ask every time.
  const ask = new Set(template.permissions.ask);
  for (const rule of ["Bash(swift run*)", "Bash(*/moonshine-import)", "Bash(*/moonshine-import *)"]) {
    assert.ok(ask.has(rule), rule);
  }
  // The sandbox denies ~/.npm: npm caches inside the checkout, in a git-ignored folder.
  assert.equal(template.env.npm_config_cache, "/Users/<you>/<repo>/.npm-cache");
  const ignored = readFileSync(join(repository, ".gitignore"), "utf8").split("\n");
  assert.ok(ignored.includes(".npm-cache/"));
});

test("the worktree-only block carries the main checkout's .git rules with placeholders only", () => {
  const block = template._worktreeOnly;
  assert.deepEqual(block.permissions.deny, [
    "Edit(//Users/<you>/<repo>/.git/config)",
    "Edit(//Users/<you>/<repo>/.git/hooks/**)",
    "Edit(//Users/<you>/<repo>/.git/commondir)",
    "Edit(./.git)",
  ]);
  assert.deepEqual(block.sandbox.filesystem, {
    allowRead: ["<main-checkout>/.git"],
    allowWrite: ["<main-checkout>/.git"],
    denyWrite: [
      "<main-checkout>/.git/config",
      "<main-checkout>/.git/hooks",
      "<main-checkout>/.git/commondir",
      "./.git",
    ],
  });
});
