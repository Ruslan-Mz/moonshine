// Tests for scripts/install-guard.sh on throwaway repositories: node --test scripts/install-guard.test.mjs
// Each test runs the installer under test from outside the throwaway repository, as origin's main copy
// runs, into a temporary HOME (scripts/guard-fixture.mjs).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { commit, denyListFile, environment, git, install, installed, ok, repository, slug } from "./guard-fixture.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const github = "https://github.com/Ruslan-Mz/moonshine.git";
const guardFiles = ["binary-allowlist.txt", "commit-scan.mjs", "gh-post.mjs", "matcher.mjs", "merge.mjs", "plain-rules.mjs", "pre-push.mjs"];

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
    "check-project-scripts.mjs",
    "commit-scan.mjs",
    "config.json",
    "gh-post.mjs",
    "matcher.mjs",
    "merge.mjs",
    "plain-rules.mjs",
    "pre-push.mjs",
    "xcbuild.sh",
  ]);
  assert.deepEqual(readdirSync(installed(work, "bin")).sort(), ["gh-post", "xcbuild"]);
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

test("a reinstall keeps the state file", () => {
  const work = setUp();
  assert.equal(install(work, [work.denyList]).status, 0);
  writeFileSync(installed(work, "state", "posts.jsonl"), '{"kind":"comment"}\n');
  assert.equal(install(work, [work.denyList]).status, 0);
  assert.equal(readFileSync(installed(work, "state", "posts.jsonl"), "utf8"), '{"kind":"comment"}\n');
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
  assert.deepEqual(readdirSync(installed(work)).sort(), ["bin", "guard", "hooks", "state"]);
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

/// The guard files as the fixture's main holds them.
function mainGuard(work) {
  return Object.fromEntries(guardFiles.map((name) => [name, ok(work, "show", `main:scripts/guard/${name}`)]));
}

function installedGuard(work) {
  return Object.fromEntries(guardFiles.map((name) => [name, readFileSync(installed(work, "guard", name), "utf8")]));
}

/// The install command CLAUDE.md documents.
function documentedLine() {
  const line = /`(git fetch origin && m=[^`]+)`/.exec(readFileSync(join(repo, "CLAUDE.md"), "utf8"))?.[1];
  assert.ok(line?.includes(github), "CLAUDE.md documents the install command");
  return line;
}

/// The documented command run by `shell`, with the fixture's bare repository for the GitHub one.
function documented(work, shell = ["bash", "-c"]) {
  const line = documentedLine();
  writeFileSync(join(work.cwd, "deny-list.txt"), "zephyrine\n");
  return spawnSync(shell[0], [...shell.slice(1), line.replaceAll(github, work.remote)], {
    cwd: work.cwd,
    env: environment(work.home, { MOONSHINE_ORIGIN_URL: work.remote, ...work.env }),
    encoding: "utf8",
  });
}

test("the documented command installs main's guard, whatever the checkout's guard and installer hold", () => {
  const work = setUp();
  const expected = mainGuard(work);
  ok(work, "switch", "-q", "-c", "edited");
  commit(work, "scripts/guard/pre-push.mjs", "// replaced\n", "edit the guard");
  commit(work, "scripts/install-guard.sh", `touch '${join(work.root, "ran")}'\n`, "edit the installer");
  appendFileSync(join(work.cwd, "scripts", "guard", "matcher.mjs"), "\n// edited\n");
  writeFileSync(join(work.cwd, "scripts", "guard", "extra.mjs"), "// extra\n");
  const result = documented(work);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(installedGuard(work), expected);
  assert.ok(!existsSync(join(work.root, "ran")), "the checkout's installer must not run");
  assert.ok(!existsSync(installed(work, "guard", "extra.mjs")));
});

// zsh, the owner's shell, reads `$m:s…` as a substitution modifier ("bad substitution"): the
// variable is written `${m}` before every `:` (owner, 2026-11-01).
test("the documented command writes ${m} before every colon", () => {
  const line = documentedLine();
  assert.ok(!/\$m:/.test(line), "`$m:` breaks in zsh; write `${m}:`");
  assert.equal(line.split("${m}:").length - 1, 2);
});

test("the documented command installs main's guard in zsh", { skip: !existsSync("/bin/zsh") && "no /bin/zsh" }, () => {
  const work = setUp();
  const expected = mainGuard(work);
  const result = documented(work, ["/bin/zsh", "-f", "-c"]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(installedGuard(work), expected);
});

for (const flag of ["--skip-worktree", "--assume-unchanged"]) {
  test(`a guard file edited under ${flag} is installed as main holds it`, () => {
    const work = setUp();
    const expected = mainGuard(work);
    ok(work, "update-index", flag, "scripts/guard/matcher.mjs");
    appendFileSync(join(work.cwd, "scripts", "guard", "matcher.mjs"), "\n// hidden edit\n");
    assert.equal(ok(work, "status", "--porcelain"), "", "the edit is hidden from git status");
    const result = install(work, [work.denyList]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(installedGuard(work), expected);
  });
}

test("a moved local origin/main does not stand in for the remote's", () => {
  const work = setUp();
  const expected = mainGuard(work);
  commit(work, "scripts/guard/matcher.mjs", "// replaced\n", "edit the guard");
  ok(work, "update-ref", "refs/remotes/origin/main", "HEAD");
  assert.equal(install(work, [work.denyList]).status, 0);
  assert.equal(installedGuard(work)["matcher.mjs"], expected["matcher.mjs"]);
});

test("a stale local origin/main is refused: the remote's main is not here yet", () => {
  const work = setUp();
  const other = { ...work, cwd: join(work.root, "other") };
  ok({ ...work, cwd: work.root }, "clone", "-q", work.remote, other.cwd);
  commit(other, "b.md", "later\n", "later");
  ok(other, "push", "-q", "origin", "main");
  refused(work, install(work, [work.denyList]), "git fetch origin");
});

test("a remote without main is refused", () => {
  const work = setUp();
  ok({ ...work, cwd: work.remote }, "update-ref", "-d", "refs/heads/main");
  refused(work, install(work, [work.denyList]), "origin has no main");
});

test("a checkout whose origin is another repository is refused", () => {
  const work = setUp();
  const other = join(work.root, "other.git");
  ok({ ...work, cwd: work.root }, "clone", "-q", "--bare", work.remote, other);
  ok(work, "remote", "set-url", "origin", other);
  refused(work, install(work, [work.denyList]), "origin is not");
});

test("a push URL to another repository is refused", () => {
  const work = setUp();
  ok(work, "remote", "set-url", "--push", "origin", join(work.root, "other.git"));
  refused(work, install(work, [work.denyList]), "origin is not");
});

test("running it outside any checkout is refused", () => {
  const work = setUp();
  const elsewhere = join(work.root, "elsewhere");
  mkdirSync(elsewhere);
  refused(work, install(work, [work.denyList], elsewhere), "inside a checkout of this repository");
});

// H1c: the build runs main's xcbuild.sh and project check, in a cleared environment.

const buildFiles = ["xcbuild.sh", "check-project-scripts.mjs"];
// The folder of the node the installer finds on PATH, which may be a link to process.execPath.
const nodeDir = dirname(spawnSync("/bin/sh", ["-c", "command -v node"], { encoding: "utf8" }).stdout.trim());

test("the build wrapper runs the installed xcbuild.sh with HOME and a fixed PATH only", () => {
  const work = setUp();
  assert.equal(install(work, [work.denyList]).status, 0);
  assert.equal(
    readFileSync(installed(work, "bin", "xcbuild"), "utf8"),
    "#!/bin/sh\n# Generated by scripts/install-guard.sh. Builds the current folder with main's build script and check, in a cleared environment.\n" +
      `exec /usr/bin/env -i HOME="$HOME" PATH='/usr/bin:/bin:/usr/sbin:/sbin:${nodeDir}:/opt/homebrew/bin:/usr/local/bin' /bin/sh '${installed(work, "guard", "xcbuild.sh")}' "$@"\n`,
  );
  // What reaches the script: a stand-in for the installed copy prints its environment and arguments.
  const out = join(work.root, "env.txt");
  writeFileSync(installed(work, "guard", "xcbuild.sh"), `env > '${out}'\necho "$@" >> '${out}'\n`);
  const result = spawnSync(installed(work, "bin", "xcbuild"), ["build"], {
    cwd: work.cwd,
    env: { HOME: work.home, PATH: "/usr/bin:/bin", DEVELOPER_DIR: "/tmp/fake-xcode", NODE_OPTIONS: "--require=/tmp/x.js" },
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  const lines = readFileSync(out, "utf8").trim().split("\n");
  assert.equal(lines.at(-1), "build");
  const names = lines.slice(0, -1).map((line) => line.slice(0, line.indexOf("=")));
  // sh sets PWD, SHLVL, OLDPWD and _ itself.
  assert.deepEqual(names.filter((name) => !["PWD", "SHLVL", "OLDPWD", "_"].includes(name)).sort(), ["HOME", "PATH"]);
  assert.ok(lines.includes(`HOME=${work.home}`));
  assert.ok(lines.includes(`PATH=/usr/bin:/bin:/usr/sbin:/sbin:${nodeDir}:/opt/homebrew/bin:/usr/local/bin`));
});

test("the build's scripts are installed as main holds them, whatever the checkout holds", () => {
  const work = setUp();
  const expected = Object.fromEntries(buildFiles.map((name) => [name, ok(work, "show", `main:scripts/${name}`)]));
  ok(work, "switch", "-q", "-c", "edited");
  commit(work, "scripts/xcbuild.sh", "exit 0\n", "edit the build");
  appendFileSync(join(work.cwd, "scripts", "check-project-scripts.mjs"), "\nprocess.exit(0);\n");
  assert.equal(install(work, [work.denyList]).status, 0);
  for (const name of buildFiles) assert.equal(readFileSync(installed(work, "guard", name), "utf8"), expected[name], name);
});

test("a node folder that would need quoting is refused", () => {
  const work = setUp();
  const odd = join(work.root, "it's");
  mkdirSync(odd);
  writeFileSync(join(odd, "node"), `#!/bin/sh\nexec '${process.execPath}' "$@"\n`, { mode: 0o755 });
  refused(work, install(work, [work.denyList], work.cwd, { PATH: `${odd}:/usr/bin:/bin` }), "a quote, a backslash or a control character");
});

// PR #47 round 1. /usr/bin and /bin hold no node on macOS; a runner that has one there skips this.
test(
  "without node on PATH the install is refused with a clear message",
  { skip: ["/usr/bin/node", "/bin/node"].some((path) => existsSync(path)) && "node in /usr/bin or /bin" },
  () => {
    const work = setUp();
    refused(work, install(work, [work.denyList], work.cwd, { PATH: "/usr/bin:/bin" }), "node is not on PATH");
  },
);

test("running it from a subfolder of the checkout installs", () => {
  const work = setUp();
  assert.equal(install(work, [work.denyList], join(work.cwd, "scripts")).status, 0);
  assert.equal(ok(work, "config", "--get", "core.hooksPath").trim(), installed(work, "hooks"));
});
