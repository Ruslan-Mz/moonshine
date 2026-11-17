// Tests for the headless review's lock (scripts/guard/review-lock.mjs): node --test scripts/review-lock.test.mjs
// Each test imports a copy of the guard folder in a temporary directory, so the lock's state folder
// (next to the guard) is never inside the repository. Tests that read process trees or start times
// need ps, which a session's sandbox denies; CI has it.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ok, repository } from "./guard-fixture.mjs";

const scripts = dirname(fileURLToPath(import.meta.url));
const psWorks = spawnSync("/bin/ps", ["-o", "pid=", "-p", String(process.pid)]).status === 0;
const noPs = !psWorks && "ps is not available (a session's sandbox)";

async function guardCopy() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "lock-")));
  cpSync(join(scripts, "guard"), join(root, "guard"), { recursive: true });
  mkdirSync(join(root, "state"));
  const lock = await import(pathToFileURL(join(root, "guard", "review-lock.mjs")).href);
  return { root, lock, state: join(root, "state") };
}

const session = "0a1b2c3d-0000-4000-8000-000000000001";
const head = "a".repeat(40);

function record(lock, top, extra = {}) {
  return { pr: "7", head, session, top, sessionDir: join(top, "..", "scratch", session), wrapper: { pid: process.pid, start: lock.startTime(process.pid) }, ...extra };
}

function write(state, lock, top, value) {
  writeFileSync(lock.lockPath(top), typeof value === "string" ? value : JSON.stringify(value));
}

/// A pid that existed and has exited.
function deadPid() {
  const child = spawnSync(process.execPath, ["-e", "console.log(process.pid)"], { encoding: "utf8" });
  return Number(child.stdout.trim());
}

const stop = (message) => {
  throw new Error(message);
};

test("the start time reads the same under another LANG and TZ, and under a cleared environment", { skip: noPs }, async () => {
  const { root } = await guardCopy();
  const read = (env) =>
    spawnSync(process.execPath, ["--input-type=module", "-e", `import { startTime } from ${JSON.stringify(pathToFileURL(join(root, "guard", "review-lock.mjs")).href)}; console.log(startTime(${process.pid}));`], {
      env: { PATH: process.env.PATH, ...env },
      encoding: "utf8",
    }).stdout.trim();
  const plain = read({});
  assert.notEqual(plain, "null");
  assert.equal(read({ LANG: "ru_RU.UTF-8", LC_ALL: "ru_RU.UTF-8", TZ: "Asia/Tokyo" }), plain);
  assert.equal(read({ TZ: "America/Los_Angeles" }), plain);
});

test("a live lock covers its checkout and paths in its session folder, not another checkout", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  const value = record(lock, top);
  mkdirSync(join(value.sessionDir, "scratchpad", "wt"), { recursive: true });
  write(state, lock, top, value);
  assert.equal(lock.liveLockFor(top)?.lock.session, session);
  assert.equal(lock.liveLockFor(join(value.sessionDir, "scratchpad", "wt"))?.lock.session, session, "the run's own worktree");
  assert.equal(lock.liveLockFor(null)?.lock.session, session, "no checkout: any live lock");
  assert.equal(lock.liveLockFor(realpathSync(mkdtempSync(join(tmpdir(), "other-")))), null);
});

test("a lock whose processes are gone does not count", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top, { wrapper: { pid: deadPid(), start: "x" }, child: { pid: deadPid(), start: "y" } }));
  assert.equal(lock.liveLockFor(top), null);
});

test("a live pid with another start time is stale; when ps fails it counts as live", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top, { wrapper: { pid: process.pid, start: "Thu Jan  1 00:00:00 1970" } }));
  if (psWorks) assert.equal(lock.liveLockFor(top), null);
  else assert.notEqual(lock.liveLockFor(top), null, "without ps, the lock restricts");
});

test("a live child with a gone wrapper counts as live", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top, { wrapper: { pid: deadPid(), start: "x" }, child: { pid: process.pid, start: lock.startTime(process.pid) } }));
  assert.notEqual(lock.liveLockFor(top), null);
});

test("a malformed lock counts as live and names its file", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, '{"pr":"7"');
  assert.deepEqual(lock.liveLockFor(top), { malformed: true, path: lock.lockPath(top) });
  assert.throws(() => lock.takeLock({ pr: "7", head, session, top, sessionDir: top }, stop), /cannot be read/);
});

test("a live wrapper refuses a second lock", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top));
  assert.throws(() => lock.takeLock({ pr: "7", head, session, top, sessionDir: top }, stop), /already runs/);
});

test("replacing a stale lock kills its recorded child and removes its session's worktrees only", async () => {
  const { lock, state } = await guardCopy();
  const work = repository();
  const old = join(work.root, "scratch", "old-session");
  ok(work, "worktree", "add", "-q", "--detach", join(old, "scratchpad", "wt"), "HEAD");
  ok(work, "worktree", "add", "-q", "--detach", join(work.root, "kept"), "HEAD");
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { detached: true, stdio: "ignore" });
  await new Promise((resolve) => child.once("spawn", resolve));
  write(state, lock, work.cwd, record(lock, work.cwd, { sessionDir: old, wrapper: { pid: deadPid(), start: "x" }, child: { pid: child.pid, start: lock.startTime(child.pid) } }));
  const exited = new Promise((resolve) => child.once("exit", resolve));
  const taken = lock.takeLock({ pr: "8", head, session, top: work.cwd, sessionDir: join(work.root, "scratch", session) }, stop);
  await exited;
  const listed = ok(work, "worktree", "list", "--porcelain");
  assert.ok(!listed.includes("old-session"), "the stale session's worktree is removed");
  assert.ok(listed.includes(join(work.root, "kept")), "another worktree stays");
  assert.equal(JSON.parse(readFileSync(taken.path, "utf8")).pr, "8");
  taken.release();
  assert.ok(!existsSync(taken.path));
});

test("two wrappers taking the lock at once: one wins", async () => {
  const { root } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  const url = JSON.stringify(pathToFileURL(join(root, "guard", "review-lock.mjs")).href);
  const code = `import { takeLock } from ${url};
takeLock({ pr: "7", head: "${head}", session: "${session}", top: ${JSON.stringify(top)}, sessionDir: ${JSON.stringify(top)} }, (m) => { console.log("refused"); process.exit(0); });
console.log("taken"); setTimeout(() => {}, 1500);`;
  const runs = [0, 1].map(() => spawn(process.execPath, ["--input-type=module", "-e", code], { encoding: "utf8" }));
  const outputs = await Promise.all(
    runs.map((run) => new Promise((resolve) => {
      let out = "";
      run.stdout.on("data", (chunk) => (out += chunk));
      run.on("close", () => resolve(out.trim()));
    })),
  );
  assert.deepEqual(outputs.sort(), ["refused", "taken"]);
});

test("killTree ends a grandchild whose parent exited first, and one in its own session", { skip: noPs }, async () => {
  const { lock, root } = await guardCopy();
  const pids = join(root, "pids");
  // The root leads its group. Its first child starts a sleeper in the group and exits, so the sleeper
  // is reparented; its second child stays and starts a sleeper in a session of its own.
  writeFileSync(
    join(root, "keep.cjs"),
    `const c = require("node:child_process").spawn("/bin/sleep", ["300"], { detached: true, stdio: "ignore" });\n` +
      `require("node:fs").appendFileSync(${JSON.stringify(pids)}, c.pid + "\\n");\nsetInterval(() => {}, 1000);\n`,
  );
  writeFileSync(
    join(root, "tree.sh"),
    `/bin/sh -c 'sleep 300 & echo $! >> "${pids}"'\n'${process.execPath}' '${join(root, "keep.cjs")}' &\nsleep 300\n`,
  );
  const rootProcess = spawn("/bin/sh", [join(root, "tree.sh")], { detached: true, stdio: "ignore" });
  const count = () => (existsSync(pids) ? readFileSync(pids, "utf8").trim().split("\n").length : 0);
  for (let tries = 0; tries < 200 && count() < 2; tries += 1) spawnSync("/bin/sleep", ["0.05"]);
  const sleepers = readFileSync(pids, "utf8").trim().split("\n").map(Number);
  assert.equal(sleepers.length, 2);
  const exited = new Promise((resolve) => rootProcess.once("exit", resolve));
  lock.killTree([rootProcess.pid], 2000);
  await exited;
  const gone = (pid) => {
    try {
      process.kill(pid, 0);
      return false;
    } catch (error) {
      return error.code === "ESRCH";
    }
  };
  for (let tries = 0; tries < 40 && !sleepers.every(gone); tries += 1) spawnSync("/bin/sleep", ["0.05"]);
  for (const pid of sleepers) assert.ok(gone(pid), `sleeper ${pid}`);
});
