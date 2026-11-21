// Tests for the headless review's wrapper (scripts/guard/review.mjs) on throwaway repositories, with
// a fake `gh` (GitHub's answers from a JSON file, as in gh-merge.test.mjs) and a fake `claude` that
// prints the events a test gives it: node --test scripts/review-headless.test.mjs
// The wrapper runs from the installed guard, directly with node, so the fake gh comes first on PATH
// and a real gh is never reached. Every name and entry is invented.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { commit, denyListFile, install, installed, ok, repository, secret, slug } from "./guard-fixture.mjs";

const repo = "repos/{owner}/{repo}";
const login = "owner-login";
const tools = ["Task", "Bash", "Edit", "Read", "Write", "mcp__context7__query-docs", "mcp__context7__resolve-library-id"];
// ps is denied inside a session's sandbox; CI has it. The lock needs it (a run without a start time
// refuses), so every test that gets as far as the lock skips without it.
const psWorks = spawnSync("/bin/ps", ["-o", "pid=", "-p", String(process.pid)]).status === 0;
const needsPs = { skip: !psWorks && "ps is not available (a session's sandbox)" };

const fakeGh = `#!${process.execPath}
const { readFileSync } = require("node:fs");
const args = process.argv.slice(2);
// Under the wrapper's environment (gh-post in the fake claude) FAKE_GH is gone: the file next to bin/.
const fakePath = process.env.FAKE_GH ?? require("node:path").join(__dirname, "..", "fake.json");
const fake = JSON.parse(readFileSync(fakePath, "utf8"));
if (args.length === 4 && args[0] === "api" && args[2] === "GET" && Object.hasOwn(fake, args[3])) {
  process.stdout.write(JSON.stringify(fake[args[3]]));
  process.exit(0);
}
// gh-post review: the posted review gets the id the fake's review 555 has.
if (args.length === 6 && args[0] === "api" && args[2] === "POST" && args[3].endsWith("/pulls/7/reviews")) {
  require("node:fs").appendFileSync(fakePath + ".posted", readFileSync(0, "utf8") + "\\n");
  process.stdout.write(JSON.stringify({ id: 555 }));
  process.exit(0);
}
process.stderr.write("gh: Not Found (HTTP 404)\\n");
process.exit(1);
`;

/// The fake claude: what it was started with, and the lock as it finds it, go to started.json; it
/// prints the events (with {{session}} replaced), and can post its review through the installed
/// gh-post (or record one from another session), add a review worktree in its scratchpad, start a
/// grandchild, dirty the checkout, hang, or exit with a status.
function fakeClaude(paths) {
  return `#!${process.execPath}
const fs = require("node:fs");
const { spawn, spawnSync } = require("node:child_process");
const args = process.argv.slice(2);
if (args[0] === "--version") { console.log("9.9.9 (Claude Code)"); process.exit(0); }
const b = JSON.parse(fs.readFileSync(${JSON.stringify(paths.behaviour)}, "utf8"));
const session = args[args.indexOf("--session-id") + 1];
const locks = fs.readdirSync(${JSON.stringify(paths.state)}).filter((name) => name.startsWith("review-"));
const lock = locks.length === 1 ? JSON.parse(fs.readFileSync(${JSON.stringify(paths.state)} + "/" + locks[0], "utf8")) : null;
fs.writeFileSync(${JSON.stringify(paths.started)}, JSON.stringify({ args, env: process.env, cwd: process.cwd(), pid: process.pid, ppid: process.ppid, lock }));
for (const event of b.events) process.stdout.write(JSON.stringify(event).replaceAll("{{session}}", session) + "\\n");
const pad = (b.scratch ?? ${JSON.stringify(paths.scratch)}) + "/" + session + "/scratchpad";
if (b.record === "other") fs.appendFileSync(${JSON.stringify(paths.posts)}, JSON.stringify({ kind: "review", pr: 7, id: 555, session: "another-session", time: "t" }) + "\\n");
else if (b.record) {
  fs.mkdirSync(pad, { recursive: true });
  const head = spawnSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();
  fs.writeFileSync(pad + "/review.json", JSON.stringify({ event: "COMMENT", commit_id: head, body: "a review" }));
  const post = spawnSync(${JSON.stringify(paths.ghPost)}, ["review", "7", pad + "/review.json"], { encoding: "utf8" });
  fs.writeFileSync(${JSON.stringify(paths.ghPostLog)}, JSON.stringify({ status: post.status, stderr: post.stderr }));
}
if (b.worktree) spawnSync("git", ["worktree", "add", "-q", "--detach", pad + "/review/pr-7", "HEAD"]);
if (b.grandchild) {
  const g = spawn(process.execPath, ["-e", "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000)"], { detached: true, stdio: "ignore" });
  fs.writeFileSync(${JSON.stringify(paths.grandchild)}, String(g.pid));
}
if (b.dirty) fs.writeFileSync("dirty.txt", "x");
if (b.hang) { process.on("SIGTERM", () => {}); setInterval(() => {}, 1000); } else process.exitCode = b.exit ?? 0;
`;
}

function marker(round, head, high = 0, owner = 0) {
  return `<!-- moonshine-review round=${round} head=${head} high=${high} medium=0 low=${owner} owner=${owner} -->`;
}

const init = (extra = {}) => ({ type: "system", subtype: "init", session_id: "{{session}}", apiKeySource: "none", mcp_servers: [{ name: "context7", status: "connected" }], tools, plugins: [], ...extra });
const result = (subtype = "success") => ({ type: "result", subtype });

/// A checkout on branch `slice/one` (one commit past main) with the guard installed, PR 7 at its
/// head in the fake GitHub with green checks and no review, and a fake claude that reviews and
/// records its review.
function setUp() {
  const work = repository();
  const scratch = join(work.root, "scratch");
  work.env = { MOONSHINE_SCRATCH_BASE: scratch };
  ok(work, "switch", "-q", "-c", "slice/one");
  commit(work, ".gitignore", "node_modules/\nignored-claude/\n", "ignore");
  commit(work, "docs/a.md", "a\n", "a change");
  const installedResult = install(work, [denyListFile(work, `${secret}\n`)]);
  assert.equal(installedResult.status, 0, installedResult.stderr);
  const bin = join(work.root, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), fakeGh, { mode: 0o755 });
  // The installed gh-post runs `node` from PATH, as the wrapper's PATH names node's folder.
  symlinkSync(process.execPath, join(bin, "node"));
  const paths = {
    behaviour: join(work.root, "behaviour.json"),
    started: join(work.root, "started.json"),
    grandchild: join(work.root, "grandchild.pid"),
    posts: installed(work, "state", "posts.jsonl"),
    state: installed(work, "state"),
    ghPost: installed(work, "bin", "gh-post"),
    ghPostLog: join(work.root, "gh-post.json"),
    scratch: join(scratch, slug(work.cwd)),
  };
  writeFileSync(join(work.root, "claude"), fakeClaude(paths), { mode: 0o755 });
  const configPath = installed(work, "guard", "config.json");
  writeFileSync(configPath, JSON.stringify({ ...JSON.parse(readFileSync(configPath, "utf8")), claude: join(work.root, "claude") }));
  const head = ok(work, "rev-parse", "HEAD").trim();
  const main = ok(work, "rev-parse", "main").trim();
  const context = {
    work,
    head,
    main,
    paths,
    behaviour: { events: [init(), result()], record: true },
    times: "5000,30000,500",
    fake: {
      user: { login },
      [`${repo}/pulls/7`]: {
        state: "open",
        draft: false,
        base: { ref: "main", repo: { full_name: "o/r" } },
        head: { ref: "slice/one", sha: head, repo: { full_name: "o/r" } },
      },
      [`${repo}/branches/main`]: { commit: { sha: main } },
      [`${repo}/commits/${head}/check-runs?filter=latest&per_page=100`]: {
        total_count: 4,
        check_runs: ["docs", "swift", "core-linux", "guard"].map((name, index) => ({
          id: index + 1, name, status: "completed", conclusion: "success", head_sha: head, pull_requests: [{ number: 7 }],
        })),
      },
      [`${repo}/commits/${head}/status`]: { state: "pending", total_count: 0 },
      [`${repo}/pulls/7/reviews?per_page=100&page=1`]: [],
      [`${repo}/pulls/7/reviews/555`]: { id: 555, user: { login }, commit_id: head, body: `ok\n\n${marker(1, head)}\n`, submitted_at: new Date().toISOString() },
    },
  };
  /// Moves PR 7 and its green checks to the checkout's HEAD.
  context.setHead = () => {
    const now = ok(work, "rev-parse", "HEAD").trim();
    const fake = context.fake;
    fake[`${repo}/pulls/7`].head.sha = now;
    const checks = fake[`${repo}/commits/${context.head}/check-runs?filter=latest&per_page=100`];
    fake[`${repo}/commits/${now}/check-runs?filter=latest&per_page=100`] = { ...checks, check_runs: checks.check_runs.map((run) => ({ ...run, head_sha: now })) };
    fake[`${repo}/commits/${now}/status`] = fake[`${repo}/commits/${context.head}/status`];
    context.head = now;
  };
  context.env = () => ({
    HOME: work.home,
    PATH: `${bin}:/usr/bin:/bin`,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    FAKE_GH: join(work.root, "fake.json"),
    MOONSHINE_REVIEW_TEST_TIMES: context.times,
  });
  context.prepare = () => {
    writeFileSync(join(work.root, "fake.json"), JSON.stringify(context.fake));
    writeFileSync(paths.behaviour, JSON.stringify(context.behaviour));
  };
  context.run = (args = ["7", "standard"], extra = {}) => {
    context.prepare();
    return spawnSync(process.execPath, [installed(work, "guard", "review.mjs"), ...args], {
      cwd: work.cwd,
      env: { ...context.env(), ...extra },
      encoding: "utf8",
    });
  };
  context.started = () => (existsSync(paths.started) ? JSON.parse(readFileSync(paths.started, "utf8")) : null);
  context.locks = () => readdirSync(installed(work, "state")).filter((name) => name.startsWith("review-"));
  /// The owner's word for another run on PR `pr` (P-AM2): the installed review-allow-retry.
  context.allowRetry = (args = ["7"], extra = {}) =>
    spawnSync(installed(work, "bin", "review-allow-retry"), args, { env: { HOME: work.home, PATH: "/usr/bin:/bin", ...extra }, encoding: "utf8" });
  context.runs = () => {
    const folder = join(work.home, "Library", "Caches", "moonshine-review");
    return existsSync(folder) ? readdirSync(folder) : [];
  };
  return context;
}

function exits(context, run, code, expected) {
  assert.equal(run.status, code, `${run.stdout}\n${run.stderr}\n${existsSync(context.paths.ghPostLog) ? readFileSync(context.paths.ghPostLog, "utf8") : ""}`);
  if (expected) assert.ok(run.stderr.includes(expected), `missing "${expected}" in:\n${run.stderr}`);
  // Owner, 2026-11-17 (PR #63 round 1): a refusal may be fixed and run again; a started run never.
  if (code === 1) assert.ok(run.stderr.includes("Nothing started and nothing was posted: fix what this names and run review again."), run.stderr);
  if ([5, 6, 7].includes(code)) assert.ok(run.stderr.includes("Do not run review again: tell the owner"), run.stderr);
  assert.ok(!run.stderr.toLowerCase().includes("quolltail"), "no deny-list text");
  assert.deepEqual(context.locks(), [], "the lock is released");
}

/// The stopped runs' records in the state folder.
const stopped = (context) => readdirSync(context.paths.state).filter((name) => name.startsWith("stopped-"));

function refused(context, expected, args) {
  exits(context, context.run(args), 1, expected);
  assert.equal(context.started(), null, "claude must not start");
}

test("a clean run starts claude as probed, and exits 0 with the lock and the run folder removed", needsPs, () => {
  const context = setUp();
  exits(context, context.run(["7", "deep"]), 0, "reviewed and posted");
  const { args, env, cwd } = context.started();
  const session = args[args.indexOf("--session-id") + 1];
  assert.match(session, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  assert.deepEqual(args.slice(0, 2), ["-p", "/review-pr 7 deep headless"]);
  assert.deepEqual(args.slice(args.indexOf("--tools") + 1, args.indexOf("--tools") + 6), ["Read", "Write", "Edit", "Bash", "Task"]);
  assert.equal(args[args.indexOf("--max-budget-usd") + 1], "40");
  for (const flag of ["--strict-mcp-config", "--no-session-persistence", "--verbose"]) assert.ok(args.includes(flag), flag);
  assert.deepEqual([args[args.indexOf("--permission-mode") + 1], args[args.indexOf("--permission-prompts") + 1]], ["default", "none"]);
  assert.equal(args[args.indexOf("--disallowedTools") + 1], `Bash(${installed(context.work, "bin", "review")}:*)`);
  assert.equal(cwd, context.work.cwd);
  const names = Object.keys(env).filter((name) => name !== "__CF_USER_TEXT_ENCODING").sort();
  assert.deepEqual(names, [
    "ENABLE_CLAUDEAI_MCP_SERVERS", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_NO_REPLACE_OBJECTS",
    "HOME", "LANG", "LOGNAME", "MOONSHINE_HEADLESS", "MOONSHINE_HEADLESS_PR", "PATH", "TMPDIR", "USER",
  ]);
  assert.deepEqual(context.runs(), [], "the run folder is removed after exit 0");
  // The real posting path: the installed gh-post, under MOONSHINE_HEADLESS and the live lock.
  assert.equal(env.MOONSHINE_HEADLESS, "1");
  assert.equal(JSON.parse(readFileSync(context.paths.ghPostLog, "utf8")).status, 0);
  assert.match(readFileSync(join(context.work.root, "fake.json.posted"), "utf8"), /"event":"COMMENT"/);
  // The lock recorded this run's session and claude's pid; under caffeinate -i too, which runs
  // claude in the process review started (probe, 2026-11-21, P-AM2).
  const { lock, pid } = context.started();
  assert.deepEqual([lock.session, lock.child?.pid, lock.pr, lock.head], [session, pid, "7", context.head]);
  assert.deepEqual(stopped(context), [], "a reviewed head is not recorded as stopped");
});

test("a run from a linked worktree passes the git folder check and posts", needsPs, () => {
  const context = setUp();
  const tree = join(context.work.root, "linked");
  ok(context.work, "worktree", "add", "-q", tree, "HEAD");
  assert.equal(install(context.work, [denyListFile(context.work, `${secret}\n`)]).status, 0);
  const configPath = installed(context.work, "guard", "config.json");
  writeFileSync(configPath, JSON.stringify({ ...JSON.parse(readFileSync(configPath, "utf8")), claude: join(context.work.root, "claude") }));
  context.behaviour.scratch = join(context.work.root, "scratch", slug(tree));
  context.prepare();
  const run = spawnSync(process.execPath, [installed(context.work, "guard", "review.mjs"), "7", "standard"], { cwd: tree, env: context.env(), encoding: "utf8" });
  exits(context, run, 0, "reviewed and posted");
  assert.equal(context.started().cwd, realpathSync(tree));
});

test("the run's settings allow writes to its own scratchpad only, and its MCP config names context7 only", needsPs, () => {
  const context = setUp();
  context.behaviour.exit = 1; // keep the run folder
  exits(context, context.run(), 6);
  const { args } = context.started();
  const session = args[args.indexOf("--session-id") + 1];
  const settings = JSON.parse(readFileSync(args[args.indexOf("--settings") + 1], "utf8"));
  const pad = `/${context.paths.scratch}/${session}/scratchpad/**`;
  assert.deepEqual(settings.permissions.allow, [`Write(${pad})`, `Edit(${pad})`]);
  for (const rule of ["Bash(git push*)", "Bash(*gh-post comment*)", "Bash(git worktree prune*)", "Bash(claude*)"]) assert.ok(settings.permissions.deny.includes(rule), rule);
  assert.equal(settings.autoMemoryEnabled, false);
  assert.deepEqual(Object.keys(JSON.parse(readFileSync(args[args.indexOf("--mcp-config") + 1], "utf8")).mcpServers), ["context7"]);
});

test("the variable, even empty, and wrong arguments refuse", () => {
  const context = setUp();
  exits(context, context.run(["7", "standard"], { MOONSHINE_HEADLESS: "" }), 1, "inside a headless review");
  for (const args of [[], ["7"], ["7", "quick"], ["07", "deep"], ["7", "deep", "x"]]) exits(context, context.run(args), 2, "usage");
  assert.equal(context.started(), null);
});

for (const [name, change, expected] of [
  ["a closed PR", (c) => (c.fake[`${repo}/pulls/7`].state = "closed"), "not open"],
  ["a draft", (c) => (c.fake[`${repo}/pulls/7`].draft = true), "draft"],
  ["a fork", (c) => (c.fake[`${repo}/pulls/7`].head.repo.full_name = "x/r"), "fork"],
  ["a fork/ branch", (c) => (c.fake[`${repo}/pulls/7`].head.ref = "fork/7-x"), "fork"],
  ["a failed check", (c) => (c.fake[`${repo}/commits/${c.head}/check-runs?filter=latest&per_page=100`].check_runs[0].conclusion = "failure"), "did not pass"],
  ["a GitHub read that fails", (c) => delete c.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`], "could not read"],
  ["a reviewed head", (c) => (c.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`] = [{ user: { login }, body: marker(1, c.head, 1) }]), "review already"],
  ["round 3", (c) => (c.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`] = [{ user: { login }, body: marker(2, c.main, 1) }]), "Round 3"],
  ["round 2 after a round with no High", (c) => (c.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`] = [{ user: { login }, body: marker(1, c.main) }]), "no round 2"],
  ["a main that is not an ancestor", (c) => (c.fake[`${repo}/branches/main`].commit.sha = "f".repeat(40)), "up to date with main"],
]) {
  test(`${name} refuses`, () => {
    const context = setUp();
    change(context);
    refused(context, expected);
  });
}

test("round 2 after a round with a High runs", needsPs, () => {
  const context = setUp();
  context.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`] = [{ user: { login }, body: marker(1, context.main, 1) }];
  exits(context, context.run(), 0);
});

for (const path of [".claude/agents/x.md", ".Claude/x", "docs/CLAUDE.md", "a/claude.local.md", ".mcp.json", "x/.claude/y", "CLAUDE.md"]) {
  test(`a PR that changes ${JSON.stringify(path)} is reviewed by hand`, () => {
    const context = setUp();
    commit(context.work, path, "x\n", "instructions");
    context.setHead();
    refused(context, "reviews it by hand");
  });
}

test("a rename out of .claude/ is reviewed by hand", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "main");
  commit(context.work, ".claude/rule.md", "a rule\nwith lines\n", "rule on main");
  context.fake[`${repo}/branches/main`].commit.sha = ok(context.work, "rev-parse", "HEAD").trim();
  ok(context.work, "switch", "-q", "slice/one");
  ok(context.work, "merge", "-q", "--no-edit", "main");
  ok(context.work, "mv", ".claude/rule.md", "docs/rule.md");
  ok(context.work, "commit", "-q", "-m", "move");
  context.setHead();
  refused(context, "reviews it by hand");
});

for (const [name, change, expected] of [
  ["a changed file", (c) => writeFileSync(join(c.work.cwd, "docs", "a.md"), "edited\n"), "changes or untracked"],
  ["an untracked file", (c) => writeFileSync(join(c.work.cwd, "new.md"), "x\n"), "changes or untracked"],
  ["another HEAD", (c) => ok(c.work, "switch", "-q", "--detach", "main"), "HEAD is not"],
  ["an index flag", (c) => ok(c.work, "update-index", "--skip-worktree", "docs/a.md"), "index flag"],
  ["an ignored CLAUDE.md", (c) => (mkdirSync(join(c.work.cwd, "ignored-claude"), { recursive: true }), writeFileSync(join(c.work.cwd, "ignored-claude", "CLAUDE.md"), "x")), "ignored instruction"],
  ["an ignored .claude/ inside an ignored folder", (c) => (mkdirSync(join(c.work.cwd, "node_modules", "p", ".claude"), { recursive: true }), writeFileSync(join(c.work.cwd, "node_modules", "p", ".claude", "x"), "x")), "ignored instruction"],
]) {
  test(`a checkout with ${name} refuses`, () => {
    const context = setUp();
    change(context);
    refused(context, expected);
  });
}

test("ignored files that are not instructions pass", needsPs, () => {
  const context = setUp();
  mkdirSync(join(context.work.cwd, "node_modules", "p"), { recursive: true });
  writeFileSync(join(context.work.cwd, "node_modules", "p", "index.js"), "x");
  exits(context, context.run(), 0);
});

test("a config without claude refuses", () => {
  const context = setUp();
  const configPath = installed(context.work, "guard", "config.json");
  const { claude, ...rest } = JSON.parse(readFileSync(configPath, "utf8"));
  assert.ok(claude);
  writeFileSync(configPath, JSON.stringify(rest));
  refused(context, "claude was not found");
});

test("a live lock refuses a second review; a malformed one names the file", needsPs, () => {
  const context = setUp();
  context.behaviour = { events: [init()], hang: true };
  context.prepare();
  const first = spawn(process.execPath, [installed(context.work, "guard", "review.mjs"), "7", "standard"], { cwd: context.work.cwd, env: context.env() });
  for (let tries = 0; tries < 200 && context.started() === null; tries += 1) spawnSync("/bin/sleep", ["0.05"]);
  assert.ok(context.started(), "the first run started claude");
  const second = spawnSync(process.execPath, [installed(context.work, "guard", "review.mjs"), "7", "standard"], { cwd: context.work.cwd, env: context.env(), encoding: "utf8" });
  assert.equal(second.status, 1, second.stderr);
  assert.match(second.stderr, /already runs/);
  first.kill("SIGTERM");
  for (let tries = 0; tries < 200 && context.locks().length > 0; tries += 1) spawnSync("/bin/sleep", ["0.05"]);
  assert.deepEqual(context.locks(), [], "the signalled run released its lock");
  const name = createHash("sha256").update(realpathSync(context.work.cwd)).digest("hex").slice(0, 16);
  writeFileSync(installed(context.work, "state", `review-${name}.json`), "{");
  assert.equal(context.allowRetry().status, 0, "the signalled run recorded its head; the owner allows another");
  const third = context.run();
  assert.equal(third.status, 1);
  assert.match(third.stderr, /cannot be read/);
});

for (const [name, events, expected] of [
  ["an API key", [init({ apiKeySource: "ANTHROPIC_API_KEY" }), result()], "API key"],
  ["another MCP server", [init({ mcp_servers: [{ name: "context7" }, { name: "tasks" }] }), result()], "MCP server"],
  ["an unexpected tool", [init({ tools: [...tools, "CronCreate"] }), result()], "expected set"],
  ["another session", [init({ session_id: "11111111-2222-3333-4444-555555555555" }), result()], "another session"],
  ["a plugin not listed", [init({ plugins: [{ name: "p", path: "/x", source: "p@builtin" }] }), result()], "review-plugins.txt"],
  ["a later start event that breaks a gate", [init(), init({ tools: [...tools, "Workflow"] }), result()], "expected set"],
  ["no start event in the first lines", [...Array(20).fill({ type: "assistant" }), init(), result()], "no start event"],
  ["no start event at all", [result()], "no start event"],
]) {
  test(`a start gate stops ${name} with exit 7`, needsPs, () => {
    const context = setUp();
    context.behaviour = { events, record: true, hang: name === "no start event at all" };
    context.times = "1000,30000,500";
    exits(context, context.run(), 7, expected);
  });
}

test("a plugin listed in review-plugins.txt passes the gate", needsPs, () => {
  const context = setUp();
  writeFileSync(installed(context.work, "review-plugins.txt"), "p@builtin\r\nq@builtin\n");
  context.behaviour.events = [init({ plugins: [{ name: "p", path: "/x", source: "p@builtin" }] }), result()];
  exits(context, context.run(), 0);
});

for (const [name, behaviour, code, expected] of [
  ["the last result decides: an error, then success", { events: [init(), result("error_during_execution"), init(), result()], record: true }, 0],
  ["the last result decides: success, then an error", { events: [init(), result(), init(), result("error_during_execution")], record: true }, 6, "error_during_execution"],
  ["a budget stop", { events: [init(), result("error_max_budget_usd")], exit: 1 }, 6, "error_max_budget_usd"],
  ["claude's non-zero exit", { events: [init(), result()], record: true, exit: 3 }, 6, "exited with 3"],
  ["no recorded review", { events: [init(), result()] }, 6, "recorded from this run's session"],
  ["a review recorded from another session", { events: [init(), result()], record: "other" }, 6, "recorded from this run's session"],
  ["a checkout changed during the run", { events: [init(), result()], record: true, dirty: true }, 6, "changed during the run"],
]) {
  test(`${name}: exit ${code}`, needsPs, () => {
    const context = setUp();
    context.behaviour = behaviour;
    exits(context, context.run(), code, expected);
  });
}

// PR #63 round 1: each field of the final check, alone.
for (const [name, change, expected] of [
  ["by another account", (review) => (review.user.login = "someone-else"), "by another account"],
  ["on another commit", (review, c) => (review.commit_id = c.main), "on another commit"],
  ["with no marker", (review) => (review.body = "ok\n"), "no counted marker"],
  ["whose marker names another head", (review, c) => (review.body = `ok\n\n${marker(1, c.main)}\n`), "marker names another head"],
  ["dated before the run", (review) => (review.submitted_at = new Date(Date.now() - 3_600_000).toISOString()), "older than the run"],
]) {
  test(`a recorded review ${name} fails the run`, needsPs, () => {
    const context = setUp();
    change(context.fake[`${repo}/pulls/7/reviews/555`], context);
    exits(context, context.run(), 6, expected);
  });
}

// PR #63 round 1: the wrapper exited in the tick that ended the log, so the events read in that
// tick, the ones that explain the stop, were lost. Here a gate stops the run in the same burst.
test("a stopped run's kept log holds every event up to the stop", needsPs, () => {
  const context = setUp();
  const events = [init(), ...Array.from({ length: 3000 }, (_, index) => ({ type: "assistant", index, text: "x".repeat(200) })), init({ tools: [...tools, "Workflow"] })];
  context.behaviour = { events, hang: true };
  exits(context, context.run(), 7, "expected set");
  const [folder] = context.runs();
  const kept = readFileSync(join(context.work.home, "Library", "Caches", "moonshine-review", folder, "stream.jsonl"), "utf8").trim().split("\n");
  assert.equal(kept.length, events.length);
});

test("after a budget stop the run's worktrees are removed by path; another worktree stays", needsPs, () => {
  const context = setUp();
  const other = join(context.work.root, "other-wt");
  ok(context.work, "worktree", "add", "-q", "--detach", other, "main");
  context.behaviour = { events: [init(), result("error_max_budget_usd")], worktree: true, exit: 1 };
  const run = context.run();
  exits(context, run, 6, "1 worktree(s) removed");
  const listed = ok(context.work, "worktree", "list", "--porcelain");
  assert.ok(listed.includes(other));
  assert.ok(!listed.includes("/review/pr-7"));
});

test("failed runs keep the newest three run folders", needsPs, () => {
  const context = setUp();
  context.behaviour = { events: [init(), result()], exit: 1 };
  for (let index = 0; index < 5; index += 1) {
    exits(context, context.run(), 6);
    assert.equal(context.allowRetry().status, 0);
    spawnSync("/bin/sleep", ["0.05"]);
  }
  assert.equal(context.runs().length, 3);
});

test("the time limit ends claude, even when it ignores SIGTERM, with exit 5", needsPs, () => {
  const context = setUp();
  context.behaviour = { events: [init()], hang: true, grandchild: true };
  context.times = "5000,1500,300";
  exits(context, context.run(), 5, "time limit");
  const gone = (pid) => {
    try {
      process.kill(pid, 0);
      return false;
    } catch (error) {
      return error.code === "ESRCH";
    }
  };
  assert.ok(gone(context.started().pid), "claude is gone");
  assert.ok(gone(Number(readFileSync(context.paths.grandchild, "utf8"))), "its detached grandchild is gone");
});

test("a deny-list entry never reaches the output", () => {
  const context = setUp();
  const checks = context.fake[`${repo}/commits/${context.head}/check-runs?filter=latest&per_page=100`];
  checks.check_runs.push({ id: 9, name: secret, status: "queued", conclusion: null, head_sha: context.head, pull_requests: [{ number: 7 }] });
  checks.total_count = 5;
  refused(context, "still running");
});

// P-AM2 (owner, 2026-11-17 and 2026-11-20): round 2 after owner findings on a plain PR, once round 1
// is answered with the owner decisions block and the owner's decisions file exists.
const decisionsBlock = "Answer.\n\nOwner decisions: Claude outputs/next/pr7-round1.md\n- docs/a.md:1: keep as is\n";

/// Round 1 on main with one owner finding, a plain body, the answer at 11:00 and the decisions file
/// (git-ignored, as `Claude outputs/` is in the repository). `options` change one part each.
function ownerRound1(context, options = {}) {
  const { body = "Class: plain\n\nA change.\n", answer = decisionsBlock, by = login, file = true, high = 0 } = options;
  context.fake[`${repo}/pulls/7`].body = body;
  context.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`] = [
    { user: { login }, body: marker(1, options.head ?? context.main, high, 1), submitted_at: "2026-11-20T10:00:00Z" },
    ...(options.reviews ?? []),
  ];
  context.fake[`${repo}/issues/7/comments?per_page=100&page=1`] = answer === null ? [] : [{ id: 990, user: { login: by }, created_at: "2026-11-20T11:00:00Z", body: answer }];
  const exclude = resolve(context.work.cwd, ok(context.work, "rev-parse", "--git-path", "info/exclude").trim());
  mkdirSync(dirname(exclude), { recursive: true });
  appendFileSync(exclude, "Claude outputs/\n");
  if (file) {
    mkdirSync(join(context.work.cwd, "Claude outputs", "next"), { recursive: true });
    writeFileSync(join(context.work.cwd, "Claude outputs", "next", "pr7-round1.md"), "the owner's decisions\n");
  }
}

test("round 2 after owner findings on a plain PR, answered with the decisions block, runs", needsPs, () => {
  const context = setUp();
  ownerRound1(context);
  exits(context, context.run(), 0, "reviewed and posted");
});

for (const [name, options, expected] of [
  ["a risky PR", { body: "Class: risky\n" }, "no round 2"],
  ["a body with no class line", { body: "A change.\n" }, "no round 2"],
  ["no answer", { answer: null }, "owner decisions block"],
  ["an answer without the block", { answer: "Answer.\n" }, "owner decisions block"],
  ["the block with no item", { answer: "Owner decisions: Claude outputs/next/pr7-round1.md\n" }, "owner decisions block"],
  ["the block by another account", { by: "stranger" }, "owner decisions block"],
  ["the block naming round 2's file", { answer: decisionsBlock.replace("round1", "round2") }, "owner decisions block"],
  ["no decisions file", { file: false }, "is not in the checkout"],
  ["a round 1 head that is not an ancestor", { head: "f".repeat(40) }, "not an ancestor"],
  [
    "another account's marker, second of two",
    { reviews: [{ user: { login: "stranger" }, body: "a comment" }, { user: { login: "stranger" }, body: "<!-- moonshine-review round=1 -->" }] },
    "Another account posted a review marker",
  ],
  ["another account's upper-case marker", { reviews: [{ user: { login: "stranger" }, body: "<!--MOONSHINE-REVIEW round=1-->" }] }, "Another account posted a review marker"],
]) {
  test(`round 2 after owner findings refuses with ${name}`, () => {
    const context = setUp();
    ownerRound1(context, options);
    refused(context, expected);
  });
}

test("round 2 after a High needs no decisions block, also on a risky PR", needsPs, () => {
  const context = setUp();
  ownerRound1(context, { body: "Class: risky\n", answer: null, file: false, high: 1 });
  context.fake[`${repo}/pulls/7/reviews?per_page=100&page=1`][0].body = marker(1, context.main, 1);
  exits(context, context.run(), 0, "reviewed and posted");
});

// P-AM2 (owner, 2026-11-20): after a start, the head is not reviewed again without the owner's word.
test("a run stopped after its start records its head; the next run refuses until the owner allows it", needsPs, () => {
  const context = setUp();
  context.behaviour.exit = 1;
  exits(context, context.run(), 6);
  assert.deepEqual(stopped(context), [`stopped-7-${context.head}.json`]);
  assert.deepEqual(Object.keys(JSON.parse(readFileSync(join(context.paths.state, stopped(context)[0]), "utf8"))).sort(), ["code", "head", "pr", "time"]);
  rmSync(context.paths.started);
  refused(context, "review-allow-retry 7");
  const allowed = context.allowRetry();
  assert.equal(allowed.status, 0, allowed.stderr);
  assert.deepEqual(stopped(context), []);
  context.behaviour.exit = 0;
  exits(context, context.run(), 0, "reviewed and posted");
});

test("a stopped record refuses its head only: another head of the PR runs", needsPs, () => {
  const context = setUp();
  writeFileSync(join(context.paths.state, `stopped-7-${"b".repeat(40)}.json`), "{}");
  exits(context, context.run(), 0, "reviewed and posted");
});

test("a stopped record refuses before anything starts", () => {
  const context = setUp();
  writeFileSync(join(context.paths.state, `stopped-7-${context.head}.json`), "{}");
  refused(context, "stopped after its start");
});

test("review-allow-retry clears its PR's records only, and refuses inside a headless run and bad arguments", () => {
  const context = setUp();
  for (const name of [`stopped-7-${context.head}.json`, `stopped-70-${context.head}.json`]) writeFileSync(join(context.paths.state, name), "{}");
  assert.equal(context.allowRetry(["7"], { MOONSHINE_HEADLESS: "" }).status, 1);
  for (const args of [[], ["07"], ["7x"], ["7", "8"], ["12345678"], ["*"]]) assert.equal(context.allowRetry(args).status, 2, JSON.stringify(args));
  assert.equal(stopped(context).length, 2, "nothing is removed by a refusal");
  const allowed = context.allowRetry(["7"]);
  assert.equal(allowed.status, 0, allowed.stderr);
  assert.match(allowed.stdout, /PR 7 may be reviewed again/);
  assert.deepEqual(stopped(context), [`stopped-70-${context.head}.json`]);
});

// The assertion is held by a forked caffeinate whose arguments name claude (probe, 2026-11-21).
test("claude runs under caffeinate -i on macOS while the run lasts", { skip: (!existsSync("/usr/bin/caffeinate") && "not macOS") || needsPs.skip }, async () => {
  const context = setUp();
  context.behaviour = { events: [init()], hang: true };
  context.times = "5000,3000,200";
  context.prepare();
  const run = spawn(process.execPath, [installed(context.work, "guard", "review.mjs"), "7", "standard"], { cwd: context.work.cwd, env: context.env() });
  const ended = new Promise((resolve) => run.once("exit", resolve));
  for (let tries = 0; tries < 200 && context.started() === null; tries += 1) spawnSync("/bin/sleep", ["0.05"]);
  const listed = spawnSync("/bin/ps", ["-A", "-o", "args="], { encoding: "utf8" }).stdout;
  assert.ok(listed.split("\n").some((line) => line.startsWith(`/usr/bin/caffeinate -i ${join(context.work.root, "claude")} -p`)), "a caffeinate names claude");
  assert.equal(await ended, 5);
});
