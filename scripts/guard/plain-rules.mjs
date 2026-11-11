// Which changes gh-post merge may merge without the owner (CLAUDE.md rule 2, "Pull requests"): a
// pull request is plain only when every changed path is on the list below and no Swift line in or
// next to a change holds a risky token. Everything else is risky, and the owner merges it. This is
// a routing filter, not a review: it errs towards risky. A new folder or file needs a reviewed edit
// of this list. A reason names a kind and a path, never a line's text.
// Tests: node --test scripts/plain-rules.test.mjs
//
// The caller passes its own `git(args, options)`, which returns stdout and must not return on a
// failure (as for commit-scan.mjs); it runs from any folder of the checkout, with any config.
import { printable } from "./matcher.mjs";

const spec = "docs/specs/phase-1-see.md";

/// Paths a plain pull request may change (old and new name alike).
const plainPaths = [
  /^Apps\/Mac\/Sources\/(?:Today|Lines|Week|Palette)\/[^/]+\.swift$/,
  /^Apps\/Mac\/Sources\/(?:RootView|Tokens)\.swift$/,
  /^Apps\/Mac\/Resources\/Localizable\.xcstrings$/,
  /^Apps\/Mac\/Tests\/[^/]+\.swift$/,
  /^MoonShineCore\/Tests\/(?:[^/]+\/)*[^/]+\.swift$/,
  /^MoonShineCore\/Sources\/MoonShineCore\/Services\/(?:Overview|Stats|Trace|DayLoad)\.swift$/,
  /^MoonShineCore\/Sources\/MoonShineFixtures\/[^/]+\.swift$/,
  /^fixtures\/.+$/,
  /^docs\/method\/log\/\d{4}-\d{2}\.md$/,
  /^docs\/method\/forecast\.md$/,
  new RegExp(`^${spec.replace(/[./-]/g, "\\$&")}$`),
];

const testPath = /^(?:Apps\/Mac\/Tests|MoonShineCore\/Tests)\//;

const names = (list) => list.join("|");
// A whole word: `Process`, not `ProcessInfo`; `actor`, not `MainActor`.
const word = (list) => new RegExp(`(?<![A-Za-z0-9_])(?:${names(list)})(?![A-Za-z0-9_])`);
// A part of a name: `withTaskGroup`, `DispatchQueue`.
const part = (list) => new RegExp(names(list));
// A C call: the name directly followed by `(`, not after a letter, digit, `_` or `.`.
const cCall = (list) => new RegExp(`(?<![A-Za-z0-9_.])(?:${names(list)})\\s*\\(`);
// A member, called or passed: `.refresh(` and `action: model.refresh`, not `.selection`.
const member = (list) => new RegExp(`\\.(?:${names(list)})(?![A-Za-z0-9_])`);

// [kind, pattern, also in test files]
const tokens = [
  ["concurrency", /(?<![A-Za-z0-9_])Task\s*[{(<.]/, true],
  ["concurrency", member(["task"]), true],
  ["concurrency", word(["async", "await"]), false],
  ["concurrency", word(["actor", "Sendable", "nonisolated", "Thread", "Timer"]), true],
  ["concurrency", part(["TaskGroup", "Dispatch", "OperationQueue", "Async\\w*Stream", "Continuation"]), true],
  ["process", word(["Process", "typealias", "dlopen", "dlsym", "getenv", "fopen", "popen"]), true],
  ["process", part(["ProcessInfo", "NSWorkspace", "NSAppleScript", "OSAKit", "NotificationCenter", "posix_spawn"]), true],
  ["process", part(["NSClassFromString", "@_", "[Uu]nsafe"]), true],
  ["process", cCall(["kill", "open", "system"]), true],
  ["storage", part(["UserDefaults", "FileManager", "FileHandle", "write\\(to", "fileURLWithPath", "URL\\(filePath"]), true],
  ["storage", part(["NSHomeDirectory", "homeDirectory", "fileImporter", "fileExporter", "NSOpenPanel", "NSSavePanel"]), true],
  ["storage", part(["[Bb]ookmark", "SecurityScoped", "EventKit", "GRDB", "Yams"]), true],
  ["storage", /(?<![A-Za-z0-9_])contentsOf/, true],
  ["URL", part(["URLSession", "openURL", "onOpenURL"]), true],
  ["URL", /(?<![A-Za-z0-9_])Link\s*\(/, true],
  ["model action", member(["select", "refresh", "approveHeldRemoval", "chooseVault", "setSource", "setVaultBookmark", "closeStores"]), true],
  ["model action", member(["start", "load"]), false],
  ["line removal", part(["[Aa]pprov", "[Hh]eldRemoval", "[Ll]ineRemoval"]), true],
];

const importModules = new Set([
  "SwiftUI",
  "Foundation",
  "Observation",
  "Charts",
  "AppKit",
  "MoonShineCore",
  "MoonShineFixtures",
  "Testing",
  "XCTest",
]);
const testableModules = new Set(["MoonShineCore", "MoonShineMac"]);

/// Why a Swift line is risky, as a kind, or null.
function riskyToken(text, inTests) {
  if (/(?<![A-Za-z0-9_])import(?![A-Za-z0-9_])/.test(text)) {
    const plainImport = /^\s*(@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\/\/.*)?$/.exec(text);
    if (!plainImport) return "an import";
    const [, testable, module] = plainImport;
    if (testable ? !(inTests && testableModules.has(module)) : !importModules.has(module)) return "an import";
  }
  for (const [kind, pattern, inTestFiles] of tokens) {
    if ((inTestFiles || !inTests) && pattern.test(text)) return kind;
  }
  return null;
}

/// The changes from `base` to `head`: per path its status, modes, whether git counts it binary,
/// and its patch hunks (lines with kind "+", "-" or " "). Lines read must equal git's counts.
export function readChanges(git, base, head) {
  const top = git(["rev-parse", "--show-toplevel"]).trim();
  const run = (args, options = {}) => git(args, { cwd: top, ...options });
  const common = ["diff-tree", "-r", "-z", "--no-renames", "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative"];
  const raw = run([...common, "--raw", base, head]).split("\0");
  const counts = run([...common, "--numstat", base, head]).split("\0");
  const result = [];
  for (let index = 0; index + 1 < raw.length; index += 2) {
    // ":<old mode> <new mode> <old blob> <new blob> <status>", then the path
    const [oldMode, newMode, , , status] = raw[index].slice(1).split(" ");
    result.push({ path: raw[index + 1], oldMode, newMode, status, binary: false, added: 0, removed: 0, hunks: [] });
  }
  const numbers = counts.filter((field) => field !== "").map((field) => field.split("\t"));
  if (numbers.length !== result.length) throw new Error("git's file counts do not agree");
  numbers.forEach(([added, removed, path], index) => {
    const change = result[index];
    if (path !== change.path) throw new Error("git's file lists do not agree");
    if (added === "-") change.binary = true;
    else Object.assign(change, { added: Number(added), removed: Number(removed) });
  });
  for (const change of result) {
    if (change.binary) continue;
    const patch = run([
      "diff-tree", "-p", "--unified=3", "--no-color", "--no-ext-diff", "--no-textconv", "--text", "--no-relative",
      "--src-prefix=a/", "--dst-prefix=b/", base, head, "--", `:(literal)${change.path}`,
    ]);
    let hunk = null;
    let added = 0;
    let removed = 0;
    for (const text of patch.split("\n")) {
      if (text.startsWith("@@ ")) {
        hunk = [];
        change.hunks.push(hunk);
      } else if (hunk && /^[-+ ]/.test(text)) {
        hunk.push({ kind: text[0], text: text.slice(1) });
        if (text[0] === "+") added += 1;
        if (text[0] === "-") removed += 1;
      }
    }
    if (added !== change.added || removed !== change.removed) throw new Error("a patch does not match git's line counts");
  }
  return result;
}

/// Whether each run of changed lines in the spec only ticks boxes: as many removed lines as added
/// ones, in order, each `- [ ]` become `- [x]` with the rest unchanged.
function onlyTicks(change) {
  if (change.status !== "M") return false;
  for (const hunk of change.hunks) {
    const runs = [];
    let current = null;
    for (const line of hunk) {
      if (line.kind === " ") current = null;
      else {
        if (!current) runs.push((current = { removed: [], added: [] }));
        if (line.kind === "-" && current.added.length > 0) return false;
        (line.kind === "-" ? current.removed : current.added).push(line.text);
      }
    }
    for (const { removed, added } of runs) {
      if (removed.length !== added.length) return false;
      for (let index = 0; index < removed.length; index += 1) {
        const box = /^(\s*)- \[ \](.*)$/.exec(removed[index]);
        if (!box || added[index] !== `${box[1]}- [x]${box[2]}`) return false;
      }
    }
  }
  return true;
}

/// Plain, or risky with the reasons.
export function classify(changes, entries = []) {
  const reasons = [];
  for (const change of changes) {
    const where = printable(change.path, entries);
    if (!plainPaths.some((pattern) => pattern.test(change.path))) {
      reasons.push(`a path outside the plain list: ${where}`);
      continue;
    }
    const modes = change.status === "D" ? [change.oldMode] : [change.oldMode, change.newMode];
    if (!modes.every((mode) => mode === "100644" || mode === "000000") || (change.status !== "D" && change.newMode !== "100644")) {
      reasons.push(`a mode other than a plain file (a link, a submodule or an executable): ${where}`);
      continue;
    }
    if (change.binary) {
      reasons.push(`a binary change: ${where}`);
      continue;
    }
    if (change.path === spec && !onlyTicks(change)) {
      reasons.push(`a spec change beyond ticking boxes: ${where}`);
      continue;
    }
    if (!change.path.endsWith(".swift")) continue;
    const inTests = testPath.test(change.path);
    const kinds = new Set();
    for (const hunk of change.hunks) {
      for (const line of hunk) {
        const kind = riskyToken(line.text, inTests);
        if (kind) kinds.add(kind);
      }
    }
    for (const kind of kinds) reasons.push(`a risky token (${kind}) in or next to a change: ${where}`);
  }
  return { plain: reasons.length === 0, reasons };
}

/// Lines added and removed from `from` to `to`, or null when a change is binary.
export function changedLines(git, from, to) {
  const top = git(["rev-parse", "--show-toplevel"]).trim();
  let total = 0;
  for (const field of git(["diff-tree", "-r", "-z", "--no-renames", "--no-relative", "--numstat", from, to], { cwd: top }).split("\0")) {
    if (field === "") continue;
    const [added, removed] = field.split("\t");
    if (added === "-") return null;
    total += Number(added) + Number(removed);
  }
  return total;
}
