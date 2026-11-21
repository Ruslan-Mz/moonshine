// gh-post merge <pr>: the author session merges a plain pull request (CLAUDE.md → "Pull requests"),
// or is refused, and the owner merges it. It refuses whatever it cannot prove from GitHub's answers,
// the local commits and the state file:
//   1. the PR: open, not a draft, into main, from this repository (no fork, no fork/ branch), opened
//      by the account gh is signed in as;
//   2. the commits: origin/pr/<n> is the PR's head, and main is an ancestor of it;
//   3. the class: the body's one `Class: plain` line, and plain-rules.mjs on the diff from main;
//   4. CI, the newest run of each check name among the runs on the head for this PR (every run
//      named and with an id): docs and guard succeeded, swift and core-linux
//      succeeded or were skipped, every other check completed and succeeded, was skipped or
//      neutral, and the commit status is success or there is none;
//   5. the guard, again: commit-scan.mjs over the new commits, the title, the body, the branch name;
//   6. the review: the last round by the same account, recorded by gh-post review in a session other
//      than the one that created the PR, with the counted marker of /review-pr and no High; no
//      unrecorded marker review at that round or later; no inline High or owner decision; nobody's
//      changes requested; at most 100 lines changed since, counted from the reviewed commit merged
//      with main. A round with owner findings (P-AM2) is recorded, counts no fewer than its inline
//      owner decisions, and is followed by a later round on a newer head descending from it; the
//      last round then counts no owner finding, is round 2 at most, and no other account's marker
//      precedes it;
//   7. after every marker review with findings, its own answer comment: recorded, later than that
//      review and earlier than the account's next marker review, from another session than that
//      review's; after a round with owner findings, one of them carries its owner decisions block,
//      and the decisions file it names exists in the checkout (never read).
// Then `gh pr merge <n> --merge --match-head-commit <head>`, once. A refusal names the check, never
// PR text. git runs with replace refs off, in a full clone without grafts, so it reads the commits
// GitHub merges (github.mjs: the git folder the guard was installed for, no replace refs). The state
// file records each sent comment, review and PR (kind, PR, id, session, time).
// It and the session id guard against mistakes, not against a session set on getting around them:
// test code runs outside the sandbox and can write the state file.
// Tests: node --test scripts/gh-merge.test.mjs
import { spawnSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { binaryAllowlist, scan } from "./commit-scan.mjs";
import { ciGreen, decisionsFile, decisionsFileExists, findingCount, gitHub, hasMarker, ownerDecisions, repo, reviewMarker, safeGit } from "./github.mjs";
import { denyList, match } from "./matcher.mjs";
import { changedLines, classify, readChanges } from "./plain-rules.mjs";

const guardFolder = dirname(fileURLToPath(import.meta.url));
const postsFile = join(guardFolder, "..", "state", "posts.jsonl");
const kinds = new Set(["pr-create", "review", "comment"]);
const maxCommits = 2000;
const maxUnreviewed = 100;
const reportLimit = 10;

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
export function readPosts(stop) {
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

/// Merges PR `pr` (a checked number, as text) or calls `stop`, which must not return. Returns gh's
/// exit status.
export function merge(pr, stop) {
  const { top, run, git, isAncestor } = safeGit(stop);
  const { api, pages } = gitHub(top, stop);

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
  ciGreen(api, pr, head, entries, stop);

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
  // A round with owner findings (P-AM2, owner 2026-11-17): recorded, followed by a later round on a
  // newer head that descends from it; the last round counts none and is round 2 at most.
  const ownerRounds = marked.filter(({ marker }) => marker.owner > 0);
  if (ownerRounds.length > 0) {
    if (ownerRounds.some(({ session }) => session === undefined)) stop("A round with owner findings is not recorded in the state file; the owner merges.");
    if (last.marker.owner > 0) stop("The last review round counts an owner finding; the owner merges.");
    if (last.marker.round > 2) stop("A round with owner findings was followed by round 3 or later, which is the owner's; the owner merges.");
    for (const { marker, review } of ownerRounds) {
      if (marker.round >= last.marker.round || review.commit_id === last.review.commit_id || !isAncestor(review.commit_id, last.review.commit_id)) {
        stop("A round with owner findings has no later round on a newer head; push the fixes and run review again.");
      }
      const owned = pages(`${repo}/pulls/${pr}/reviews/${review.id}/comments`).filter((comment) => typeof comment?.body === "string" && comment.body.includes("decision: owner"));
      if (owned.length > marker.owner) stop("A round's marker counts fewer owner findings than its inline comments; the owner merges.");
    }
    // A marker by another account before the last round could have narrowed its diff.
    for (const review of reviews) {
      if (review?.user?.login !== login && hasMarker(review?.body) && time(review.submitted_at) < time(last.review.submitted_at)) {
        stop("Another account posted a review marker before the last round; the owner merges.");
      }
    }
  }
  if (last.marker.high > 0) stop("The last review round counts a High; fix it and run another round.");
  if (/Changes required/.test(last.review.body)) stop("The last review says Changes required.");
  const reviewed = last.review.commit_id;
  if (last.marker.head !== reviewed) stop("The last review's marker names another head than the commit it was posted on.");
  if (!isAncestor(reviewed, head)) stop("The last review's commit is not an ancestor of the head (the branch was rewritten).");
  for (const comment of pages(`${repo}/pulls/${pr}/reviews/${last.review.id}/comments`)) {
    const text = typeof comment?.body === "string" ? comment.body : "";
    if (text.startsWith("**High ·") || text.includes("decision: owner")) stop("An inline comment of the last review is a High or an owner decision.");
  }
  // The PR's own lines since the review: from the reviewed commit merged with main, so lines that
  // main brought in do not count.
  const merged = run(["merge-tree", "--write-tree", "--no-messages", reviewed, main]);
  if (merged.status !== 0) stop("The last review's commit does not merge cleanly with main; the owner merges, or another round runs.");
  const since = changedLines(git, merged.stdout.split("\n")[0], head);
  if (since === null || since > maxUnreviewed) {
    stop(`More than ${maxUnreviewed} lines (or a binary file) changed after the last review; the owner merges, or another round runs.`);
  }
  const creators = new Set(posts.filter((post) => post.kind === "pr-create").map((post) => post.session));
  if (creators.size === 0) stop("The PR's creation is not recorded (it was not created with gh-post pr-create); the owner merges.");
  if (creators.has(last.session)) stop("The last review was posted from the session that created the PR.");

  // 7. The answer comments: each round with findings has its own, after that round and before the
  // account's next marker review (or after the last), so one comment cannot answer two rounds.
  const rounds = marked
    .map((item) => ({ ...item, at: time(item.review.submitted_at) }))
    .sort((a, b) => a.at - b.at);
  // A round with owner findings needs the decisions block in one of them, and its file.
  if (rounds.some(({ marker }) => findingCount(marker) > 0)) {
    const answers = pages(`${repo}/issues/${pr}/comments`)
      .filter((comment) => comment?.user?.login === login)
      .map((comment) => ({ session: sessionOf("comment", comment.id), at: time(comment.created_at), body: comment.body }))
      .filter(({ session }) => session !== undefined);
    rounds.forEach(({ marker, session, at }, index) => {
      if (!(findingCount(marker) > 0)) return;
      const until = index + 1 < rounds.length ? rounds[index + 1].at : Infinity;
      const own = answers.filter((answer) => answer.session !== session && answer.at > at && answer.at < until);
      if (own.length === 0) {
        stop("A review round has findings and no recorded answer comment of its own, from another session, before the next round.");
      }
      if (marker.owner > 0) {
        if (!own.some((answer) => ownerDecisions(answer.body, marker.owner, pr, marker.round))) {
          stop(`A round with owner findings has no answer with its owner decisions block (Owner decisions: ${decisionsFile(pr, marker.round)}, one line per finding).`);
        }
        if (!decisionsFileExists(top, pr, marker.round)) stop(`The owner's decisions file ${decisionsFile(pr, marker.round)} is not in the checkout; the owner writes it.`);
      }
    });
  }

  // Merge, pinned to the head checked above.
  const done = spawnSync("gh", ["pr", "merge", pr, "--merge", "--match-head-commit", head], { cwd: top, stdio: "inherit" });
  if (done.error) stop(`gh could not be started (${done.error.code ?? "unknown error"}).`);
  return done.status ?? 1;
}
