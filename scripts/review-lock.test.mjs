// Tests for the headless review's lock (scripts/guard/review-lock.mjs): node --test scripts/review-lock.test.mjs
// Each test imports a copy of the guard folder in a temporary directory, so the lock's state folder
// (next to the guard) is never inside the repository. Tests that read process trees or start times
// need ps, which a session's sandbox denies; CI has it.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { commit, ok, repository } from "./guard-fixture.mjs";

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
const staleSession = "0a1b2c3d-0000-4000-8000-000000000003";
const head = "a".repeat(40);

/// A lock held by this test process. Without ps its start time is a stand-in, which counts as live.
function record(lock, top, extra = {}) {
  const start = lock.startTime(process.pid) ?? "unknown";
  return { pr: "7", head, session, top, sessionDir: join(top, "..", "scratch", session), wrapper: { pid: process.pid, start }, ...extra };
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

// PR #63 round 1: a start time that ps could not read was stored as null, and the lock stopped
// covering a live run once ps worked again.
test("a lock without a start time counts as live (malformed), for the wrapper and the child", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top, { wrapper: { pid: process.pid, start: null } }));
  assert.equal(lock.liveLockFor(top)?.malformed, true);
  write(state, lock, top, record(lock, top, { child: { pid: process.pid, start: "" } }));
  assert.equal(lock.liveLockFor(top)?.malformed, true);
});

test("a live wrapper refuses a second lock", async () => {
  const { lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  write(state, lock, top, record(lock, top));
  assert.throws(() => lock.takeLock({ pr: "7", head, session, top, sessionDir: top }, stop), /already runs/);
});

/// A repository with a stale lock (its wrapper gone) of session `staleSession` for PR 7, review
/// worktrees of that session, a worktree of its own in that session's scratchpad, and another one.
function staleSetUp(lock, state, extra = {}) {
  const work = repository();
  const old = join(work.root, "scratch", staleSession);
  const review = join(old, "scratchpad", "review");
  for (const name of ["pr-7", "pr-7-probe-tests"]) ok(work, "worktree", "add", "-q", "--detach", join(review, name), "HEAD");
  ok(work, "worktree", "add", "-q", "--detach", join(review, "pr-70"), "HEAD");
  ok(work, "worktree", "add", "-q", "--detach", join(old, "scratchpad", "author"), "HEAD");
  ok(work, "worktree", "add", "-q", "--detach", join(work.root, "kept"), "HEAD");
  write(state, lock, work.cwd, record(lock, work.cwd, { session: staleSession, sessionDir: old, wrapper: { pid: deadPid(), start: "x" }, ...extra }));
  const fields = { pr: "8", head, session, top: work.cwd, sessionDir: join(work.root, "scratch", session) };
  const listed = () => ok(work, "worktree", "list", "--porcelain");
  return { work, old, fields, listed };
}

/// Asserts that `child` was not signalled, then ends it.
async function lives(child) {
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.deepEqual([child.exitCode, child.signalCode], [null, null], "the process lives");
  child.kill("SIGKILL");
}

async function liveChild() {
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { detached: true, stdio: "ignore" });
  await new Promise((resolve) => child.once("spawn", resolve));
  return child;
}

test("replacing a stale lock kills its recorded claude and removes its review worktrees of its PR only", { skip: noPs }, async () => {
  const { lock, state } = await guardCopy();
  const child = await liveChild();
  const { work, fields, listed } = staleSetUp(lock, state, { child: { pid: child.pid, start: lock.startTime(child.pid) } });
  const exited = new Promise((resolve) => child.once("exit", resolve));
  const taken = lock.takeLock(fields, stop, process.execPath);
  await exited;
  const after = listed();
  assert.ok(!after.includes("/review/pr-7\n") && !after.includes("pr-7-probe-tests"), "the stale session's review worktrees of PR 7 are removed");
  for (const kept of ["/review/pr-70", "/scratchpad/author", join(work.root, "kept")]) assert.ok(after.includes(kept), kept);
  assert.equal(JSON.parse(readFileSync(taken.path, "utf8")).pr, "8");
  taken.release();
  assert.ok(!existsSync(taken.path));
});

// PR #63 round 1: a forged stale lock made the next review kill any process and remove any worktree.
for (const [name, extra, expected] of [
  ["a session folder outside this scratch root", (work) => ({ sessionDir: join(work.root, "elsewhere", staleSession) }), "another checkout or session folder"],
  ["a session folder of another session", (work) => ({ sessionDir: join(work.root, "scratch", session) }), "another checkout or session folder"],
  ["another checkout", (work) => ({ top: join(work.root, "kept") }), "another checkout or session folder"],
]) {
  test(`a stale lock naming ${name} is refused and touches nothing`, async () => {
    const { lock, state } = await guardCopy();
    const child = await liveChild();
    const { work, fields, listed } = staleSetUp(lock, state);
    const before = listed();
    write(state, lock, work.cwd, { ...JSON.parse(readFileSync(lock.lockPath(work.cwd), "utf8")), child: { pid: child.pid, start: lock.startTime(child.pid) ?? "unknown" }, ...extra(work) });
    assert.throws(() => lock.takeLock(fields, stop, process.execPath), (error) => error.message.includes(expected) && error.message.includes(lock.lockPath(work.cwd)));
    assert.equal(listed(), before, "no worktree is removed");
    await lives(child);
  });
}

test("a stale lock whose live child is not claude is refused and touches nothing", async () => {
  const { lock, state } = await guardCopy();
  const child = await liveChild();
  const { fields, listed } = staleSetUp(lock, state, { child: { pid: child.pid, start: lock.startTime(child.pid) ?? "unknown" } });
  const before = listed();
  assert.throws(() => lock.takeLock(fields, stop, "/nowhere/claude"), /names a live process that is not claude/);
  assert.equal(listed(), before);
  await lives(child);
});

test("setChild records the child only while the lock is this run's", { skip: noPs }, async () => {
  const { lock } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  const taken = lock.takeLock({ pr: "7", head, session, top, sessionDir: join(top, "s", session) }, stop, process.execPath);
  assert.equal(taken.setChild(process.pid), true);
  assert.equal(JSON.parse(readFileSync(taken.path, "utf8")).child.pid, process.pid);
  writeFileSync(taken.path, JSON.stringify({ ...JSON.parse(readFileSync(taken.path, "utf8")), session: staleSession }));
  assert.equal(taken.setChild(process.pid), false);
  assert.equal(JSON.parse(readFileSync(taken.path, "utf8")).session, staleSession, "another run's lock is not replaced");
});

test("two wrappers taking the lock at once: one wins", { skip: noPs }, async () => {
  const { root } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  const url = JSON.stringify(pathToFileURL(join(root, "guard", "review-lock.mjs")).href);
  const code = `import { takeLock } from ${url};
takeLock({ pr: "7", head: "${head}", session: "${session}", top: ${JSON.stringify(top)}, sessionDir: ${JSON.stringify(top)} }, (m) => { console.log("refused"); process.exit(0); });
console.log("taken"); setTimeout(() => {}, 1500);`;
  const runs = [0, 1].map(() => spawn(process.execPath, ["--input-type=module", "-e", code], { encoding: "utf8" }));
  assert.deepEqual((await outputs(runs)).sort(), ["refused", "taken"]);
});

function outputs(runs) {
  return Promise.all(
    runs.map((run) => new Promise((resolve) => {
      let out = "";
      run.stdout.on("data", (chunk) => (out += chunk));
      run.on("close", () => resolve(out.trim()));
    })),
  );
}

// PR #63 round 1: wrapper B read a stale lock, spent a second in git, and then took over the lock
// wrapper A had written meanwhile, so both ran. A git that sleeps slows B; A waits until B has read.
test("two wrappers replacing one stale lock: one wins", { skip: noPs }, async () => {
  const { root, lock, state } = await guardCopy();
  const top = realpathSync(mkdtempSync(join(tmpdir(), "top-")));
  const scratch = join(top, "..", "scratch");
  write(state, lock, top, record(lock, top, { session: staleSession, sessionDir: join(scratch, staleSession), wrapper: { pid: deadPid(), start: "x" } }));
  const slow = join(root, "slow");
  mkdirSync(slow);
  const realGit = spawnSync("/bin/sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
  writeFileSync(join(slow, "git"), `#!/bin/sh\n/bin/sleep 1\nexec '${realGit}' "$@"\n`);
  chmodSync(join(slow, "git"), 0o755);
  const url = JSON.stringify(pathToFileURL(join(root, "guard", "review-lock.mjs")).href);
  const code = (id, wait) => `import { takeLock } from ${url};
Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ${wait});
takeLock({ pr: "7", head: "${head}", session: "${id}", top: ${JSON.stringify(top)}, sessionDir: ${JSON.stringify(join(scratch, id))} }, (m) => { console.log("refused"); process.exit(0); }, "/nowhere/claude");
console.log("taken"); setTimeout(() => {}, 2500);`;
  const runs = [
    spawn(process.execPath, ["--input-type=module", "-e", code(session, 0)], { env: { ...process.env, PATH: `${slow}:${process.env.PATH}` } }),
    spawn(process.execPath, ["--input-type=module", "-e", code("0a1b2c3d-0000-4000-8000-000000000004", 300)]),
  ];
  assert.deepEqual((await outputs(runs)).sort(), ["refused", "taken"]);
});

// PR #63 round 1: git lists an ignored nested repository (a package checkout) as one folder entry.
function cleanSetUp() {
  const work = repository();
  commit(work, ".gitignore", ".build/\n.claude/settings.local.json\n.claude/.cc-writes/\n", "ignore");
  const dep = join(work.cwd, ".build", "checkouts", "Dep");
  mkdirSync(join(dep, "Sources", "Dep"), { recursive: true });
  ok({ ...work, cwd: dep }, "init", "-q");
  writeFileSync(join(dep, "Sources", "Dep", "Dep.swift"), "let dep = 1\n");
  return { work, dep, clean: (lock) => lock.checkoutClean(work.cwd, ok(work, "rev-parse", "HEAD").trim()) };
}

for (const path of ["CLAUDE.md", "Sources/claude.local.md", "Sources/Dep/.claude/settings.json", ".claude/agents/x.md", ".mcp.json"]) {
  test(`an ignored nested repository with ${path} refuses`, async () => {
    const { lock } = await guardCopy();
    const { dep, clean } = cleanSetUp();
    mkdirSync(dirname(join(dep, path)), { recursive: true });
    writeFileSync(join(dep, path), "x\n");
    assert.match(clean(lock), /ignored nested repository/);
  });
}

test("the allowed ignored files pass: the local settings and write logs, also inside a nested repository", async () => {
  const { lock } = await guardCopy();
  const { work, dep, clean } = cleanSetUp();
  for (const path of [join(work.cwd, ".claude", "settings.local.json"), join(work.cwd, ".claude", ".cc-writes", "a"), join(dep, ".claude", ".cc-writes", "a"), join(dep, "Sources", "Dep", ".claude", ".cc-writes", "b")]) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "x\n");
  }
  assert.equal(clean(lock), null);
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

// P-AM2 (owner, 2026-11-20): a stopped run names a sleep of the Mac.
test("the sleep watch adds up the wall clock's steps beyond the monotonic clock's", async () => {
  const { lock } = await guardCopy();
  let [wall, mono] = [1_000_000, 50];
  const watch = lock.sleepWatch(60_000, () => wall, () => mono);
  [wall, mono] = [wall + 10_000, mono + 10_000];
  assert.equal(watch.slept(), 0, "awake: both clocks step alike");
  [wall, mono] = [wall + 600_000, mono + 1_000];
  assert.equal(watch.slept(), 599_000, "asleep: the wall clock ran on");
  [wall, mono] = [wall - 5_000, mono + 1_000];
  assert.equal(watch.slept(), 599_000, "a clock set back adds nothing");
  watch.stop();
});

// P-GX (owner, 2026-11-28): a session waiting on a review sees its output grow.
test("the heartbeat prints the event count at most every 5 minutes, counts only", async () => {
  const { lock } = await guardCopy();
  const written = [];
  let now = 1_000;
  const beat = lock.heartbeat((line) => written.push(line), 300_000, () => now);
  beat.event();
  now += 299_999;
  beat.event();
  assert.deepEqual(written, [], "nothing before 5 minutes");
  now += 1;
  beat.event();
  assert.deepEqual(written, ["review: 3 events\n"]);
  now += 299_999;
  beat.event();
  assert.equal(written.length, 1, "nothing again before the next 5 minutes");
  now += 1;
  beat.event();
  assert.deepEqual(written, ["review: 3 events\n", "review: 5 events\n"]);
  now += 3_600_000;
  assert.equal(written.length, 2, "no event, no line: a stopped stream prints nothing");
  for (const line of written) assert.match(line, /^review: \d+ events\n$/);
});

test("a stopped run's record is not named like a lock", async () => {
  const { lock, state } = await guardCopy();
  const path = lock.stoppedPath("7", head);
  assert.equal(dirname(path), state);
  assert.ok(!/^review-/.test(path.slice(state.length + 1)));
});
