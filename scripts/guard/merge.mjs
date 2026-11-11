// gh-post merge <pr>: the author session merges a plain pull request (CLAUDE.md → "Pull requests"),
// or is refused, and the owner merges it. It refuses whatever it cannot prove from GitHub's answers,
// the local commits and the state file:
//   1. the PR: open, not a draft, into main, from this repository (no fork, no fork/ branch), opened
//      by the account gh is signed in as;
//   2. the commits: origin/pr/<n> is the PR's head, and main is an ancestor of it;
//   3. the class: the body's one `Class: plain` line, and plain-rules.mjs on the diff from main;
//   4. CI: docs and guard succeeded, swift and core-linux succeeded or were skipped, every other
//      check completed and succeeded, was skipped or neutral, and the commit status is not failed;
//   5. the guard, again: commit-scan.mjs over the new commits, the title, the body, the branch name;
//   6. the review: the last round by the same account, recorded by gh-post review in a session other
//      than the one that created the PR, with the counted marker of /review-pr and no High; no
//      round with an owner finding; no unrecorded marker review at that round or later; no inline
//      High or owner decision; nobody's changes requested; at most 100 lines changed since;
//   7. with findings, the answer comment: recorded, later than the review, from another session.
// Then `gh pr merge <n> --merge --match-head-commit <head>`, once. A refusal names the check, never
// PR text. The state file records each sent comment, review and PR (kind, PR, id, session, time).
// It and the session id guard against mistakes, not against a session set on getting around them:
// test code runs outside the sandbox and can write the state file.
// Tests: node --test scripts/gh-merge.test.mjs
import { spawnSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { binaryAllowlist, scan } from "./commit-scan.mjs";
import { denyList, match, printable } from "./matcher.mjs";
import { changedLines, classify, readChanges } from "./plain-rules.mjs";

const guardFolder = dirname(fileURLToPath(import.meta.url));
const postsFile = join(guardFolder, "..", "state", "posts.jsonl");
const repo = "repos/{owner}/{repo}";
const kinds = new Set(["pr-create", "review", "comment"]);
/// The conclusions each required check may have.
const required = { docs: ["success"], guard: ["success"], swift: ["success", "skipped"], "core-linux": ["success", "skipped"] };
const otherConclusions = ["success", "skipped", "neutral"];
const maxPages = 10;
const maxCommits = 2000;
const maxUnreviewed = 100;
const reportLimit = 10;
const anyMarker = /<!--\s*moonshine-review\b/g;
const countedMarker =
  /<!-- moonshine-review round=([1-9][0-9]{0,3}) head=([0-9a-f]{40}) high=([0-9]{1,4}) medium=([0-9]{1,4}) low=([0-9]{1,4}) owner=([0-9]{1,4}) -->/;

/// Appends one line for a sent post; false when it cannot be written.
export function recordPost(kind, pr, id, session) {
  try {
    appendFileSync(postsFile, JSON.stringify({ kind, pr, id, session, time: new Date().toISOString() }) + "\n");
    return true;
  } catch {
    return false;
  }
}

/// The recorded posts; none when the file does not exist yet. A line that cannot be read stops.
function readPosts(stop) {
  let text;
  try {
    text = readFileSync(postsFile, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return [];
    stop("The state file cannot be read.");
  }
  return text
    .split("\n")
    .filter((line) => line !== "")
    .map((line, index) => {
      let post;
      try {
        post = JSON.parse(line);
      } catch {
        stop(`Line ${index + 1} of the state file cannot be read.`);
      }
      const whole = (value) => Number.isSafeInteger(value) && value > 0;
      if (!kinds.has(post?.kind) || !whole(post.pr) || !whole(post.id) || typeof post.session !== "string" || post.session === "") {
        stop(`Line ${index + 1} of the state file cannot be read.`);
      }
      return post;
    });
}

/// The review's counted marker: { round, head, high, medium, low, owner }; null when the body has no
/// marker. More than one marker, or one without counts, stops.
function reviewMarker(body, stop) {
  const found = (body ?? "").match(anyMarker) ?? [];
  if (found.length === 0) return null;
  if (found.length > 1) stop("A review by this account holds more than one marker.");
  const counted = countedMarker.exec(body);
  if (!counted) stop("A review's marker carries no counts (round, head, high, medium, low, owner); the owner merges.");
  const [, round, head, high, medium, low, owner] = counted;
  return { round: Number(round), head, high: Number(high), medium: Number(medium), low: Number(low), owner: Number(owner) };
}

/// Merges PR `pr` (a checked number, as text) or calls `stop`, which must not return. Returns gh's
/// exit status.
export function merge(pr, stop) {
  const where = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (where.status !== 0) stop("Run it inside a checkout of this repository.");
  const top = where.stdout.trim();
  const run = (args, options = {}) => spawnSync("git", args, { cwd: top, encoding: "utf8", maxBuffer: 1 << 30, ...options });
  const git = (args, options = {}) => {
    const result = run(args, options);
    if (result.status !== 0) stop(`git ${args[0]} failed (exit ${result.status}).`);
    return result.stdout;
  };
  const isAncestor = (older, newer) =>
    run(["cat-file", "-e", `${older}^{commit}`]).status === 0 && run(["merge-base", "--is-ancestor", older, newer]).status === 0;
  const api = (path) => {
    const result = spawnSync("gh", ["api", "--method", "GET", path], { cwd: top, encoding: "utf8", maxBuffer: 1 << 28 });
    if (result.error) stop(`gh could not be started (${result.error.code ?? "unknown error"}).`);
    if (result.status !== 0) stop(`gh api could not read ${path.replace(/\?.*$/, "")}.`);
    try {
      return JSON.parse(result.stdout);
    } catch {
      stop(`gh api returned no JSON for ${path.replace(/\?.*$/, "")}.`);
    }
  };
  const pages = (path) => {
    const items = [];
    for (let page = 1; page <= maxPages; page += 1) {
      const batch = api(`${path}?per_page=100&page=${page}`);
      if (!Array.isArray(batch)) stop(`gh api returned no list for ${path}.`);
      items.push(...batch);
      if (batch.length < 100) return items;
    }
    stop(`${path} has more than ${maxPages * 100} items; the owner merges.`);
  };

  // 1. The PR.
  const login = api("user")?.login;
  if (typeof login !== "string" || login === "") stop("gh is not signed in.");
  const info = api(`${repo}/pulls/${pr}`);
  if (info?.state !== "open") stop("The PR is not open.");
  if (info.draft !== false) stop("The PR is a draft.");
  if (info.base?.ref !== "main") stop("The PR's base is not main.");
  const headRepo = info.head?.repo?.full_name;
  if (typeof headRepo !== "string" || headRepo !== info.base?.repo?.full_name || String(info.head?.ref).startsWith("fork/")) {
    stop("The PR comes from a fork or a fork/ branch; the owner merges.");
  }
  if (info.user?.login !== login) stop("The PR was not opened by the account gh is signed in as.");
  const head = info.head?.sha;
  if (typeof head !== "string" || !/^[0-9a-f]{40}$/.test(head)) stop("The PR has no head commit.");
  if (typeof info.title !== "string" || (info.body !== null && typeof info.body !== "string") || typeof info.head.ref !== "string") {
    stop("The PR has no title, body or branch name.");
  }
  const body = (info.body ?? "").replace(/\r/g, "");

  // 2. The commits.
  if (run(["rev-parse", "--verify", "--quiet", `refs/remotes/origin/pr/${pr}^{commit}`]).stdout?.trim() !== head) {
    stop(`origin/pr/${pr} is not the PR's head; run git fetch origin, then gh-post merge again.`);
  }
  const main = api(`${repo}/branches/main`)?.commit?.sha;
  if (typeof main !== "string" || !/^[0-9a-f]{40}$/.test(main)) stop("GitHub named no commit for main.");
  if (!isAncestor(main, head)) stop("The PR is not up to date with main (or main is not fetched); update it, then run gh-post merge again.");

  // 3. The class.
  const classLines = body.split("\n").filter((line) => /^\s*class\s*:/i.test(line));
  if (classLines.length !== 1) stop("The PR body must hold exactly one line `Class: plain` or `Class: risky`.");
  if (classLines[0] !== "Class: plain") stop("The PR's class line is not `Class: plain`; a risky PR is the owner's to merge.");
  const entries = denyList(stop);
  let changes;
  try {
    changes = readChanges(git, main, head);
  } catch {
    stop("The diff from main could not be read in full.");
  }
  const judged = classify(changes, entries);
  if (!judged.plain) {
    const shown = judged.reasons.slice(0, reportLimit).map((reason) => `  ${reason}`);
    if (judged.reasons.length > reportLimit) shown.push(`  … and ${judged.reasons.length - reportLimit} more`);
    stop(`computed: risky; the owner merges.\n${shown.join("\n")}`);
  }

  // 4. CI.
  const checks = api(`${repo}/commits/${head}/check-runs?filter=latest&per_page=100`);
  const runs = checks?.check_runs;
  if (!Array.isArray(runs) || !Number.isSafeInteger(checks.total_count)) stop("GitHub returned no check runs.");
  if (checks.total_count > runs.length) stop("The head has more check runs than one page; the owner merges.");
  for (const name of Object.keys(required)) {
    if (!runs.some((check) => check?.name === name)) stop(`The required check ${name} has not run on the head.`);
  }
  for (const check of runs) {
    const name = typeof check?.name === "string" ? printable(check.name, entries) : "a check without a name";
    if (check?.status !== "completed") stop(`The check ${name} is still running; run gh-post merge again when it has finished.`);
    const allowed = required[check.name] ?? otherConclusions;
    if (!allowed.includes(check.conclusion)) stop(`The check ${name} did not pass.`);
  }
  const status = api(`${repo}/commits/${head}/status`);
  if (!(status?.total_count === 0 || status?.state === "success")) stop("The head's commit status is not success.");

  // 5. The guard, again.
  const commits = git(["rev-list", head, `^${main}`]).split("\n").filter((sha) => sha !== "");
  if (commits.length > maxCommits) stop(`More than ${maxCommits} commits; the owner merges.`);
  const allowedFiles = binaryAllowlist(join(guardFolder, "binary-allowlist.txt"), () =>
    stop("No binary-allowlist.txt next to the installed guard; reinstall the guard (CLAUDE.md → Commands → Guard)."),
  );
  const findings = [];
  for (const sha of commits) scan(git, sha, entries, allowedFiles, findings);
  for (const [label, text] of [["the title", info.title], ["the branch name", info.head.ref]]) {
    const kind = match(text, entries);
    if (kind) findings.push(`${label}: ${kind}`);
  }
  body.split("\n").forEach((line, index) => {
    const kind = match(line, entries);
    if (kind) findings.push(`body line ${index + 1}: ${kind}`);
  });
  if (findings.length > 0) {
    stop(`the guard found ${findings.length} match(es):\n${findings.slice(0, reportLimit).map((finding) => `  ${finding}`).join("\n")}`);
  }

  // 6. The review.
  const posts = readPosts(stop).filter((post) => post.pr === Number(pr));
  const sessionOf = (kind, id) => posts.find((post) => post.kind === kind && post.id === id)?.session;
  const reviews = pages(`${repo}/pulls/${pr}/reviews`);
  const latestState = new Map();
  for (const review of reviews) {
    if (["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].includes(review?.state)) latestState.set(review.user?.login, review.state);
  }
  if ([...latestState.values()].includes("CHANGES_REQUESTED")) stop("A reviewer has changes requested.");
  const marked = reviews
    .filter((review) => review?.user?.login === login)
    .map((review) => ({ review, marker: reviewMarker(review.body, stop), session: sessionOf("review", review.id) }))
    .filter(({ marker }) => marker !== null);
  const recorded = marked.filter(({ session }) => session !== undefined);
  if (recorded.length === 0) stop("There is no review recorded by gh-post review for this PR.");
  const time = (text) => {
    const value = Date.parse(text);
    if (Number.isNaN(value)) stop("A review or comment has no time.");
    return value;
  };
  const last = recorded.reduce((best, item) =>
    item.marker.round > best.marker.round ||
    (item.marker.round === best.marker.round && time(item.review.submitted_at) > time(best.review.submitted_at))
      ? item
      : best,
  );
  if (marked.some(({ marker, session }) => session === undefined && marker.round >= last.marker.round)) {
    stop("A review by this account at the last round or later is not recorded in the state file; the owner merges.");
  }
  if (last.marker.high > 0) stop("The last review round counts a High; fix it and run another round.");
  if (recorded.some(({ marker }) => marker.owner > 0)) stop("A review round counts an owner finding; the owner merges.");
  if (/Changes required/.test(last.review.body)) stop("The last review says Changes required.");
  const reviewed = last.review.commit_id;
  if (last.marker.head !== reviewed) stop("The last review's marker names another head than the commit it was posted on.");
  if (!isAncestor(reviewed, head)) stop("The last review's commit is not an ancestor of the head (the branch was rewritten).");
  for (const comment of pages(`${repo}/pulls/${pr}/reviews/${last.review.id}/comments`)) {
    const text = typeof comment?.body === "string" ? comment.body : "";
    if (text.startsWith("**High ·") || text.includes("decision: owner")) stop("An inline comment of the last review is a High or an owner decision.");
  }
  const since = changedLines(git, reviewed, head);
  if (since === null || since > maxUnreviewed) {
    stop(`More than ${maxUnreviewed} lines (or a binary file) changed after the last review; the owner merges, or another round runs.`);
  }
  const creators = new Set(posts.filter((post) => post.kind === "pr-create").map((post) => post.session));
  if (creators.size === 0) stop("The PR's creation is not recorded (it was not created with gh-post pr-create); the owner merges.");
  if (creators.has(last.session)) stop("The last review was posted from the session that created the PR.");

  // 7. The answer comment.
  const { high, medium, low } = last.marker;
  if (high + medium + low > 0) {
    const reviewedAt = time(last.review.submitted_at);
    const answered = pages(`${repo}/issues/${pr}/comments`).some((comment) => {
      const session = sessionOf("comment", comment?.id);
      return (
        comment?.user?.login === login && session !== undefined && session !== last.session && time(comment.created_at) > reviewedAt
      );
    });
    if (!answered) stop("The last review has findings and no recorded answer comment after it from another session.");
  }

  // Merge, pinned to the head checked above.
  const merged = spawnSync("gh", ["pr", "merge", pr, "--merge", "--match-head-commit", head], { cwd: top, stdio: "inherit" });
  if (merged.error) stop(`gh could not be started (${merged.error.code ?? "unknown error"}).`);
  return merged.status ?? 1;
}
