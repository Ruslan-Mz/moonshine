// The read-boundary hook fails closed, and the permission rules H1a added stay in the template
// (CLAUDE.md → Commands; H1a, 2026-10-29). Run: node --test scripts/hook-command.test.mjs
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
    "Edit(**/.git/worktrees/*/commondir)",
    "Edit(**/.git/worktrees/*/gitdir)",
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
    "Bash(git *moonshine.denyList*)",
    "Bash(git *moonshine.denylist*)",
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

test("the worktree-only block carries the main checkout's .git rules with placeholders only", () => {
  const block = template._worktreeOnly;
  assert.deepEqual(block.permissions.deny, [
    "Edit(//Users/<you>/<repo>/.git/config)",
    "Edit(//Users/<you>/<repo>/.git/hooks/**)",
    "Edit(//Users/<you>/<repo>/.git/commondir)",
    "Edit(//Users/<you>/<repo>/.git/worktrees/*/commondir)",
    "Edit(//Users/<you>/<repo>/.git/worktrees/*/gitdir)",
    "Edit(./.git)",
  ]);
  assert.deepEqual(block.sandbox.filesystem, {
    allowRead: ["<main-checkout>/.git"],
    allowWrite: ["<main-checkout>/.git"],
    denyWrite: [
      "<main-checkout>/.git/config",
      "<main-checkout>/.git/hooks",
      "<main-checkout>/.git/commondir",
      "<main-checkout>/.git/worktrees/*/commondir",
      "<main-checkout>/.git/worktrees/*/gitdir",
      "./.git",
    ],
  });
});
