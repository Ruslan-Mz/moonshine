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

test("/review-pr reads a fork PR's diff only, before any worktree is created (PUB-3 round 1)", () => {
  const skill = readFileSync(join(repository, ".claude/skills/review-pr/SKILL.md"), "utf8");
  const rule = skill.indexOf("**Fork PRs are read-only**");
  assert.ok(rule > 0, "the fork rule is in SKILL.md");
  assert.ok(rule < skill.indexOf("git worktree add <scratchpad>/review/pr-<n>"), "it comes before the worktree");
  assert.match(skill, /headRepository,headRepositoryOwner,isCrossRepository/);
  assert.match(skill, /or `headRefName` starts with `fork\/`/);
  assert.match(skill, /nothing from the PR is built, tested or run/);
  assert.match(skill, /\*\*Read-only review: the head is a fork's code; nothing from this PR was built, tested or run\.\*\*/);
  const cleanUp = skill.slice(skill.indexOf("## 6. Clean up"));
  assert.match(cleanUp, /^A read-only review \(§1, step 1\) created no worktree and no probe worktree: run only `git worktree prune`\./m);
});

for (const [agent, rule] of [
  ["pr-reviewer.md", /\*\*Read-only review \(a fork PR\)\.\*\* When the orchestrator says the review is read-only, or gives you no worktree/],
  ["review-verifier.md", /\*\*Read-only review \(a fork PR\)\.\*\* When the orchestrator says the review is read-only, or gives you no worktree/],
]) {
  test(`${agent} states the read-only fork rule in its own instructions (PUB-3 round 2)`, () => {
    const text = readFileSync(join(repository, ".claude/agents", agent), "utf8");
    assert.match(text, rule);
    assert.match(text, /no `swift`, `xcodebuild`, `node` or `npm`, no script/);
  });
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

// S4-4c-1 (owner, 2026-11-05): only the owner writes the local signing settings, which the
// unsandboxed xcodebuild reads. The Edit deny is also a sandbox write deny; no normal step
// (commit, branch, fetch, push, worktree, build, tests, npm, the installer) writes the file.
test("the template denies writing the local signing settings", () => {
  assert.ok(new Set(template.permissions.deny).has("Edit(**/Configs/*.local.*)"));
});

// H1c (owner, 2026-11-06): the app is built only through the installed xcbuild, which runs main's
// check and build script; bare XcodeGen and xcodebuild lose their allow and their sandbox exclusion,
// and are denied.
const xcbuild = "/Users/<you>/.config/moonshine/bin/xcbuild";

test("the template builds the app only through the installed xcbuild", () => {
  const allow = template.permissions.allow;
  assert.ok(allow.includes(`Bash(${xcbuild} build)`));
  assert.ok(allow.includes(`Bash(${xcbuild} test)`));
  assert.deepEqual(
    allow.filter((rule) => rule.includes("xcbuild")),
    [`Bash(${xcbuild} build)`, `Bash(${xcbuild} test)`],
  );
  const excluded = template.sandbox.excludedCommands;
  assert.ok(excluded.includes(`${xcbuild} *`));
  for (const rule of [...allow, ...excluded]) assert.doesNotMatch(rule, /xcodegen|xcodebuild/, rule);
  const deny = new Set(template.permissions.deny);
  for (const rule of [
    "Bash(xcodegen*)",
    "Bash(xcodebuild*)",
    "Bash(*/xcodegen*)",
    "Bash(*/xcodebuild*)",
    "Bash(xcrun xcodebuild*)",
  ]) {
    assert.ok(deny.has(rule), rule);
  }
  assert.ok(Object.hasOwn(template._notes, `Bash(${xcbuild} build|test)`));
});

test("the template allows the four read commands of H1c outside the sandbox, each with its reason", () => {
  const allow = template.permissions.allow;
  const excluded = template.sandbox.excludedCommands;
  for (const command of [
    "gh pr list",
    "gh pr list *",
    "xcrun xcresulttool get test-results *",
    "gh run view *",
    "gh run list",
    "gh run list *",
  ]) {
    assert.ok(allow.includes(`Bash(${command})`), command);
    assert.ok(excluded.includes(command), command);
  }
  for (const note of ["gh pr list", "xcrun xcresulttool get test-results", "gh run view, gh run list"]) {
    assert.ok(Object.hasOwn(template._notes, note), note);
  }
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

test("the template allows read-only gh api on this repository and keeps every write deny (owner, 2026-11-04)", () => {
  assert.ok(template.permissions.allow.includes("Bash(gh api repos/Ruslan-Mz/moonshine/*)"));
  const deny = new Set(template.permissions.deny);
  for (const rule of [
    "Bash(gh api *--method post*)",
    "Bash(gh api *--method POST*)",
    "Bash(gh api *--method=*)",
    "Bash(gh api *-X*)",
    "Bash(gh api *-f *)",
    "Bash(gh api *-F *)",
    "Bash(gh api *--input*)",
    "Bash(gh api *--field*)",
    "Bash(gh api *--raw-field*)",
    "Bash(gh api *@*)",
    "Bash(gh api *merge*)",
    "Bash(gh api graphql*)",
  ]) {
    assert.ok(deny.has(rule), rule);
  }
});
