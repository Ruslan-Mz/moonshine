// The read-boundary hook fails closed, and the permission rules H1a and H1b added stay in the
// template (CLAUDE.md → Commands; H1a, 2026-10-29; H1b, 2026-10-30). Run: node --test scripts/hook-command.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
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
  // P-HR's owner patch (#65) dropped the prune; P-AM2 (#65's deferred Low) stops accepting the old line.
  assert.match(cleanUp, /^A read-only review \(§1, step 1\) created no worktree and no probe worktree: remove nothing\./m);
  assert.doesNotMatch(skill, /run only `git worktree prune`/);
  assert.match(cleanUp, /Never run `git worktree prune` \(P-HR, owner 2026-11-16\)/);
});

// P-HR's owner patch (#65): the headless run's rules in §0, pinned (P-AM2, #65's deferred Low).
test("/review-pr states the headless run's rules", () => {
  const skill = readFileSync(join(repository, ".claude/skills/review-pr/SKILL.md"), "utf8");
  assert.match(skill, /^argument-hint: ".*\[headless\]"$/m);
  assert.match(skill, /^- `headless` \(P-HR, owner 2026-11-16\): the run was started by `~\/\.config\/moonshine\/bin\/review`/m);
  assert.match(skill, /The mode argument is final; nothing waits for the owner; `local`, `since <sha>` and `at <sha>` are refused/);
  assert.match(skill, /no `\$` expansion \(write every path literally\)/);
  assert.match(skill, /In a `headless` run, never wait: keep the mode given/);
});

// W7 of P-HR's owner patch (#65): how the agents change probe copies and count, pinned (P-AM2).
for (const [agent, write] of [
  ["pr-reviewer.md", /A changed copy of a file for a probe is written whole with the Write tool, never with `sed -i`/],
  ["review-verifier.md", /Change a probe copy with the Edit tool, never with `sed -i`/],
]) {
  test(`${agent} states the W7 write and count rules`, () => {
    const text = readFileSync(join(repository, ".claude/agents", agent), "utf8");
    assert.match(text, write);
    assert.match(text, /On a line that starts with `git`, use no `-c` anywhere, also after a pipe \(`grep -c`, `wc -c`\): use `--count` or `--bytes`/);
    assert.match(text, /No `\$` expansion: write every path literally \(a headless run refuses it\)/);
  });
}

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
  assert.deepEqual(
    allow.filter((rule) => rule.includes("xcbuild")),
    [`Bash(${xcbuild} build)`, `Bash(${xcbuild} test)`, `Bash(${xcbuild} summary)`],
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
  assert.ok(Object.hasOwn(template._notes, `Bash(${xcbuild} build|test|summary)`));
  // CLAUDE.md § Git: a new deny rule names the steps that run its paths.
  const denyNote =
    template._notes["Bash(xcodegen*), Bash(xcodebuild*), Bash(*/xcodegen*), Bash(*/xcodebuild*), Bash(xcrun xcodebuild*)"];
  assert.match(denyNote ?? "", /Normal steps that run these paths: none/);
});

// PR #47 round 1 (owner, 2026-11-06): xcresulttool outside the sandbox echoed expanded file names
// for any path; the summary goes through `xcbuild summary`, which takes no path.
test("no rule runs xcresulttool directly", () => {
  for (const rule of [...template.permissions.allow, ...template.sandbox.excludedCommands]) {
    assert.doesNotMatch(rule, /xcresulttool/, rule);
  }
});

test("the template allows the three gh read commands of H1c outside the sandbox, each with its reason", () => {
  const allow = template.permissions.allow;
  const excluded = template.sandbox.excludedCommands;
  for (const command of ["gh pr list", "gh pr list *", "gh run view *", "gh run list", "gh run list *"]) {
    assert.ok(allow.includes(`Bash(${command})`), command);
    assert.ok(excluded.includes(command), command);
  }
  for (const note of ["gh pr list", "gh run view, gh run list"]) {
    assert.ok(Object.hasOwn(template._notes, note), note);
  }
});

// PR #47 round 1 (owner, 2026-11-06): a reviewer created and removed folders in the main checkout.
test("/review-pr and its agents write only in their own worktree or the scratchpad", () => {
  const skill = readFileSync(join(repository, ".claude/skills/review-pr/SKILL.md"), "utf8");
  assert.match(skill, /\*\*Writes stay in a worktree or the scratchpad\*\*/);
  assert.match(skill, /Reviewers and verifiers write only inside their own worktree or the session scratchpad, and plant fixtures there/);
  for (const agent of ["pr-reviewer.md", "review-verifier.md"]) {
    const text = readFileSync(join(repository, ".claude/agents", agent), "utf8");
    assert.match(text, /\*\*Write only in your own worktree or the session scratchpad\*\*/, agent);
    assert.match(text, /Never create, change or remove a file or folder in the main checkout/, agent);
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

// P-HR (owner, 2026-11-16): the headless review starts only through the installed wrapper, by its
// absolute path and outside the sandbox; nobody prunes worktrees (a sibling author worktree is live);
// a session never starts claude itself; and the main checkout's commondir is write-denied.
test("the template starts a headless review only through the installed wrapper and denies prune and claude", () => {
  const review = "/Users/<you>/.config/moonshine/bin/review";
  assert.ok(template.permissions.allow.includes(`Bash(${review} *)`));
  assert.ok(template.sandbox.excludedCommands.includes(`${review} *`));
  assert.ok(!template.permissions.allow.some((rule) => /worktree prune/.test(rule)), "no allow for git worktree prune");
  for (const rule of ["Bash(git worktree prune*)", "Bash(claude *)", "Bash(*/claude *)"]) assert.ok(template.permissions.deny.includes(rule), rule);
  assert.ok(template.sandbox.filesystem.denyWrite.includes("./.git/commondir"));
  for (const note of [`Bash(${review} *)`, "Bash(git worktree prune*)", "Bash(claude *), Bash(*/claude *)", "sandbox.filesystem.denyWrite ./.git/commondir"]) {
    assert.ok(Object.hasOwn(template._notes, note), note);
  }
});

// P-HR (owner, 2026-11-17): the hook tests write no bytecode. A .pyc beside the hook can be loaded in
// place of its source, and the headless review refuses an ignored file under .claude/. The suite
// runs as CI runs it, on a copy of the hooks folder. A python3 shim first on PATH clears a cache
// prefix (Apple's python3 has one), so bytecode would land beside the source as on CI.
const hookTests = /^\s*(python3 .*-m unittest discover -s \.claude\/hooks .*)$/m;

/// The .pyc files and __pycache__ folders a hook-test command leaves under a copy's .claude/.
function bytecodeAfter(command) {
  const copy = realpathSync(mkdtempSync(join(tmpdir(), "hooks-")));
  mkdirSync(join(copy, ".claude", "hooks"), { recursive: true });
  for (const name of ["read-boundary.py", "test_read_boundary.py"]) {
    copyFileSync(join(repository, ".claude", "hooks", name), join(copy, ".claude", "hooks", name));
  }
  const real = spawnSync("/bin/sh", ["-c", "command -v python3"], { encoding: "utf8" }).stdout.trim();
  mkdirSync(join(copy, "bin"));
  writeFileSync(join(copy, "bin", "python3"), `#!/bin/sh\nexec '${real}' -X pycache_prefix= "$@"\n`, { mode: 0o755 });
  const { PYTHONDONTWRITEBYTECODE, PYTHONPYCACHEPREFIX, ...env } = process.env;
  const run = spawnSync("/bin/sh", ["-c", command], { cwd: copy, env: { ...env, PATH: `${join(copy, "bin")}:${env.PATH}` }, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  return readdirSync(join(copy, ".claude"), { recursive: true }).filter((path) => /(^|\/)__pycache__(\/|$)|\.pyc$/.test(path));
}

test("the hook tests run with python3 -B and leave no __pycache__ under .claude/", () => {
  const command = hookTests.exec(readFileSync(join(repository, ".github/workflows/ci.yml"), "utf8"))?.[1];
  assert.equal(command, "python3 -B -m unittest discover -s .claude/hooks -p 'test_*.py'");
  assert.ok(readFileSync(join(repository, "CLAUDE.md"), "utf8").includes(`\`${command}\``), "CLAUDE.md documents the same command");
  assert.deepEqual(bytecodeAfter(command), []);
});

test("without -B the same suite leaves a __pycache__ (the check above can fail)", () => {
  assert.notDeepEqual(bytecodeAfter("python3 -m unittest discover -s .claude/hooks -p 'test_*.py'"), []);
});

// P-AM2 (owner, 2026-11-20): only the owner writes a round's decisions file, and only the owner
// clears a stopped run's record.
test("the template denies writing the owner's decisions files and running review-allow-retry", () => {
  const file = "./Claude outputs/next/pr*-round*.md";
  assert.ok(template.permissions.deny.includes(`Edit(${file})`));
  assert.ok(template.sandbox.filesystem.denyWrite.includes(file));
  const calls = ["Bash(*/.config/moonshine/bin/review-allow-retry*)", "Bash(review-allow-retry*)"];
  for (const rule of calls) assert.ok(template.permissions.deny.includes(rule), rule);
  assert.ok(!template.permissions.allow.some((rule) => /review-allow-retry|Claude outputs/.test(rule)), "no allow undoes them");
  assert.ok(!template.sandbox.excludedCommands.some((command) => /review-allow-retry/.test(command)), "it never runs outside the sandbox");
  for (const note of [`Edit(${file}), sandbox.filesystem.denyWrite ${file}`, calls.join(", ")]) assert.ok(Object.hasOwn(template._notes, note), note);
  assert.match(template._notes[calls.join(", ")], /Sibling class/);
});

// PR #67 round 1 (owner, 2026-11-21): the deny refuses the tool's calls, not every line naming it.
test("the review-allow-retry deny refuses its calls only", () => {
  const denies = template.permissions.deny
    .filter((rule) => rule.startsWith("Bash(") && rule.endsWith(")"))
    .map((rule) => new RegExp(`^${rule.slice(5, -1).replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")}$`, "s"));
  const denied = (command) => denies.some((pattern) => pattern.test(command));
  for (const command of ["/Users/someone/.config/moonshine/bin/review-allow-retry 67", "~/.config/moonshine/bin/review-allow-retry 67", "review-allow-retry 67"]) {
    assert.ok(denied(command), command);
  }
  for (const command of ["grep -n review-allow-retry CLAUDE.md", 'git commit -m "review-allow-retry: name its record"','node --test --test-name-pattern "review-allow-retry" scripts/review-headless.test.mjs']) {
    assert.ok(!denied(command), command);
  }
});
