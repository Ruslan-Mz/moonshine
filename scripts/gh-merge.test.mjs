// Tests for gh-post merge (scripts/guard/merge.mjs) on throwaway repositories with a fake `gh`:
// node --test scripts/gh-merge.test.mjs
// The fake answers each `gh api --method GET <path>` from a JSON file, in GitHub's shapes, and
// records `gh pr merge`. Each test installs the guard into its own temporary HOME
// (scripts/guard-fixture.mjs). Every entry is invented.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { commit, denyListFile, environment, install, installed, ok, repository, secret } from "./guard-fixture.mjs";

const repo = "repos/{owner}/{repo}";
const login = "owner-login";

const fakeGh = `#!${process.execPath}
const { appendFileSync, readFileSync } = require("node:fs");
const args = process.argv.slice(2);
const fake = JSON.parse(readFileSync(process.env.FAKE_GH, "utf8"));
if (args.length === 4 && args[0] === "api" && args[1] === "--method" && args[2] === "GET") {
  if (!Object.hasOwn(fake.api, args[3])) {
    process.stderr.write("gh: Not Found (HTTP 404)\\n");
    process.exit(1);
  }
  process.stdout.write(JSON.stringify(fake.api[args[3]]));
  process.exit(0);
}
if (args[0] === "pr" && args[1] === "merge") {
  appendFileSync(process.env.FAKE_GH_LOG, args.join(" ") + "\\n");
  process.exit(fake.mergeStatus);
}
process.stderr.write("fake gh: unexpected call\\n");
process.exit(3);
`;

function marker(round, head, counts = {}) {
  const { high = 0, medium = 0, low = 0, owner = 0 } = counts;
  return `<!-- moonshine-review round=${round} head=${head} high=${high} medium=${medium} low=${low} owner=${owner} -->`;
}

/// A repository whose branch `slice/one` adds a method-log row on top of `main`, PR 7 in the fake
/// GitHub, a clean round-1 review by the owner's account from session-b, and the state lines of
/// the PR's creation (session-a) and the review.
function setUp() {
  const work = repository();
  work.env = { MOONSHINE_SCRATCH_BASE: join(work.root, "scratch") };
  const installedResult = install(work, [denyListFile(work, `${secret}\nmirelbrook\n`)]);
  assert.equal(installedResult.status, 0, installedResult.stderr);
  const main = ok(work, "rev-parse", "main").trim();
  ok(work, "switch", "-q", "-c", "slice/one");
  commit(work, "docs/method/log/2026-11.md", "| a row |\n", "a log row");
  const bin = join(work.root, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), fakeGh, { mode: 0o755 });
  const context = { work, main, bin, posts: [], log: join(work.root, "gh.log"), fakePath: join(work.root, "fake.json") };
  context.head = () => ok(work, "rev-parse", "HEAD").trim();
  context.commit = (path, text, message = "more") => {
    commit(work, path, text, message);
    return context.publish();
  };
  /// Points origin/pr/7 and the fake PR at HEAD.
  context.publish = () => {
    const head = context.head();
    ok(work, "update-ref", "refs/remotes/origin/pr/7", head);
    context.fake.api[`${repo}/pulls/7`].head.sha = head;
    context.setChecks(head);
    return head;
  };
  context.setChecks = (head, runs = ["docs", "swift", "core-linux", "guard"].map((name) => checkRun(name))) => {
    const forThisPR = runs.map((run) => ({ head_sha: head, pull_requests: [{ number: 7 }], ...run }));
    context.fake.api[`${repo}/commits/${head}/check-runs?filter=latest&per_page=100`] = {
      total_count: forThisPR.length,
      check_runs: forThisPR,
    };
    context.fake.api[`${repo}/commits/${head}/status`] = { state: "pending", total_count: 0, statuses: [] };
  };
  context.record = (kind, pr, id, session) => context.posts.push({ kind, pr, id, session, time: "2026-11-11T09:00:00.000Z" });
  context.review = (id, body, overrides = {}) => ({
    id,
    user: { login },
    body,
    state: "COMMENTED",
    commit_id: context.head(),
    submitted_at: "2026-11-11T10:00:00Z",
    ...overrides,
  });
  context.setReviews = (reviews) => {
    context.fake.api[`${repo}/pulls/7/reviews?per_page=100&page=1`] = reviews;
    for (const review of reviews) {
      const key = `${repo}/pulls/7/reviews/${review.id}/comments?per_page=100&page=1`;
      if (!Object.hasOwn(context.fake.api, key)) context.fake.api[key] = [];
    }
  };
  context.fake = {
    mergeStatus: 0,
    api: {
      user: { login },
      [`${repo}/pulls/7`]: {
        number: 7,
        state: "open",
        draft: false,
        title: "S9: a log row",
        body: "Class: plain\n\nA row.\n",
        user: { login },
        base: { ref: "main", repo: { full_name: "o/r" } },
        head: { ref: "slice/one", sha: "", repo: { full_name: "o/r" } },
      },
      [`${repo}/branches/main`]: { name: "main", commit: { sha: main } },
      [`${repo}/issues/7/comments?per_page=100&page=1`]: [],
    },
  };
  const head = context.publish();
  context.record("pr-create", 7, 7, "session-a");
  context.record("review", 7, 901, "session-b");
  context.setReviews([context.review(901, `**No findings**\n\n${marker(1, head)}\n`)]);
  context.run = (cwd = work.cwd) => {
    writeFileSync(context.fakePath, JSON.stringify(context.fake));
    const state = installed(work, "state", "posts.jsonl");
    writeFileSync(state, context.posts.map((post) => JSON.stringify(post)).join("\n") + (context.posts.length ? "\n" : ""));
    if (context.extraState) appendFileSync(state, context.extraState);
    return spawnSync(installed(work, "bin", "gh-post"), ["merge", "7"], {
      cwd,
      env: environment(work.home, { PATH: `${bin}:${process.env.PATH}`, FAKE_GH: context.fakePath, FAKE_GH_LOG: context.log }),
      encoding: "utf8",
    });
  };
  context.merged = () => (existsSync(context.log) ? readFileSync(context.log, "utf8") : null);
  return context;
}

let checkRunId = 0;
function checkRun(name, status = "completed", conclusion = "success") {
  checkRunId += 1;
  return { id: checkRunId, name, status, conclusion: status === "completed" ? conclusion : null };
}

function merges(context, cwd) {
  const result = context.run(cwd);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(context.merged(), `pr merge 7 --merge --match-head-commit ${context.head()}\n`);
}

function refused(context, ...expected) {
  const result = context.run();
  assert.equal(result.status, 1, `expected a refusal:\n${result.stdout}\n${result.stderr}`);
  assert.match(result.stderr, /gh-post: refused/);
  for (const text of expected) assert.ok(result.stderr.includes(text), `missing "${text}" in:\n${result.stderr}`);
  for (const leak of ["quolltail", "mirelbrook"]) {
    assert.ok(!result.stderr.toLowerCase().includes(leak), `the matched text must not be printed:\n${result.stderr}`);
  }
  assert.equal(context.merged(), null, "nothing may be merged");
}

const pr = (context) => context.fake.api[`${repo}/pulls/7`];

test("a plain PR with green checks and a clean review merges once, pinned to its head", () => {
  merges(setUp());
});

test("it merges when run from a subfolder", () => {
  const context = setUp();
  mkdirSync(join(context.work.cwd, "docs"), { recursive: true });
  merges(context, join(context.work.cwd, "docs"));
});

test("swift and core-linux skipped pass", () => {
  const context = setUp();
  context.setChecks(context.head(), [
    checkRun("docs"),
    checkRun("guard"),
    checkRun("swift", "completed", "skipped"),
    checkRun("core-linux", "completed", "skipped"),
  ]);
  merges(context);
});

test("a body with CRLF line ends still names its class", () => {
  const context = setUp();
  pr(context).body = "Class: plain\r\n\r\nA row.\r\n";
  merges(context);
});

test("a merge GitHub refuses (the head moved) exits 1", () => {
  const context = setUp();
  context.fake.mergeStatus = 1;
  const result = context.run();
  assert.equal(result.status, 1);
});

for (const [name, change, expected] of [
  ["a fork's head", (p) => (p.head.repo.full_name = "x/r"), "fork"],
  ["a fork/ branch", (p) => (p.head.ref = "fork/7-x"), "fork"],
  ["a draft", (p) => (p.draft = true), "draft"],
  ["a closed PR", (p) => (p.state = "closed"), "not open"],
  ["another base", (p) => (p.base.ref = "release"), "base"],
  ["another author", (p) => (p.user.login = "someone-else"), "not opened by"],
  ["no Class line", (p) => (p.body = "A row.\n"), "Class"],
  ["two Class lines", (p) => (p.body = "Class: plain\nClass: plain\n"), "Class"],
  ["Class: risky", (p) => (p.body = "Class: risky\n"), "risky"],
  ["a matching title", (p) => (p.title = `about ${secret}`), "guard"],
  ["a matching body", (p) => (p.body = `Class: plain\nby ${secret}\n`), "guard"],
]) {
  test(`the PR is refused: ${name}`, () => {
    const context = setUp();
    change(pr(context));
    refused(context, expected);
  });
}

test("a stale origin/pr/<n> is refused with the fetch to run", () => {
  const context = setUp();
  ok(context.work, "update-ref", "refs/remotes/origin/pr/7", context.main);
  refused(context, "git fetch origin");
});

test("a PR behind main is refused", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "main");
  commit(context.work, "README.md", "moved\n", "main moved");
  context.fake.api[`${repo}/branches/main`].commit.sha = context.head();
  ok(context.work, "switch", "-q", "slice/one");
  refused(context, "not up to date with main");
});

test("a change outside the plain list is computed risky, whatever the body says", () => {
  const context = setUp();
  const head = context.commit("Adapters/Sources/X.swift", "let a = 1\n");
  context.setReviews([context.review(901, marker(1, head))]);
  refused(context, "computed: risky", "Adapters/Sources/X.swift");
});

test("a deny-list line in an added line is refused by the local scan", () => {
  const context = setUp();
  const head = context.commit("docs/method/log/2026-11.md", `| a row by ${secret} |\n`);
  context.setReviews([context.review(901, marker(1, head))]);
  refused(context, "guard");
});

for (const [name, runs, expected] of [
  ["a check still running", [checkRun("docs"), checkRun("swift", "in_progress"), checkRun("core-linux"), checkRun("guard")], "still running"],
  ["a failed docs", [checkRun("docs", "completed", "failure"), checkRun("swift"), checkRun("core-linux"), checkRun("guard")], "docs"],
  ["a skipped guard", [checkRun("docs"), checkRun("swift"), checkRun("core-linux"), checkRun("guard", "completed", "skipped")], "guard"],
  ["a missing core-linux", [checkRun("docs"), checkRun("swift"), checkRun("guard")], "core-linux"],
  ["another check that failed", [...["docs", "swift", "core-linux", "guard"].map((n) => checkRun(n)), checkRun("lint", "completed", "failure")], "lint"],
]) {
  test(`CI is refused: ${name}`, () => {
    const context = setUp();
    context.setChecks(context.head(), runs);
    refused(context, expected);
  });
}

test("more check runs than one page is refused", () => {
  const context = setUp();
  context.setChecks(context.head());
  context.fake.api[`${repo}/commits/${context.head()}/check-runs?filter=latest&per_page=100`].total_count = 101;
  refused(context, "check runs");
});

test("a failed commit status is refused; a successful one passes", () => {
  const context = setUp();
  context.fake.api[`${repo}/commits/${context.head()}/status`] = { state: "failure", total_count: 1, statuses: [{ state: "failure" }] };
  refused(context, "status");
  context.fake.api[`${repo}/commits/${context.head()}/status`] = { state: "success", total_count: 1, statuses: [{ state: "success" }] };
  merges(context);
});

test("no recorded review is refused", () => {
  const context = setUp();
  context.posts = context.posts.filter((post) => post.kind !== "review");
  refused(context, "no review");
});

test("an unrecorded marker review by the owner's account at the same round or later is refused", () => {
  const context = setUp();
  const head = context.head();
  context.setReviews([
    context.review(901, marker(1, head)),
    context.review(950, marker(2, head, { high: 1 }), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "not recorded");
});

test("a marker review by another account is ignored", () => {
  const context = setUp();
  const head = context.head();
  context.setReviews([
    context.review(901, marker(1, head)),
    context.review(960, marker(2, head, { high: 1 }), { user: { login: "stranger" }, submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  merges(context);
});

for (const [name, body, expected] of [
  ["a marker without counts", (head) => `<!-- moonshine-review round=1 head=${head} -->`, "counts"],
  ["a count that is not a whole number", (head) => marker(1, head).replace("high=0", "high=0.5"), "counts"],
  ["two markers", (head) => `${marker(1, head)}\n${marker(1, head)}`, "more than one marker"],
  ["a High", (head) => marker(1, head, { high: 1 }), "High"],
  ["Changes required", (head) => `**Changes required**\n${marker(1, head)}`, "Changes required"],
]) {
  test(`the review is refused: ${name}`, () => {
    const context = setUp();
    context.setReviews([context.review(901, body(context.head()))]);
    refused(context, expected);
  });
}

test("an owner finding in an earlier round is refused, though the last round is clean", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.record("comment", 7, 990, "session-a");
  context.setReviews([
    context.review(901, marker(1, head, { low: 1, owner: 1 })),
    context.review(902, marker(2, head), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "owner");
});

test("a review whose head is not the commit it was posted on is refused", () => {
  const context = setUp();
  context.setReviews([context.review(901, marker(1, context.main))]);
  refused(context, "head");
});

test("a review on a commit that is not an ancestor of the head is refused", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "-c", "other", "main");
  commit(context.work, "docs/method/log/2026-11.md", "| other |\n", "other");
  const other = context.head();
  ok(context.work, "switch", "-q", "slice/one");
  context.setReviews([context.review(901, marker(1, other), { commit_id: other })]);
  refused(context, "ancestor");
});

test("an inline High comment is refused", () => {
  const context = setUp();
  context.fake.api[`${repo}/pulls/7/reviews/901/comments?per_page=100&page=1`] = [
    { id: 1, body: "**High · correctness · decision: author** — something" },
  ];
  refused(context, "inline");
});

test("an inline owner decision is refused", () => {
  const context = setUp();
  context.fake.api[`${repo}/pulls/7/reviews/901/comments?per_page=100&page=1`] = [
    { id: 1, body: "**Low · docs · decision: owner** — something" },
  ];
  refused(context, "inline");
});

test("inline comments are read past the first page", () => {
  const context = setUp();
  const page = Array.from({ length: 100 }, (_, id) => ({ id, body: "**Low · docs · decision: author** — x" }));
  context.fake.api[`${repo}/pulls/7/reviews/901/comments?per_page=100&page=1`] = page;
  context.fake.api[`${repo}/pulls/7/reviews/901/comments?per_page=100&page=2`] = [{ id: 200, body: "**High · x · decision: author** — y" }];
  refused(context, "inline");
});

test("changes requested by anyone is refused", () => {
  const context = setUp();
  context.setReviews([
    context.review(901, marker(1, context.head())),
    context.review(970, "please wait", { user: { login: "stranger" }, state: "CHANGES_REQUESTED" }),
  ]);
  refused(context, "changes requested");
});

test("a review from the session that created the PR is refused", () => {
  const context = setUp();
  context.posts = context.posts.map((post) => (post.kind === "review" ? { ...post, session: "session-a" } : post));
  refused(context, "session");
});

test("a PR with no recorded creation is refused", () => {
  const context = setUp();
  context.posts = context.posts.filter((post) => post.kind !== "pr-create");
  refused(context, "created");
});

test("a state line that cannot be read is refused", () => {
  const context = setUp();
  context.extraState = "{ not json\n";
  refused(context, "state file");
});

/// Round 1 with one Low finding, and the answer comment `comment` (recorded with `session`).
function withFinding(context, comment, session) {
  context.setReviews([context.review(901, marker(1, context.head(), { low: 1 }))]);
  if (comment) {
    context.fake.api[`${repo}/issues/7/comments?per_page=100&page=1`] = [comment];
    context.record("comment", 7, comment.id, session);
  }
}

test("findings with the answer comment from another session merge", () => {
  const context = setUp();
  withFinding(context, { id: 990, user: { login }, created_at: "2026-11-11T11:00:00Z" }, "session-a");
  merges(context);
});

for (const [name, comment, session] of [
  ["no answer", null, null],
  ["an answer before the review", { id: 990, user: { login }, created_at: "2026-11-11T09:30:00Z" }, "session-a"],
  ["an answer from the review's session", { id: 990, user: { login }, created_at: "2026-11-11T11:00:00Z" }, "session-b"],
  ["an answer by another account", { id: 990, user: { login: "stranger" }, created_at: "2026-11-11T11:00:00Z" }, "session-a"],
]) {
  test(`findings are refused with ${name}`, () => {
    const context = setUp();
    withFinding(context, comment, session);
    refused(context, "answer");
  });
}

test("a small push after the review merges", () => {
  const context = setUp();
  context.commit("docs/method/log/2026-11.md", "| a row |\n| a fix |\n");
  merges(context);
});

test("more than 100 lines pushed after the review are refused", () => {
  const context = setUp();
  const text = Array.from({ length: 101 }, (_, n) => `| row ${n} |`).join("\n") + "\n";
  context.commit("docs/method/log/2026-11.md", text);
  refused(context, "after the last review");
});

test("a risky token pushed after the review is refused", () => {
  const context = setUp();
  context.commit("Apps/Mac/Sources/Today/Probe.swift", "Task { }\n");
  refused(context, "computed: risky", "concurrency");
});

test("exactly 100 lines pushed after the review merge; 101 are refused", () => {
  const rows = (count) => "| a row |\n" + Array.from({ length: count }, (_, n) => `| row ${n} |\n`).join("");
  const context = setUp();
  context.commit("docs/method/log/2026-11.md", rows(100));
  merges(context);
  const over = setUp();
  over.commit("docs/method/log/2026-11.md", rows(101));
  refused(over, "after the last review");
});

test("main's own lines merged into the branch after the review do not count", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "main");
  commit(context.work, "README.md", Array.from({ length: 150 }, (_, n) => `line ${n}\n`).join(""), "main moved");
  context.fake.api[`${repo}/branches/main`].commit.sha = context.head();
  ok(context.work, "switch", "-q", "slice/one");
  ok(context.work, "merge", "-q", "--no-edit", "main");
  context.publish();
  merges(context);
});

test("the PR's own lines after the review count, though main was merged in too", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "main");
  commit(context.work, "README.md", "moved\n", "main moved");
  context.fake.api[`${repo}/branches/main`].commit.sha = context.head();
  ok(context.work, "switch", "-q", "slice/one");
  ok(context.work, "merge", "-q", "--no-edit", "main");
  context.commit("docs/method/log/2026-11.md", "| a row |\n" + Array.from({ length: 101 }, (_, n) => `| row ${n} |\n`).join(""));
  refused(context, "after the last review");
});

test("a replace ref does not change the commit that is judged", () => {
  const context = setUp();
  const before = context.head();
  const risky = context.commit("Adapters/Sources/X.swift", "let a = 1\n");
  const tree = ok(context.work, "rev-parse", `${before}^{tree}`).trim();
  const benign = ok(context.work, "commit-tree", tree, "-p", before, "-m", "benign").trim();
  ok(context.work, "replace", risky, benign);
  context.setReviews([context.review(901, marker(1, risky))]);
  refused(context, "computed: risky", "Adapters/Sources/X.swift");
});

test("a checkout with grafts is refused", () => {
  const context = setUp();
  const grafts = ok(context.work, "rev-parse", "--path-format=absolute", "--git-path", "info/grafts").trim();
  mkdirSync(join(grafts, ".."), { recursive: true });
  writeFileSync(grafts, "");
  refused(context, "grafts");
});

test("the newest run of a check counts: a passed guard after a failed one merges", () => {
  const context = setUp();
  const others = ["docs", "swift", "core-linux"].map((name) => checkRun(name));
  context.setChecks(context.head(), [checkRun("guard", "completed", "failure"), ...others, checkRun("guard")]);
  merges(context);
});

test("the newest run of a check counts: a failed guard after a passed one is refused", () => {
  const context = setUp();
  const others = ["docs", "swift", "core-linux"].map((name) => checkRun(name));
  context.setChecks(context.head(), [checkRun("guard"), ...others, checkRun("guard", "completed", "failure")]);
  refused(context, "guard");
});

test("a matching branch name is refused", () => {
  const context = setUp();
  pr(context).head.ref = `slice/${secret}`;
  refused(context, "the branch name");
});

test("a deny-listed word in a risky path is not printed", () => {
  const context = setUp();
  const head = context.commit("Adapters/Sources/Mirelbrook.swift", "let a = 1\n");
  context.setReviews([context.review(901, marker(1, head))]);
  refused(context, "computed: risky");
});

test("a review recorded for another PR does not count", () => {
  const context = setUp();
  context.posts = context.posts.map((post) => (post.kind === "review" ? { ...post, pr: 8 } : post));
  refused(context, "no review");
});

test("the highest round is the last: a clean round 1 and a round 2 with a High are refused", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.record("comment", 7, 990, "session-a");
  context.fake.api[`${repo}/issues/7/comments?per_page=100&page=1`] = [{ id: 990, user: { login }, created_at: "2026-11-11T13:00:00Z" }];
  context.setReviews([
    context.review(901, marker(1, head)),
    context.review(902, marker(2, head, { high: 1 }), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "High");
});

test("the highest round is the last: a round 1 with a High, answered, and a clean round 2 merge", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.record("comment", 7, 990, "session-a");
  context.fake.api[`${repo}/issues/7/comments?per_page=100&page=1`] = [{ id: 990, user: { login }, created_at: "2026-11-11T11:00:00Z" }];
  context.setReviews([
    context.review(902, marker(2, head), { submitted_at: "2026-11-11T12:00:00Z" }),
    context.review(901, marker(1, head, { high: 1 })),
  ]);
  merges(context);
});

test("within one round the later review is the last", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.setReviews([
    context.review(902, marker(1, head, { high: 1 }), { submitted_at: "2026-11-11T12:00:00Z" }),
    context.review(901, marker(1, head)),
  ]);
  refused(context, "High");
});

test("an unrecorded marker review at the same round, after the recorded one, is refused", () => {
  const context = setUp();
  const head = context.head();
  context.setReviews([
    context.review(901, marker(1, head)),
    context.review(950, marker(1, head, { high: 1 }), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "not recorded");
});

test("an owner finding in an unrecorded earlier round is refused", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.setReviews([
    context.review(950, marker(1, head, { owner: 1 })),
    context.review(902, marker(2, head), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "owner");
});

test("an earlier round with findings and no answer is refused, though the last round is clean", () => {
  const context = setUp();
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.setReviews([
    context.review(901, marker(1, head, { high: 1, medium: 2 })),
    context.review(902, marker(2, head), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  refused(context, "answer");
});

test("an answer comment missing from the state file does not count", () => {
  const context = setUp();
  withFinding(context, null, null);
  context.fake.api[`${repo}/issues/7/comments?per_page=100&page=1`] = [{ id: 990, user: { login }, created_at: "2026-11-11T11:00:00Z" }];
  refused(context, "answer");
});

test("a shallow checkout is refused", () => {
  const context = setUp();
  const shallow = ok(context.work, "rev-parse", "--path-format=absolute", "--git-path", "shallow").trim();
  writeFileSync(shallow, `${context.main}\n`);
  refused(context, "shallow");
});

test("a check run without an id is refused", () => {
  const context = setUp();
  const runs = ["docs", "swift", "core-linux", "guard"].map((name) => checkRun(name));
  delete runs[0].id;
  context.setChecks(context.head(), runs);
  refused(context, "no id");
});

for (const name of [undefined, ""]) {
  test(`a check run without a name is refused (${JSON.stringify(name)})`, () => {
    const context = setUp();
    const runs = ["docs", "swift", "core-linux", "guard"].map((check) => checkRun(check));
    context.setChecks(context.head(), [{ ...checkRun("x", "completed", "failure"), name }, ...runs]);
    refused(context, "no name");
  });
}

test("a passed run for another PR on the same head does not hide this PR's failed one", () => {
  const context = setUp();
  const others = ["docs", "swift", "core-linux"].map((name) => checkRun(name));
  context.setChecks(context.head(), [
    checkRun("guard", "completed", "failure"),
    ...others,
    { ...checkRun("guard"), pull_requests: [{ number: 8 }] },
  ]);
  refused(context, "guard");
});

test("a run on another head does not count", () => {
  const context = setUp();
  const others = ["docs", "swift", "core-linux"].map((name) => checkRun(name));
  context.setChecks(context.head(), [{ ...checkRun("guard"), head_sha: context.main }, ...others]);
  refused(context, "guard has not run");
});

test("a reviewed commit that does not merge cleanly with main is refused", () => {
  const context = setUp();
  ok(context.work, "switch", "-q", "main");
  commit(context.work, "docs/method/log/2026-11.md", "| main's row |\n", "main moved");
  context.fake.api[`${repo}/branches/main`].commit.sha = context.head();
  ok(context.work, "switch", "-q", "slice/one");
  ok(context.work, "merge", "-q", "--no-edit", "-X", "ours", "main");
  context.publish();
  refused(context, "merge cleanly");
});

/// Round 1 (10:00) and round 2 (12:00), both with findings, recorded from session-b and session-c,
/// and the answer comments at `times`, recorded from session-a.
function twoRoundsWithFindings(context, times) {
  const head = context.head();
  context.record("review", 7, 902, "session-c");
  context.setReviews([
    context.review(901, marker(1, head, { high: 1, medium: 2 })),
    context.review(902, marker(2, head, { low: 1 }), { submitted_at: "2026-11-11T12:00:00Z" }),
  ]);
  const comments = times.map((at, index) => ({ id: 990 + index, user: { login }, created_at: `2026-11-11T${at}:00Z` }));
  context.fake.api[`${repo}/issues/7/comments?per_page=100&page=1`] = comments;
  for (const comment of comments) context.record("comment", 7, comment.id, "session-a");
}

test("each round with findings answered before the next round merges", () => {
  const context = setUp();
  twoRoundsWithFindings(context, ["11:00", "13:00"]);
  merges(context);
});

test("one answer after the last round does not answer an earlier round", () => {
  const context = setUp();
  twoRoundsWithFindings(context, ["13:00"]);
  refused(context, "answer");
});

test("one answer between the rounds does not answer the last round", () => {
  const context = setUp();
  twoRoundsWithFindings(context, ["11:00"]);
  refused(context, "answer");
});
