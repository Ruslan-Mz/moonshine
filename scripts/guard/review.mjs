// review <pr> standard|deep: the author session starts /review-pr as a separate headless claude
// process (P-HR; CLAUDE.md → "Pull requests"). The installed bin/review runs this file in a cleared
// environment, after refusing inside a headless run. It refuses unless the checkout, the PR and CI
// are as the review needs them, takes the review lock, runs claude with private settings, a fixed
// tool set and Context7 as the only MCP server, checks every start event, and decides from the last
// result and the recorded review. It prints the exit reason and the log folder, never review text.
// Exits: 0 reviewed and posted · 1 refused · 2 usage · 5 time limit · 6 the run failed · 7 a start
// gate. A refusal (1) started nothing: the author may fix what it names and run review again; after
// a start (5, 6, 7) it is never retried (owner, 2026-11-17, PR #63 round 1).
// Tests: node --test scripts/review-headless.test.mjs
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createWriteStream, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir, userInfo } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { ciGreen, gitHub, repo, reviewMarker, safeGit } from "./github.mjs";
import { config, denyList } from "./matcher.mjs";
import { readPosts } from "./merge.mjs";
import { instructions } from "./plain-rules.mjs";
import { checkoutClean, killTree, removeWorktrees, takeLock } from "./review-lock.mjs";

const home = join(dirname(fileURLToPath(import.meta.url)), "..");
const budget = { standard: "15", deep: "40" };
const minutes = { standard: 60, deep: 120 };
const tools = ["Read", "Write", "Edit", "Bash", "Task"];
// Probe 4 (2.1.285): the start event lists exactly these.
const expectedTools = new Set(["Task", "Bash", "Edit", "Read", "Write", "mcp__context7__query-docs", "mcp__context7__resolve-library-id"]);
const keptRuns = 3;
const startLines = 20;
// A review GitHub dates up to this long before the start still counts: the two clocks may differ.
const clockSkewMs = 300_000;
const flushMs = 2_000;

function refuse(message, code = 1) {
  process.stderr.write(`review: refused. ${message} Nothing started and nothing was posted: fix what this names and run review again.\n`);
  process.exit(code);
}

// 1. Never inside a headless run; the arguments.
if ("MOONSHINE_HEADLESS" in process.env) refuse("It runs inside a headless review.");
const [pr, mode, ...extra] = process.argv.slice(2);
if (extra.length > 0 || !/^[1-9][0-9]{0,6}$/.test(pr ?? "") || !Object.hasOwn(budget, mode ?? "")) {
  process.stderr.write("usage: review <pr> standard|deep\n");
  process.exit(2);
}
// Tests shorten the limits (start, run, grace, in ms); a value can only lower them.
const [startMs, runMs, graceMs] = [120_000, minutes[mode] * 60_000, 10_000].map((limit, index) =>
  Math.min(limit, Number(process.env.MOONSHINE_REVIEW_TEST_TIMES?.split(",")[index]) || limit),
);

// The probes' environment for gh and git too: the launcher passes HOME and PATH only.
const user = userInfo().username;
const temp = spawnSync("/usr/bin/getconf", ["DARWIN_USER_TEMP_DIR"], { encoding: "utf8" }).stdout?.trim() || tmpdir();
Object.assign(process.env, { USER: user, LOGNAME: user, TMPDIR: temp });

// 2. The repository; 3. GitHub: the PR, CI, the round, one review per head.
const settings = config(refuse);
if (typeof settings.claude !== "string") refuse("claude was not found at install time; reinstall the guard (CLAUDE.md → Commands → Guard).");
// After the run, a failed read is the run's failure (verdict), not a refusal.
let onStop = refuse;
const stop = (message) => onStop(message);
const { top, git, isAncestor } = safeGit(stop);
const { api, pages } = gitHub(top, stop);
const login = api("user")?.login;
if (typeof login !== "string" || login === "") refuse("gh is not signed in.");
const info = api(`${repo}/pulls/${pr}`);
if (info?.state !== "open" || info.draft !== false) refuse("The PR is not open, or is a draft.");
if (info.base?.ref !== "main") refuse("The PR's base is not main.");
const headRepo = info.head?.repo?.full_name;
if (typeof headRepo !== "string" || headRepo !== info.base?.repo?.full_name || String(info.head?.ref).startsWith("fork/")) {
  refuse("The PR comes from a fork or a fork/ branch; the owner reviews it by hand.");
}
const head = info.head?.sha;
if (typeof head !== "string" || !/^[0-9a-f]{40}$/.test(head)) refuse("The PR has no head commit.");
ciGreen(api, pr, head, denyList(refuse), refuse);
const marked = pages(`${repo}/pulls/${pr}/reviews`)
  .filter((review) => review?.user?.login === login)
  .map((review) => reviewMarker(review.body, refuse))
  .filter((marker) => marker !== null);
if (marked.some((marker) => marker.head === head)) refuse("This head has a review already.");
const last = marked.reduce((best, marker) => (best === null || marker.round > best.round ? marker : best), null);
const round = (last?.round ?? 0) + 1;
if (round >= 3) refuse("Round 3 and later are the owner's; the owner starts them by hand.");
if (round === 2 && last.high === 0) refuse("Round 1 counted no High, so there is no round 2.");

// 4. main's instructions: main is an ancestor, and the PR changes none of them.
const main = api(`${repo}/branches/main`)?.commit?.sha;
if (typeof main !== "string" || !/^[0-9a-f]{40}$/.test(main)) refuse("GitHub named no commit for main.");
if (!isAncestor(main, head)) refuse("The PR is not up to date with main (or main or the head is not fetched): run git fetch origin.");
const changed = git(["diff-tree", "-r", "-z", "--no-renames", "--name-only", "--no-relative", main, head]).split("\0");
if (changed.some((path) => instructions.test(path.normalize("NFC")))) {
  refuse("The PR changes CLAUDE.md, CLAUDE.local.md, .claude/ or .mcp.json; the owner reviews it by hand.");
}

// 5. The checkout is exactly the head.
const unclean = checkoutClean(top, head);
if (unclean) refuse(`The checkout is not the PR's head as committed: ${unclean}.`);
git(["fsck", "--no-dangling", "--no-progress", head, main]);

// 6. The session and the lock.
const slug = top.replace(/[^A-Za-z0-9]/g, "-");
const root = settings.scratchRoots.find((path) => path.endsWith(`/${slug}`));
if (!root) refuse("This worktree has no scratchpad root; reinstall the guard (CLAUDE.md → Commands → Guard).");
const session = randomUUID();
const sessionDir = join(root, session);
const scratchpad = join(sessionDir, "scratchpad");
const lock = takeLock({ pr, head, session, top, sessionDir }, refuse, settings.claude);

// 7. The private folder: settings for this run, the MCP config, the logs.
const runs = join(process.env.HOME, "Library", "Caches", "moonshine-review");
mkdirSync(runs, { recursive: true, mode: 0o700 });
const runDir = mkdtempSync(join(runs, "run-"));
const runSettings = {
  permissions: {
    allow: [`Write(/${scratchpad}/**)`, `Edit(/${scratchpad}/**)`],
    deny: [
      "Bash(git push*)", "Bash(git * push*)", "Bash(*gh-post comment*)", "Bash(*gh-post merge*)", "Bash(*gh-post pr-*)",
      "Bash(*/bin/review*)", "Bash(claude*)", "Bash(*/claude *)", "Bash(git worktree prune*)", "WebFetch(domain:registry.npmjs.org)",
    ],
  },
  autoMemoryEnabled: false,
};
writeFileSync(join(runDir, "settings.json"), JSON.stringify(runSettings, null, 2));
writeFileSync(join(runDir, "mcp.json"), JSON.stringify({ mcpServers: { context7: { type: "http", url: "https://mcp.context7.com/mcp" } } }));
let plugins = [];
try {
  plugins = readFileSync(join(home, "review-plugins.txt"), "utf8").split(/\r?\n/).map((line) => line.trim()).filter((line) => line !== "");
} catch {
  // no file: no plugin is expected
}
const expectedPlugins = new Set(plugins);

// 8. claude, in an environment built from scratch.
const env = {
  HOME: process.env.HOME, USER: user, LOGNAME: user, TMPDIR: temp, LANG: "en_US.UTF-8", PATH: process.env.PATH,
  MOONSHINE_HEADLESS: "1", MOONSHINE_HEADLESS_PR: pr, ENABLE_CLAUDEAI_MCP_SERVERS: "false", GIT_NO_REPLACE_OBJECTS: "1",
  GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "core.fsmonitor", GIT_CONFIG_VALUE_0: "false",
};
const version = spawnSync(settings.claude, ["--version"], { env, encoding: "utf8" }).stdout?.trim().split("\n")[0] ?? "unknown";
const started = Date.now();
const child = spawn(
  settings.claude,
  [
    "-p", `/review-pr ${pr} ${mode} headless`, "--session-id", session, "--tools", ...tools,
    "--permission-mode", "default", "--permission-prompts", "none", "--settings", join(runDir, "settings.json"),
    "--strict-mcp-config", "--mcp-config", join(runDir, "mcp.json"), "--disallowedTools", `Bash(${join(home, "bin", "review")}:*)`,
    "--no-session-persistence", "--max-budget-usd", budget[mode], "--output-format", "stream-json", "--verbose",
  ],
  { cwd: top, env, detached: true, stdio: ["ignore", "pipe", "pipe"] },
);
child.on("error", () => finish(6, "claude could not be started"));
process.stdout.write(`review: round ${round}, ${mode}, claude ${version}; log ${runDir}\n`);
const errors = createWriteStream(join(runDir, "stderr.log"));
child.stderr.pipe(errors);
const stream = createWriteStream(join(runDir, "stream.jsonl"));

// 9. The stream: the gates on every start event, the last result, the limits, the signals.
const timers = [
  setTimeout(() => finish(7, "no start event in time"), startMs),
  setTimeout(() => finish(5, `the time limit of ${minutes[mode]} minutes`), runMs),
];
for (const name of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(name, () => finish(6, "stopped by a signal"));
if (child.pid && !lock.setChild(child.pid)) finish(6, "the lock could not record claude (ps failed, or another run took the lock)");
let lines = 0;
let starts = 0;
let result = null;
createInterface({ input: child.stdout, crlfDelay: Infinity }).on("line", (line) => {
  if (finish.done) return;
  stream.write(line + "\n");
  lines += 1;
  let event = null;
  try {
    event = JSON.parse(line);
  } catch {
    // not an event
  }
  if (event?.type === "system" && event.subtype === "init") {
    const why = gate(event);
    if (why) finish(7, why);
    starts += 1;
    clearTimeout(timers[0]);
  } else if (event?.type === "result") {
    result = event;
  }
  if (starts === 0 && lines >= startLines) finish(7, `no start event in the first ${startLines} lines`);
});
child.on("close", (code) => finish(...verdict(code)));

/// Why a start event stops the run, or null.
function gate(event) {
  if (event.session_id !== session) return "a start event names another session";
  if (event.apiKeySource !== "none") return "the run would bill an API key";
  if (!Array.isArray(event.mcp_servers) || event.mcp_servers.some((server) => server?.name !== "context7")) return "an MCP server other than context7";
  if (!Array.isArray(event.tools) || event.tools.some((tool) => !expectedTools.has(tool))) return "a tool outside the expected set";
  if (!Array.isArray(event.plugins) || event.plugins.some((plugin) => !expectedPlugins.has(plugin?.source))) return "a plugin not in review-plugins.txt";
  return null;
}

/// [exit, reason] once claude has exited: 0 only with exit 0, a last result of success, this
/// session's recorded review of this head on GitHub, and the checkout unchanged.
function verdict(code) {
  if (code !== 0) return [6, `claude exited with ${code}${result?.subtype ? ` (${result.subtype})` : ""}`];
  if (result?.subtype !== "success") return [6, `the last result is ${result?.subtype ?? "missing"}`];
  let failed = null;
  const fail = (message) => {
    failed = message;
    throw new Error(message);
  };
  onStop = fail;
  try {
    const recorded = readPosts(fail).filter((post) => post.kind === "review" && post.pr === Number(pr) && post.session === session);
    if (recorded.length !== 1) fail("no review, or more than one, is recorded from this run's session");
    const review = api(`${repo}/pulls/${pr}/reviews/${recorded[0].id}`);
    if (review?.user?.login !== login) fail("the recorded review is by another account");
    if (review.commit_id !== head) fail("the recorded review is on another commit");
    const marker = reviewMarker(review.body, fail);
    if (marker === null) fail("the recorded review has no counted marker");
    if (marker.head !== head) fail("the recorded review's marker names another head");
    if (!(Date.parse(review.submitted_at) >= started - clockSkewMs)) fail("the recorded review is older than the run");
  } catch {
    return [6, failed ?? "the review could not be checked"];
  }
  const after = checkoutClean(top, head);
  return after ? [6, `the checkout changed during the run: ${after}`] : [0, "reviewed and posted"];
}

/// Ends the run once: the child's process tree, this session's worktrees, the lock; then, once
/// the logs are written (at most `flushMs`), the folder.
function finish(code, reason) {
  if (finish.done) return;
  finish.done = true;
  timers.forEach(clearTimeout);
  killTree([child.pid], graceMs);
  const removed = removeWorktrees(top, sessionDir, pr);
  lock.release();
  const written = [stream, errors].map((log) => new Promise((resolve) => {
    if (log.closed) resolve();
    log.on("close", resolve).on("error", resolve);
  }));
  stream.end();
  const exit = () => {
    if (code === 0) {
      rmSync(runDir, { recursive: true, force: true });
    } else {
      const old = readdirSync(runs)
        .filter((name) => name.startsWith("run-"))
        .map((name) => ({ path: join(runs, name), time: statSync(join(runs, name)).mtimeMs }))
        .sort((a, b) => b.time - a.time);
      for (const { path } of old.slice(keptRuns)) rmSync(path, { recursive: true, force: true });
    }
    const where = code === 0 ? "" : `; log ${runDir}. Do not run review again: tell the owner`;
    process.stderr.write(`review: exit ${code}: ${reason}; ${removed} worktree(s) removed${where}\n`);
    process.exit(code);
  };
  Promise.all(written).then(exit);
  setTimeout(exit, flushMs);
}
