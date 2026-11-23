// review <pr> standard|deep: the author session starts /review-pr as a separate headless claude
// process (P-HR; CLAUDE.md → "Pull requests"). The installed bin/review runs this file in a cleared
// environment, after refusing inside a headless run. It refuses unless the checkout, the PR and CI
// are as the review needs them, takes the review lock, runs claude with private settings, a fixed
// tool set and Context7 as the only MCP server, checks every start event, and decides from the last
// result and the recorded review. It prints the exit reason and the log folder, never review text.
// Exits: 0 reviewed and posted · 1 refused · 2 usage · 5 time limit · 6 the run failed · 7 a start
// gate. A refusal (1) started nothing: the author may fix what it names and run review again, except
// the two only the owner clears, which say so; after a start (5, 6, 7) it is never retried (owner,
// 2026-11-17, PR #63 round 1): from claude's start until a posted review the head is recorded in the
// state folder, and review refuses it until the owner runs bin/review-allow-retry (P-AM2, owner
// 2026-11-20). Round 2 follows a round 1 with a High, or with owner findings on a plain PR whose
// answer carries the owner decisions block and whose decisions file exists (P-AM2). On macOS claude
// runs under caffeinate -i, and a stopped run's reason names a sleep.
// Tests: node --test scripts/review-headless.test.mjs
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createWriteStream, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir, userInfo } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { ciGreen, decisionsFile, decisionsFileExists, gitHub, hasMarker, ownerDecisions, repo, reviewMarker, safeGit } from "./github.mjs";
import { config, denyList } from "./matcher.mjs";
import { readPosts } from "./merge.mjs";
import { instructions } from "./plain-rules.mjs";
import { checkoutClean, killTree, removeWorktrees, sleepWatch, stoppedPath, takeLock } from "./review-lock.mjs";

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
const caffeinate = "/usr/bin/caffeinate";
// A sleep longer than this is named in a stopped run's reason.
const sleepNamedMs = 60_000;

function refuse(message, code = 1) {
  process.stderr.write(`review: refused. ${message} Nothing started and nothing was posted: fix what this names and run review again.\n`);
  process.exit(code);
}

/// A refusal no fix of the author's clears (PR #67 round 1): a new head must not route around it.
function refuseOwner(message) {
  process.stderr.write(`review: refused. ${message} Nothing started and nothing was posted: only the owner can clear this; ask the owner.\n`);
  process.exit(1);
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
const reviews = pages(`${repo}/pulls/${pr}/reviews`);
// /review-pr reads the round and round 2's diff from the markers of all reviews (P-AM2).
if (reviews.some((review) => review?.user?.login !== login && hasMarker(review?.body))) {
  refuse("Another account posted a review marker on this PR; the owner reviews it by hand.");
}
const marked = reviews
  .filter((review) => review?.user?.login === login)
  .map((review) => ({ review, marker: reviewMarker(review.body, refuse) }))
  .filter(({ marker }) => marker !== null);
if (marked.some(({ marker }) => marker.head === head)) refuse("This head has a review already.");
const last = marked.reduce((best, item) => (best === null || item.marker.round > best.marker.round ? item : best), null)?.marker;
const round = (last?.round ?? 0) + 1;
if (round >= 3) refuse("Round 3 and later are the owner's; the owner starts them by hand.");
if (round === 2) {
  // After a High, or after owner findings on a plain PR, whose decisions are answered (P-AM2).
  const plain = (typeof info.body === "string" ? info.body : "").replace(/\r/g, "").split("\n").filter((line) => /^\s*class\s*:/i.test(line));
  if (!(last.high > 0 || (last.owner > 0 && plain.length === 1 && plain[0] === "Class: plain"))) {
    refuse("Round 1 counted no High, and no owner finding on a plain PR, so there is no round 2.");
  }
  if (!isAncestor(last.head, head)) refuse("Round 1's head is not an ancestor of this head (the branch was rewritten, or it is not fetched: run git fetch origin).");
  if (last.owner > 0) {
    const submitted = Date.parse(marked.find(({ marker }) => marker === last).review.submitted_at);
    const answered = pages(`${repo}/issues/${pr}/comments`).some(
      (comment) => comment?.user?.login === login && Date.parse(comment.created_at) > submitted && ownerDecisions(comment.body, last.owner, pr, 1),
    );
    if (!answered) refuse(`Round 1's owner findings have no answer with the owner decisions block (Owner decisions: ${decisionsFile(pr, 1)}, one line per finding).`);
    if (!decisionsFileExists(top, pr, 1)) refuseOwner(`The owner's decisions file ${decisionsFile(pr, 1)} is not in the checkout; the owner writes it.`);
  }
}

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
// Under the lock (PR #67 round 1), so a run that stopped while this one waited for it counts.
if (existsSync(stoppedPath(pr, head))) {
  lock.release();
  refuseOwner(`A run on this head started and posted no review; the owner allows another with ${join(home, "bin", "review-allow-retry")} ${pr}.`);
}

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
const args = [
  "-p", `/review-pr ${pr} ${mode} headless`, "--session-id", session, "--tools", ...tools,
  "--permission-mode", "default", "--permission-prompts", "none", "--settings", join(runDir, "settings.json"),
  "--strict-mcp-config", "--mcp-config", join(runDir, "mcp.json"), "--disallowedTools", `Bash(${join(home, "bin", "review")}:*)`,
  "--no-session-persistence", "--max-budget-usd", budget[mode], "--output-format", "stream-json", "--verbose",
];
// Idle sleep cannot cut the run on macOS (owner, 2026-11-20); a closed lid still does.
const awake = existsSync(caffeinate);
const child = spawn(awake ? caffeinate : settings.claude, awake ? ["-i", settings.claude, ...args] : args, {
  cwd: top, env, detached: true, stdio: ["ignore", "pipe", "pipe"],
});
// From claude's start the head is recorded, and only a posted review removes the record (owner,
// 2026-11-20; PR #67 round 1): a failure before the spawn blocks nothing, and a wrapper killed
// before finish() still leaves it.
let recorded = false;
if (child.pid) {
  try {
    writeFileSync(stoppedPath(pr, head), JSON.stringify({ pr, head, code: null, time: new Date().toISOString() }), { mode: 0o600 });
    recorded = true;
  } catch {
    // finish(6) below
  }
}
// Tests move the wall clock on by this many ms after the start, as a sleep would.
const testSleptMs = Number(process.env.MOONSHINE_REVIEW_TEST_SLEPT_MS) || 0;
let wallReads = 0;
const sleep = sleepWatch(undefined, () => Date.now() + (wallReads++ === 0 ? 0 : testSleptMs));
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
if (child.pid && !recorded) finish(6, "the run could not be recorded in the state folder");
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
  const slept = sleep.slept();
  sleep.stop();
  if (code !== 0 && slept > sleepNamedMs) reason += `; the Mac slept about ${Math.round(slept / 60_000)} min during the run`;
  killTree([child.pid], graceMs);
  const removed = removeWorktrees(top, sessionDir, pr);
  // A posted review clears the record; a stop adds its exit to it, and the record written at the
  // start stays if that fails.
  try {
    if (code === 0) rmSync(stoppedPath(pr, head), { force: true });
    else if (recorded) writeFileSync(stoppedPath(pr, head), JSON.stringify({ pr, head, code, time: new Date().toISOString() }), { mode: 0o600 });
  } catch {
    // the record written at the start stays
  }
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
    const where = code === 0 ? "" : `; log ${runDir}. Do not run review again: tell the owner${child.pid && !recorded ? " (the stop could not be recorded)" : ""}`;
    process.stderr.write(`review: exit ${code}: ${reason}; ${removed} worktree(s) removed${where}\n`);
    process.exit(code);
  };
  Promise.all(written).then(exit);
  setTimeout(exit, flushMs);
}
