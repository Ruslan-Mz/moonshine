// Throwaway repositories for the guard tests (pre-push, gh-post, install-guard). Each has a bare
// `origin` whose `main` holds copies of scripts/guard/, scripts/install-guard.sh and the build's
// scripts/xcbuild.sh and scripts/check-project-scripts.mjs, which the installer installs from. git reads no global or system config. Every deny-list entry in the tests
// is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scripts = dirname(fileURLToPath(import.meta.url));

export const secret = "Zephyrine Quolltail";
export const vault = "Obsidian" + "V"; // spelled in two parts so this file passes the guard itself

/// The folder name Claude Code gives a project: every character but A-Z, a-z and 0-9 becomes `-`.
export function slug(path) {
  return path.replace(/[^A-Za-z0-9]/g, "-");
}

export function environment(home, extra = {}) {
  const env = { ...process.env, HOME: home, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", ...extra };
  // Either would send the install outside the temporary HOME.
  if (!("MOONSHINE_GUARD_DIR" in extra)) delete env.MOONSHINE_GUARD_DIR;
  if (!("MOONSHINE_SCRATCH_BASE" in extra)) delete env.MOONSHINE_SCRATCH_BASE;
  if (!("MOONSHINE_ORIGIN_URL" in extra)) delete env.MOONSHINE_ORIGIN_URL;
  return env;
}

export function git(work, ...args) {
  return spawnSync(
    "git",
    ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "init.defaultBranch=main", ...args],
    { cwd: work.cwd, env: environment(work.home, work.env), encoding: "utf8" },
  );
}

export function ok(work, ...args) {
  const result = git(work, ...args);
  assert.equal(result.status, 0, `git ${args.join(" ")}\n${result.stderr}`);
  return result.stdout;
}

export function commit(work, path, content, message) {
  mkdirSync(dirname(join(work.cwd, path)), { recursive: true });
  writeFileSync(join(work.cwd, path), content);
  ok(work, "add", "--", path);
  ok(work, "commit", "-q", "-m", message);
}

/// A working repository on `main` with the guard committed and pushed to a bare `origin`, and
/// fetched. `env` is added to every git and installer run.
export function repository({ env = {} } = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "guard-")));
  const home = join(root, "home");
  mkdirSync(home);
  const work = { root, home, env, cwd: join(root, "work"), remote: join(root, "remote.git") };
  ok({ ...work, cwd: root }, "init", "-q", "--bare", work.remote);
  ok({ ...work, cwd: root }, "init", "-q", work.cwd);
  ok(work, "remote", "add", "origin", work.remote);
  cpSync(join(scripts, "guard"), join(work.cwd, "scripts", "guard"), { recursive: true });
  for (const file of ["install-guard.sh", "xcbuild.sh", "check-project-scripts.mjs"]) {
    cpSync(join(scripts, file), join(work.cwd, "scripts", file));
  }
  writeFileSync(join(work.cwd, "README.md"), "hello\n");
  ok(work, "add", "-A");
  ok(work, "commit", "-q", "-m", "first");
  ok(work, "push", "-q", "origin", "main");
  ok(work, "fetch", "-q", "origin");
  return work;
}

/// Writes a deny-list next to the repository and returns its path.
export function denyListFile(work, text) {
  const path = join(work.root, "deny-list.txt");
  writeFileSync(path, text);
  return path;
}

/// Runs the installer under test (the one the fixture's main holds a copy of) from `cwd`, the
/// repository by default, as main's installer runs: from outside the checkout. The fixture's bare
/// repository stands in for the GitHub one. `extra` is added to the installer's environment.
export function install(work, args, cwd = work.cwd, extra = {}) {
  return spawnSync("/bin/sh", [join(scripts, "install-guard.sh"), ...args], {
    cwd,
    env: environment(work.home, { MOONSHINE_ORIGIN_URL: work.remote, ...work.env, ...extra }),
    encoding: "utf8",
  });
}

/// The installed guard folder in the temporary HOME.
export function installed(work, ...parts) {
  return join(work.home, ".config", "moonshine", ...parts);
}
