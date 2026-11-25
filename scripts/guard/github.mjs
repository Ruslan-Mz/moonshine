// What gh-post merge (merge.mjs) and the headless review (review.mjs) read from git and GitHub, the
// same way: git in a checked repository, GitHub reads that stop on any failure, the CI rule and the
// review markers. `stop` is called with a message and must not return; no message holds PR text.
import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, realpathSync } from "node:fs";
import { join, resolve } from "node:path";
import { config, fold, printable } from "./matcher.mjs";

export const repo = "repos/{owner}/{repo}";
const maxPages = 10;
/// The conclusions each required check may have.
const required = { docs: ["success"], guard: ["success"], swift: ["success", "skipped"], "core-linux": ["success", "skipped"] };
const otherConclusions = ["success", "skipped", "neutral"];
const anyMarker = /<!--\s*moonshine-review\b/g;
const countedMarker =
  /<!-- moonshine-review round=([1-9][0-9]{0,3}) head=([0-9a-f]{40}) high=([0-9]{1,4}) medium=([0-9]{1,4}) low=([0-9]{1,4}) owner=([0-9]{1,4}) -->/;

/// git in the checkout around `cwd`: { top, run, git, isAncestor }. It refuses a checkout whose git
/// folder is not the one the guard was installed for (a `.git` file or commondir pointing elsewhere),
/// a shallow one, grafts and replace refs, and runs with fsmonitor and hooks off.
export function safeGit(stop, cwd = process.cwd()) {
  const env = { ...process.env, GIT_NO_REPLACE_OBJECTS: "1" };
  const off = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"];
  const where = spawnSync("git", [...off, "rev-parse", "--show-toplevel"], { cwd, env, encoding: "utf8" });
  if (where.status !== 0) stop("Run it inside a checkout of this repository.");
  const top = where.stdout.trim();
  const run = (args, options = {}) => spawnSync("git", [...off, ...args], { cwd: top, env, encoding: "utf8", maxBuffer: 1 << 30, ...options });
  const git = (args, options = {}) => {
    const result = run(args, options);
    if (result.status !== 0) stop(`git ${args[0]} failed (exit ${result.status}).`);
    return result.stdout;
  };
  const isAncestor = (older, newer) =>
    run(["cat-file", "-e", `${older}^{commit}`]).status === 0 && run(["merge-base", "--is-ancestor", older, newer]).status === 0;
  let same = false;
  try {
    same = realpathSync(git(["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim()) === realpathSync(config(stop).mainGitDir);
  } catch {
    // a folder that cannot be resolved is not the installed one
  }
  if (!same) stop("This checkout's git folder is not the one the guard was installed for; the owner checks it.");
  if (git(["rev-parse", "--is-shallow-repository"]).trim() !== "false") stop("The checkout is shallow; the owner merges.");
  if (existsSync(resolve(top, git(["rev-parse", "--git-path", "info/grafts"]).trim()))) stop("The checkout has grafts; the owner merges.");
  if (git(["for-each-ref", "--count=1", "--format=x", "refs/replace/"]).trim() !== "") stop("The checkout has replace refs; the owner checks them.");
  return { top, run, git, isAncestor };
}

/// GitHub reads through gh from `top`: { api, pages }. Every failure stops.
export function gitHub(top, stop) {
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
  return { api, pages };
}

/// Stops unless CI passed on `head` for PR `pr`: the newest run of each check name among the runs on
/// the head for this PR (every run named and with an id), docs and guard succeeded, swift and
/// core-linux succeeded or were skipped, every other check completed as a success, skipped or
/// neutral, and the commit status is success or there is none.
export function ciGreen(api, pr, head, entries, stop) {
  const checks = api(`${repo}/commits/${head}/check-runs?filter=latest&per_page=100`);
  if (!Array.isArray(checks?.check_runs) || !Number.isSafeInteger(checks.total_count)) stop("GitHub returned no check runs.");
  if (checks.total_count > checks.check_runs.length) stop("The head has more check runs than one page; the owner merges.");
  // A workflow run again on the same head (guard on an edited body) is another check suite, which
  // filter=latest does not fold: the newest run of each name counts, by its id. Runs belong to a
  // commit, not a PR: only runs on this head for this PR count, so another PR on the same commit
  // cannot hide a failure.
  const newest = new Map();
  for (const check of checks.check_runs) {
    if (!Number.isSafeInteger(check?.id)) stop("A check run has no id.");
    if (typeof check.name !== "string" || check.name === "") stop("A check run has no name.");
    const forThisPR = Array.isArray(check.pull_requests) && check.pull_requests.some((item) => item?.number === Number(pr));
    if (check.head_sha !== head || !forThisPR) continue;
    if (!newest.has(check.name) || check.id > newest.get(check.name).id) newest.set(check.name, check);
  }
  const runs = [...newest.values()];
  for (const name of Object.keys(required)) {
    if (!runs.some((check) => check?.name === name)) stop(`The required check ${name} has not run on the head.`);
  }
  for (const check of runs) {
    const name = printable(check.name, entries);
    if (check?.status !== "completed") stop(`The check ${name} is still running; run the command again when it has finished.`);
    const allowed = required[check.name] ?? otherConclusions;
    if (!allowed.includes(check.conclusion)) stop(`The check ${name} did not pass.`);
  }
  const status = api(`${repo}/commits/${head}/status`);
  if (!(status?.total_count === 0 || status?.state === "success")) stop("The head's commit status is not success.");
}

/// A body as the marker checks read it (PR #67 round 1): folded like the guard's scan (NFKC, no
/// zero-width characters or soft hyphens, lower case), then every hyphen-like character as `-`
/// (NFKC leaves U+2010–U+2015 and U+2212 alone) and the small and full-width `-`, `<` and `>` as
/// themselves, so a marker no one sees still counts.
function markerText(body) {
  return fold(body)
    .replace(/[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]/g, "-")
    .replace(/[\uFE64\uFF1C]/g, "<")
    .replace(/[\uFE65\uFF1E]/g, ">");
}

/// Whether a body holds a marker of any shape, in any spelling: a non-global test, so calls over
/// several bodies share no `lastIndex` (P-AM2).
export function hasMarker(body) {
  return typeof body === "string" && /<!--\s*moonshine-review\b/.test(markerText(body));
}

/// A marker's findings of every kind; a round counts as one with findings when this is above 0.
export function findingCount(marker) {
  return marker.high + marker.medium + marker.low + marker.owner;
}

/// The owner's decisions file for round `round` of PR `pr`, as the answer comment names it.
export function decisionsFile(pr, round) {
  return `Claude outputs/next/pr${pr}-round${round}.md`;
}

/// Whether the decisions file exists in the checkout at `top` as a regular file. Only the owner
/// writes it (CLAUDE.md → "Pull requests"); it is never read. From the checkout's real folder down,
/// each part of the path must be listed under that exact name (no other case) and be a folder, the
/// last one a file, never a link (PR #67 round 1).
export function decisionsFileExists(top, pr, round) {
  const parts = decisionsFile(pr, round).split("/");
  try {
    let path = realpathSync(top);
    for (const [index, part] of parts.entries()) {
      if (!readdirSync(path).includes(part)) return false;
      path = join(path, part);
      const stat = lstatSync(path);
      if (index < parts.length - 1 ? !stat.isDirectory() : !stat.isFile()) return false;
    }
    return true;
  } catch {
    return false;
  }
}

// A decision's label (PR #69, owner 2026-11-23; any case, P-AM3, owner 2026-11-25):
// `- <path:line or class>: keep` or `- <path:line or class>: fix: <what>`, with some text after `fix:`.
const decisionLabel = /^- \S.*?: (?:keep(?![A-Za-z0-9_-])|fix:[ \t]*\S)/i;

/// Whether an answer comment carries the owner decisions block of round `round` of PR `pr` (P-AM2,
/// owner 2026-11-17 and 2026-11-20): exactly one line `Owner decisions: <decisionsFile>`, followed
/// directly by lines starting `- ` and some text, then a blank line or the end. Exactly `count` of
/// them carry a label; a line without one decides nothing and counts for nothing (P-AM3). The file
/// itself is never read here; the callers check that it exists.
export function ownerDecisions(body, count, pr, round) {
  if (typeof body !== "string") return false;
  const lines = body.replace(/\r/g, "").split("\n");
  const header = `Owner decisions: ${decisionsFile(pr, round)}`;
  const at = lines.flatMap((line, index) => (/^Owner decisions:/.test(line) ? [index] : []));
  if (at.length !== 1 || lines[at[0]] !== header) return false;
  const items = lines.slice(at[0] + 1);
  const end = items.findIndex((line) => !/^- \S/.test(line));
  const block = end === -1 ? items : items.slice(0, end);
  const labelled = block.filter((line) => decisionLabel.test(line)).length;
  return labelled === count && (end === -1 || items[end].trim() === "");
}

/// The review's counted marker: { round, head, high, medium, low, owner }; null when the body has no
/// marker. More than one marker, or one without counts, stops.
export function reviewMarker(body, stop) {
  const found = markerText(body ?? "").match(anyMarker) ?? [];
  if (found.length === 0) return null;
  if (found.length > 1) stop("A review by this account holds more than one marker.");
  const counted = countedMarker.exec(body);
  if (!counted) stop("A review's marker carries no counts (round, head, high, medium, low, owner); the owner merges.");
  const [, round, head, high, medium, low, owner] = counted;
  return { round: Number(round), head, high: Number(high), medium: Number(medium), low: Number(low), owner: Number(owner) };
}
