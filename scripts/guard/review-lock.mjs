// The headless review's lock (P-HR): one file per checkout in the guard's state folder, which a
// sandboxed session cannot write. While it is live, gh-post allows only the run's own review and
// pre-push refuses (CLAUDE.md → Commands → Guard). Shared by review.mjs, gh-post.mjs and pre-push.mjs.
// What a forged lock can do: docs/setup/headless-review.md, "The lock".
// Tests: node --test scripts/review-lock.test.mjs
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { closeSync, fstatSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { instructions } from "./plain-rules.mjs";

const stateFolder = join(dirname(fileURLToPath(import.meta.url)), "..", "state");
// ps prints the start time in the C locale and UTC, whatever the caller's LANG and TZ.
const psEnv = { PATH: "/usr/bin:/bin", LC_ALL: "C", LANG: "C", TZ: "UTC0" };
// Ignored paths Claude Code itself writes, allowed in a checkout that is reviewed; inside an ignored
// nested repository (a package checkout) only its write log (owner, 2026-11-17, PR #63 round 1).
const allowedIgnored = /^(?:\.claude\/settings\.local\.json|\.claude\/\.cc-writes(?:\/.*)?|(?:.*\/)?\.DS_Store)$/;
const allowedNested = /(?:^|\/)\.claude\/\.cc-writes\//;
const maxWalked = 500_000;

const real = (path) => {
  try {
    return realpathSync(path).toLowerCase();
  } catch {
    return null;
  }
};
const inside = (path, folder) => {
  if (path === null || folder === null) return false;
  const rest = relative(folder, path);
  return !isAbsolute(rest) && rest.split(sep)[0] !== "..";
};

export function lockPath(top) {
  return join(stateFolder, `review-${createHash("sha256").update(realpathSync(top)).digest("hex").slice(0, 16)}.json`);
}

/// The process's start time as ps prints it, or null when ps fails or prints nothing.
export function startTime(pid) {
  const result = spawnSync("/bin/ps", ["-o", "lstart=", "-p", String(pid)], { env: psEnv, encoding: "utf8" });
  const text = result.status === 0 ? result.stdout.trim() : "";
  return text === "" ? null : text;
}

/// Gone only when the pid does not exist, or exists with another start time; a ps that fails
/// counts as alive.
function alive(record) {
  if (!Number.isSafeInteger(record?.pid) || record.pid <= 1) return false;
  try {
    process.kill(record.pid, 0);
  } catch (error) {
    if (error.code === "ESRCH") return false;
  }
  const now = startTime(record.pid);
  return now === null || now === record.start;
}

const processRecord = (value) => Number.isSafeInteger(value?.pid) && typeof value.start === "string" && value.start !== "";

/// { lock, ino, text } for a well-formed file, { malformed: true } otherwise, null when there is
/// none. The inode is the one the text was read from.
function readLock(path) {
  let text;
  let ino;
  try {
    const fd = openSync(path, "r");
    try {
      ino = fstatSync(fd).ino;
      text = readFileSync(fd, "utf8");
    } finally {
      closeSync(fd);
    }
  } catch (error) {
    return error.code === "ENOENT" ? null : { malformed: true };
  }
  try {
    const lock = JSON.parse(text);
    const ok =
      /^[1-9][0-9]{0,6}$/.test(lock.pr) && /^[0-9a-f]{40}$/.test(lock.head) && /^[0-9a-f-]{36}$/.test(lock.session) &&
      typeof lock.top === "string" && typeof lock.sessionDir === "string" && processRecord(lock.wrapper) &&
      (lock.child === undefined || processRecord(lock.child));
    return ok ? { lock, ino, text } : { malformed: true };
  } catch {
    return { malformed: true };
  }
}

/// Whether a run is alive: its wrapper or its child.
export function live(lock) {
  return alive(lock.wrapper) || (lock.child !== undefined && alive(lock.child));
}

/// The live lock that covers `top` (or any, when `top` is null): the one for this checkout, or one
/// whose session folder holds `top` (the run's own review worktrees). { lock, path }, { malformed,
/// path } (which counts as live), or null.
export function liveLockFor(top) {
  let names;
  try {
    names = readdirSync(stateFolder).filter((name) => /^review-[0-9a-f]{16}\.json$/.test(name));
  } catch {
    return null;
  }
  const here = top === null ? null : real(top);
  for (const name of names) {
    const path = join(stateFolder, name);
    const found = readLock(path);
    if (found === null) continue;
    if (found.malformed) return { malformed: true, path };
    const covers = here === null || real(found.lock.top) === here || inside(here, real(found.lock.sessionDir));
    if (covers && live(found.lock)) return { lock: found.lock, path };
  }
  return null;
}

/// Why the checkout at `top` is not exactly `head`, or null: HEAD, a change or an untracked file, a
/// submodule, an index flag, or an ignored instruction file (CLAUDE.md, CLAUDE.local.md, .claude/,
/// .mcp.json at any depth, ignored folders included).
export function checkoutClean(top, head) {
  const git = (...args) => {
    const result = spawnSync("git", ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", ...args], {
      cwd: top,
      env: { ...process.env, GIT_NO_REPLACE_OBJECTS: "1" },
      encoding: "utf8",
      maxBuffer: 1 << 30,
    });
    return result.status === 0 ? result.stdout : null;
  };
  if (git("rev-parse", "HEAD")?.trim() !== head) return "HEAD is not the PR's head";
  if (git("status", "--porcelain=v1", "-z", "--ignore-submodules=dirty", "--untracked-files=all") !== "") return "the checkout has changes or untracked files";
  const staged = git("ls-files", "-s", "-z");
  if (staged === null || staged.split("\0").some((entry) => entry.startsWith("160000 "))) return "the checkout has a submodule";
  const tags = git("ls-files", "-v", "-z");
  if (tags === null || tags.split("\0").some((entry) => entry !== "" && !entry.startsWith("H "))) return "a file has an index flag";
  const ignored = git("ls-files", "-z", "--others", "--ignored", "--exclude-standard");
  if (ignored === null) return "the ignored files cannot be listed";
  const bad = (path, allowed) => instructions.test(path.normalize("NFC")) && !allowed.test(path);
  // git lists an ignored nested repository as one folder entry: walk it, following no link.
  const nested = [];
  for (const path of ignored.split("\0")) {
    if (path.endsWith("/")) nested.push(path);
    else if (path !== "" && bad(path, allowedIgnored)) return "an ignored instruction file (CLAUDE.md, .claude/, .mcp.json)";
  }
  let walked = 0;
  while (nested.length > 0) {
    const folder = nested.pop();
    let entries;
    try {
      entries = readdirSync(join(top, folder), { withFileTypes: true });
    } catch {
      return "an ignored nested repository cannot be read";
    }
    walked += entries.length;
    if (walked > maxWalked) return "the ignored nested repositories hold too many files to check";
    for (const entry of entries) {
      const path = folder + entry.name;
      if (entry.isDirectory()) nested.push(`${path}/`);
      else if (bad(path, allowedNested)) return "an instruction file in an ignored nested repository (CLAUDE.md, .claude/, .mcp.json)";
    }
  }
  return null;
}

const exists = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
};
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

/// Ends `roots` (detached children) and everything under them: the descendants and every process
/// in their groups, walked until no new pid appears; TERM, up to `graceMs` to exit, then KILL.
/// Never this process or its group.
export function killTree(roots, graceMs = 10_000) {
  const collect = () => {
    // A zombie has exited already; it waits only for its parent to reap it.
    const rows = (spawnSync("/bin/ps", ["-A", "-o", "pid=,ppid=,pgid=,stat="], { env: psEnv, encoding: "utf8" }).stdout ?? "")
      .split("\n")
      .map((line) => line.trim().split(/\s+/))
      .filter((row) => row.length === 4 && !row[3].startsWith("Z"))
      .map((row) => row.slice(0, 3).map(Number))
      .filter((row) => row.every(Number.isSafeInteger));
    const own = rows.find(([pid]) => pid === process.pid)?.[2];
    const pids = new Set(roots.filter((pid) => Number.isSafeInteger(pid) && pid > 1 && pid !== own));
    // A root was started detached, so it leads its own group, which outlives it.
    const groups = new Set(pids);
    for (let size = -1; size !== pids.size + groups.size; ) {
      size = pids.size + groups.size;
      for (const [pid, ppid, pgid] of rows) {
        if (pids.has(pid) && pgid > 1 && pgid !== own) groups.add(pgid);
        if (pids.has(ppid) || groups.has(pgid)) pids.add(pid);
      }
    }
    pids.delete(process.pid);
    // Only processes that exist; when ps fails, the roots that still answer.
    const listed = new Set(rows.map(([pid]) => pid));
    return [...pids].filter((pid) => (rows.length > 0 ? listed.has(pid) : exists(pid)));
  };
  const signal = (pids, name) => pids.forEach((pid) => {
    try {
      process.kill(pid, name);
    } catch {
      // gone already
    }
  });
  signal(collect(), "SIGTERM");
  for (let waited = 0; waited < graceMs && collect().length > 0; waited += 100) sleep(100);
  signal(collect(), "SIGKILL");
}

/// Removes the review worktrees of PR `pr` that the checkout at `top` lists in the session folder
/// `folder` (`scratchpad/review/pr-<pr>` and `pr-<pr>-*`, as /review-pr names them), by path; never
/// prunes.
export function removeWorktrees(top, folder, pr) {
  const off = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"];
  const list = spawnSync("git", [...off, "worktree", "list", "--porcelain", "-z"], { cwd: top, encoding: "utf8" });
  const base = real(join(folder, "scratchpad", "review"));
  const name = new RegExp(`^pr-${pr}(?:-.*)?$`);
  let removed = 0;
  for (const line of list.status === 0 ? list.stdout.split("\0") : []) {
    if (!line.startsWith("worktree ")) continue;
    const path = line.slice("worktree ".length);
    const resolved = real(path);
    if (base === null || resolved === null || dirname(resolved) !== base || !name.test(basename(resolved))) continue;
    if (spawnSync("git", [...off, "worktree", "remove", "--force", "--force", path], { cwd: top }).status === 0) removed += 1;
  }
  return removed;
}

/// Whether the process `pid` was started as `claude` (the path itself, or a script run by an
/// interpreter); false when ps fails.
function runsClaude(pid, claude) {
  const result = spawnSync("/bin/ps", ["-o", "args=", "-p", String(pid)], { env: psEnv, encoding: "utf8" });
  const args = result.status === 0 ? result.stdout.trim() : "";
  const command = /^\S+ /.test(args) ? args.replace(/^\S+ /, "") : "";
  return args === claude || args.startsWith(`${claude} `) || command === claude || command.startsWith(`${claude} `);
}

/// Takes the lock for `fields.top` or stops: created exclusively. A stale lock is acted on only
/// when it names this checkout and a session folder under this run's scratch root (owner,
/// 2026-11-17, PR #63 round 1): a recorded child still alive is killed only when it runs `claude`,
/// and only its session's review worktrees of its PR are removed. Then it is set aside, and only
/// the file read is.
export function takeLock(fields, stop, claude) {
  const path = lockPath(fields.top);
  const found = readLock(path);
  if (found?.malformed) stop(`The review lock ${path} cannot be read; the owner removes it when no review runs.`);
  if (found) {
    const stale = found.lock;
    if (alive(stale.wrapper)) stop("A review already runs in this checkout.");
    if (real(stale.top) !== real(fields.top) || stale.sessionDir !== join(dirname(fields.sessionDir), stale.session)) {
      stop(`The stale review lock ${path} names another checkout or session folder; the owner checks it and removes it.`);
    }
    if (stale.child !== undefined && alive(stale.child)) {
      if (!runsClaude(stale.child.pid, claude)) stop(`The stale review lock ${path} names a live process that is not claude; the owner checks it and removes it.`);
      killTree([stale.child.pid]);
    }
    removeWorktrees(fields.top, stale.sessionDir, stale.pr);
    // Set aside by rename; if what was renamed is not the file read above, another run took it.
    // The inode alone does not tell: Linux gives a new lock the inode a removed one freed.
    const aside = `${path}.stale-${process.pid}`;
    let same;
    try {
      renameSync(path, aside);
      same = statSync(aside).ino === found.ino && readFileSync(aside, "utf8") === found.text;
    } catch {
      stop("Another review took the lock first.");
    }
    if (!same) {
      renameSync(aside, path);
      stop("Another review took the lock first.");
    }
    rmSync(aside, { force: true });
  }
  const start = startTime(process.pid);
  if (start === null) stop("ps cannot read this run's start time, so the lock could not cover it.");
  const lock = { ...fields, wrapper: { pid: process.pid, start } };
  try {
    writeFileSync(path, JSON.stringify(lock), { flag: "wx", mode: 0o600 });
  } catch {
    stop("Another review took the lock first.");
  }
  return {
    path,
    lock,
    /// Records the child; false when its start time cannot be read or the lock is no longer this run's.
    setChild(pid) {
      const child = { pid, start: startTime(pid) };
      if (child.start === null || readLock(path)?.lock?.session !== lock.session) return false;
      lock.child = child;
      writeFileSync(`${path}.new`, JSON.stringify(lock), { mode: 0o600 });
      renameSync(`${path}.new`, path);
      return true;
    },
    release() {
      const now = readLock(path);
      if (now?.lock?.session === lock.session) rmSync(path, { force: true });
    },
  };
}
