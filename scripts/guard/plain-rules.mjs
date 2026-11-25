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

/// Paths a plain pull request may change (old and new name alike). Specs and design notes are text
/// nothing runs (owner, 2026-11-16, P-HR): a plain PR may record an owner decision in them. Only
/// Markdown there, and only data in fixtures/ (owner, 2026-11-17, PR #63 round 1).
const plainPaths = [
  /^Apps\/Mac\/Sources\/(?:Today|Lines|Week|Palette)\/[^/]+\.swift$/,
  /^Apps\/Mac\/Sources\/(?:RootView|Tokens|ViewCommands)\.swift$/,
  /^Apps\/Mac\/Resources\/Localizable\.xcstrings$/,
  /^Apps\/Mac\/Tests\/[^/]+\.swift$/,
  /^MoonShineCore\/Tests\/(?:[^/]+\/)*[^/]+\.swift$/,
  /^MoonShineCore\/Sources\/MoonShineCore\/Services\/(?:Overview|Stats|Trace|DayLoad)\.swift$/,
  /^MoonShineCore\/Sources\/MoonShineFixtures\/[^/]+\.swift$/,
  /^fixtures\/(?:[^/]+\/)*(?:[^/]+\.(?:md|json|ya?ml|txt)|\.gitkeep)$/,
  /^docs\/method\/log\/\d{4}-\d{2}\.md$/,
  /^docs\/method\/forecast\.md$/,
  /^docs\/specs\/(?:[^/]+\/)*[^/]+\.md$/,
  /^design\/(?:[^/]+\/)*[^/]+\.md$/,
];
// Claude Code's own instructions, at any depth, are never plain: it loads a nested CLAUDE.md too.
export const instructions = /(?:^|\/)(?:claude\.md|claude\.local\.md|\.claude|\.mcp\.json)(?:\/|$)/i;
// A tool's config is never plain, wherever it sits: Prettier, ESLint, npm and git read it and may
// load code it names (owner, 2026-11-17, PR #63 round 1).
const toolConfig =
  /(?:^|\/)(?:\.prettierrc[^/]*|\.prettierignore|prettier\.config\.[^/]*|\.eslintrc[^/]*|eslint\.config\.[^/]*|package(?:-lock)?\.json|\.npmrc|\.nvmrc|[jt]sconfig[^/]*\.json|\.editorconfig|\.gitattributes|\.gitignore|node_modules)(?:\/|$)/i;

const testPath = /^(?:Apps\/Mac\/Tests|MoonShineCore\/Tests)\//;

const names = (list) => list.join("|");
// A whole word: `Process`, not `ProcessInfo`; `actor`, not `MainActor`.
const word = (list) => new RegExp(`(?<![A-Za-z0-9_])(?:${names(list)})(?![A-Za-z0-9_])`);
// A part of a name: `withTaskGroup`, `DispatchQueue`.
const part = (list) => new RegExp(names(list));
// A C call: the name directly followed by `(`, not after a letter, digit, `_` or `.`, unless the `.`
// follows a C module's name: `unlink(` and `Foundation.unlink(`, not `items.remove(`.
const cCall = (list) =>
  new RegExp(`(?<![A-Za-z0-9_.])(?:(?:Foundation|Darwin|Glibc|Musl)\\s*\\.\\s*)?(?:${names(list)})\\s*\\(`);
// A member, called or passed: `.refresh(` and `action: model.refresh`, not `.selection`.
const member = (list) => new RegExp(`\\.(?:${names(list)})(?![A-Za-z0-9_])`);
// A member called: `.start(`, not `span.start`.
const call = (list) => new RegExp(`\\.(?:${names(list)})\\s*\\(`);
// The app model's member, called or passed: `model.start` and `appModel.load`. A reference through
// another name passes; every plain pull request still has its full review (owner, 2026-11-11).
const onModel = (list) => new RegExp(`(?<![A-Za-z0-9_])(?:model|appModel)\\s*\\.\\s*(?:${names(list)})(?![A-Za-z0-9_])`);

// `](scheme:`, the target of a markdown link, also in a String Catalog's values.
const markdownLink = /\]\(\s*[A-Za-z][A-Za-z0-9+.-]*:/;

const modelActions = ["select", "refresh", "approveHeldRemoval", "chooseVault", "setSource", "setVaultBookmark", "closeStores"];

// [kind, pattern, also in test files]
const tokens = [
  ["concurrency", /(?<![A-Za-z0-9_])Task\s*[{(<.]/, true],
  ["concurrency", member(["task"]), true],
  ["concurrency", word(["async", "await"]), false],
  ["concurrency", word(["actor", "Sendable", "nonisolated", "isolated", "Thread", "Timer"]), true],
  ["concurrency", part(["TaskGroup", "Dispatch", "OperationQueue", "Async\\w*Stream", "Continuation"]), true],
  ["concurrency", part(["NSLock", "NSRecursiveLock", "NSCondition", "pthread_", "os_unfair_lock", "assumeIsolated", "@concurrent", "@preconcurrency"]), true],
  ["concurrency", part(["performSelector", "afterDelay"]), true],
  ["process", word(["Process", "typealias", "dlopen", "dlsym", "getenv", "fopen", "popen"]), true],
  ["process", part(["ProcessInfo", "NSWorkspace", "NSAppleScript", "OSAKit", "NotificationCenter", "posix_spawn"]), true],
  ["process", part(["NSClassFromString", "NSSelectorFromString", "classNamed", "@_", "[Uu]nsafe", "NSUser\\w*Task"]), true],
  ["process", part(["InputStream", "OutputStream", "Bundle\\s*\\(\\s*(?:path|url)"]), true],
  ["process", part(["NSXPC", "xpc_", "NSAppleEventDescriptor", "NSAppleEventManager", "NSRunningApplication"]), true],
  // The exec family by prefix: execl, execle, execlp, execv, execve, execvp, execvP, fexecve.
  ["process", cCall(["kill", "open", "system", "f?exec[lv]\\w*", "setenv", "unsetenv", "putenv", "f?chdir"]), true],
  ["storage", cCall(["unlink(?:at)?", "rename(?:at)?(?:x_np)?", "rmdir", "remove", "f?truncate", "creat"]), true],
  ["storage", cCall(["openat", "mkdir(?:at)?", "symlink(?:at)?", "link(?:at)?", "[fl]?chmod(?:at)?", "[fl]?chown(?:at)?", "f?copyfile", "f?clonefile(?:at)?"]), true],
  ["storage", cCall(["mkfifo(?:at)?", "mknod(?:at)?", "[fl]?utimes", "futimens", "utimensat"]), true],
  ["storage", cCall(["f?setxattr", "f?removexattr", "mko?s?temps?", "mkdtemp", "f?opendir", "fdopendir", "readdir(?:_r)?", "scandir", "fts_open", "n?ftw", "realpath"]), true],
  ["storage", part(["UserDefaults", "FileManager", "FileHandle", "write\\(to", "fileURLWithPath", "URL\\(filePath"]), true],
  ["storage", part(["NSHomeDirectory", "homeDirectory", "fileImporter", "fileExporter", "NSOpenPanel", "NSSavePanel"]), true],
  ["storage", part(["[Bb]ookmark", "SecurityScoped", "EventKit", "GRDB", "Yams"]), true],
  ["storage", part(["FileWrapper", "NSUbiquitousKeyValueStore", "DocumentGroup", "FileDocument", "NSDocument"]), true],
  // `contentsOf`, `withContentsOf`, `ContentsOfFile`: reads of a file the tokens above do not name.
  ["storage", part(["[Cc]ontentsOf", "NSAttributedString\\s*\\(\\s*(?:url|path)", "CGDataProvider", "CGPDFDocument", "CGImageSource"]), true],
  ["storage", part(["applicationSupportDirectory", "documentsDirectory", "fileURLWithFileSystemRepresentation"]), true],
  ["URL", part(["URLSession", "openURL", "onOpenURL", "AsyncImage", "byReferencing", "NetService", "getStreamsToHost", "NSURLConnection"]), true],
  ["URL", part(["CFStreamCreate\\w*Socket", "CFSocket", "CF(?:Read|Write)Stream"]), true],
  ["URL", cCall(["socket", "connect", "bind", "sendto"]), true],
  ["URL", /(?<![A-Za-z0-9_])Link\s*\(/, true],
  // A markdown link opens the browser on a click, as `Link` does: in a string literal, which `Text`
  // reads as markdown, in `AttributedString(markdown:)`, or as the `.link` attribute.
  ["URL", part(["AttributedString\\s*\\(\\s*markdown", "\\.link\\s*="]), true],
  ["URL", markdownLink, true],
  ["drag, pasteboard or sharing", part(["onDrop", "dropDestination", "draggable", "NSItemProvider", "NSPasteboard", "UIPasteboard", "ShareLink", "NSSharingService"]), true],
  ["drag, pasteboard or sharing", part(["copyable", "cuttable", "PasteButton", "pasteDestination", "onPasteCommand", "onCopyCommand", "onCutCommand", "onDrag", "exportableToServices", "importableFromServices", "importsItemProviders"]), true],
  ["drag, pasteboard or sharing", part(["NSUserActivity", "userActivity", "onContinueUserActivity", "handlesExternalEvents"]), true],
  ["model action", member(modelActions), true],
  ["model action", call(["start", "load"]), false],
  ["model action", onModel([...modelActions, "start", "load"]), false],
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
// `import Synchronization` stays risky in tests too: a lock is concurrency (rule 2).
const testableModules = new Set(["MoonShineCore", "MoonShineFixtures", "MoonShineMac"]);
// An import statement, not the word in a comment or a string (#70; P-AM3, owner 2026-11-25): where
// Swift may start one on a scanned line (its start, a lone CR, which ends a Swift line but not git's,
// `;`, or the end of a block comment), after attributes and access modifiers (`public import`).
// It runs only on a line holding `import`, no longer than `importLength`; a longer one is not read and
// stays risky, so a long line cannot make the match slow (PR #71 round 1).
const importLength = 1000;
const importStatement =
  /(?:^|[\r;]|\*\/)\s*(?:(?:@[A-Za-z_]\w{0,80}(?:\([^)\n]{0,200}\))?|public|package|internal|fileprivate|private)\s+)*import(?![A-Za-z0-9_])/;

// P-AM (owner, 2026-11-12, 2026-11-15 and 2026-11-16): three shapes are taken out of a line before
// the tokens scan it; every other token still scans the rest of the line.
//
// `Sendable` as an item of a type's conformance list, the whole declaration on one line: in Swift 6
// mode (Core and the app) the compiler checks the conformance, and `@unchecked`, which opts out, is
// not a plain item, so it stays. A generic clause, `where`, `@Sendable` and `any Sendable` stay too.
// The compiler does not check a subclass of an `@unchecked Sendable` class (`JSONDecoder`): a class
// passes only with `Sendable` first, where no superclass can stand. An extension of such a subclass
// cannot be told from the line and passes (accepted, owner 2026-11-16).
// Every run is bounded and the tail has one parse, so a long line cannot make the match slow; a line
// longer than `conformanceLength` is not read and stays risky.
const conformanceLength = 400;
const conformance =
  /^([ \t]{0,40}(?:(?:@\w{1,40}|public|package|internal|fileprivate|private|final|indirect)[ \t]{1,8}){0,6}(struct|enum|class|extension|protocol)[ \t]{1,8}[A-Za-z_]\w{0,80}[ \t]{0,8}:[ \t]{0,8})([\w.]{1,80}(?:[ \t]{0,8},[ \t]{0,8}[\w.]{1,80}){0,20})([ \t]{0,8}(?:\{[ \t]{0,8}(?:\}[ \t]{0,8})?)?(?:\/\/.*)?)$/;
// `.task` where it cannot be SwiftUI's modifier: a property chain or an enum case pattern.
const taskNotModifier = [
  /\.\s*task(?=\s*\.)/g,
  /(?<=(?<![A-Za-z0-9_])case\s+)\.\s*task(?=\s*\(\s*let(?![A-Za-z0-9_]))/g,
  /(?<=(?<![A-Za-z0-9_])case\s+let\s+)\.\s*task(?=\s*\()/g,
];
// And `.task(` on a receiver named here, in the paths named with it (owner, 2026-11-16): the app's
// type with a `task` case and the test helpers. A variable that shares one of these names passes;
// the review still reads every plain pull request. A new receiver needs a reviewed edit of this list.
const taskReceivers = [
  [/^Apps\/Mac\/(?:Sources\/Today|Tests)\//, ["TodayTableRow"]],
  [testPath, ["world", "TestWorld"]],
  [/^MoonShineCore\/Tests\/MoonShineCoreTests\/DayLoadTests\.swift$/, ["RigaDay", "R"]],
].map(([path, list]) => [path, new RegExp(`(?<=(?<![A-Za-z0-9_.])(?:${names(list)})\\s*)\\.\\s*task(?=\\s*\\()`, "g")]);
// In test files, `typealias X = Y` for one name `Y`, unless a token needs text after `Y`
// (`Task {`, `Link(`, `Bundle(path:`, `URL(filePath:`, `NSAttributedString(url:`), which the alias would hide. `Y` is still
// scanned. scripts/plain-rules.test.mjs reads these names from this file's patterns.
const aliasOfOneName = /^(\s*(?:(?:public|package|internal|fileprivate|private)\s+)?)typealias(\s+[A-Za-z_]\w*\s*=\s*([A-Za-z_]\w*)\s*(?:\/\/.*)?)$/;
const namesNeedingText = new Set(["Task", "Link", "Bundle", "URL", "NSAttributedString", "AttributedString"]);

/// The line as the tokens scan it: P-AM's shapes taken out.
function scanned(text, path, inTests) {
  let line = text;
  const list = line.length <= conformanceLength && conformance.exec(line);
  if (list) {
    const items = list[3].split(",").map((item) => item.trim());
    const allowed = list[2] === "class" ? items[0] === "Sendable" : items.includes("Sendable");
    if (allowed) line = list[1] + items.filter((item) => item !== "Sendable").join(", ") + list[4];
  }
  for (const pattern of taskNotModifier) line = line.replace(pattern, ".task_");
  for (const [where, pattern] of taskReceivers) if (where.test(path)) line = line.replace(pattern, ".task_");
  const alias = inTests && aliasOfOneName.exec(line);
  if (alias && !namesNeedingText.has(alias[3])) line = `${alias[1]}typealias_${alias[2]}`;
  return line;
}

/// Why a Swift line is risky, as a kind, or null.
function riskyToken(text, path) {
  const inTests = testPath.test(path);
  if (/canImport\s*\(/.test(text)) return "an import";
  if (text.includes("import") && text.length > importLength) return "an import";
  if (text.includes("import") && importStatement.test(text)) {
    const plainImport = /^\s*(@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\/\/.*)?$/.exec(text);
    if (!plainImport) return "an import";
    const [, testable, module] = plainImport;
    if (testable ? !(inTests && testableModules.has(module)) : !importModules.has(module)) return "an import";
  }
  const line = scanned(text, path, inTests);
  for (const [kind, pattern, inTestFiles] of tokens) {
    if ((inTestFiles || !inTests) && pattern.test(line)) return kind;
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

/// Plain, or risky with the reasons. `entries` is the deny-list: a path that matches it is named by
/// kind only, so the caller must pass it.
export function classify(changes, entries) {
  if (!Array.isArray(entries)) throw new Error("classify needs the deny-list's entries");
  const reasons = [];
  for (const change of changes) {
    const where = printable(change.path, entries);
    const name = change.path.normalize("NFC");
    if (instructions.test(name) || toolConfig.test(name) || !plainPaths.some((pattern) => pattern.test(change.path))) {
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
    // A catalog's value is markdown to `Text`: a link in it opens the browser on a click.
    if (change.path.endsWith(".xcstrings") && change.hunks.some((hunk) => hunk.some((line) => markdownLink.test(line.text)))) {
      reasons.push(`a risky token (URL) in or next to a change: ${where}`);
      continue;
    }
    if (!change.path.endsWith(".swift")) continue;
    const kinds = new Set();
    for (const hunk of change.hunks) {
      for (const line of hunk) {
        const kind = riskyToken(line.text, change.path);
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
