#!/usr/bin/env node
// No code path writes to the vault before the Write phase (ADR-0004, ADR-0014, ADR-0015).
// Searches the Swift sources of every target that can reach the vault for calls that write
// files, open a database or start a process or script, and fails on any outside the allowlist
// below. From the Write phase the `VaultWriter` implementation joins the allowlist. In `Apps`
// it also fails on anything that opens a URL: the app opens external URLs through one function
// with an allowlist of schemes (ADR-0015, amendment of 2026-10-10); that function joins the
// allowlist here in S4.
//
// Calendars are read-only until the Act phase (ADR-0012): EventKit and EventKitUI may be
// imported only by `CalendarAdapter/SystemEventStore.swift`, in any import spelling; no other
// file names an EventKit type (`EK…`), so no second file reaches the store; and that file calls
// none of EventKit's write or reminder names. `Array.remove` and the like elsewhere pass.
//
// It is a text search over the names listed below: it catches a write added by accident, not
// one hidden on purpose. What it does not see: a call through a variable, a selector or a
// function reference; a C or framework function not listed; anything in a dependency;
// `bridge/snapshot.js` (JXA, OmniFocus only).
//
// What it reserves in the searched targets:
// - the C names below as unqualified calls (`remove(x)`); a declaration (`func remove(`) and a
//   member call (`items.remove(at:)`, `self.remove(x)`) pass;
// - the type names below anywhere in code, and in a comment that follows code on its line;
//   a line that is only a `//` comment is not searched for C names and type names, so prose
//   passes. Member calls (`.write(`, `.removeItem(`) are searched in comments too.
// A symbolic link under a searched folder is a finding: SwiftPM compiles what it points to, and
// the search does not follow it.
//
// Usage: node scripts/check-vault-writes.mjs [repository root]
// Exit 0 clean, 1 with `file:line: pattern` per finding, 2 when a required folder is missing.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";

const required = ["MoonShineCore/Sources", "Adapters/Sources"];
// Searched when it exists. Only here are folders named `*Tests` left out: under the two
// required folders SwiftPM compiles such a folder into the product.
const optional = ["Apps"];

// File plus exact text. The text is removed from each line of that file before the search, so
// an allowed call never hides another call on the same line or elsewhere in the file.
const allowed = {
  // The store: MoonShine's own data.
  "Adapters/Sources/SQLiteStore/SQLiteStore.swift": ["DatabasePool(path: path)", "DatabaseQueue()"],
  // The measurement tool: its own store file, and a refusal printed to standard error.
  "Adapters/Sources/moonshine-import/MoonShineImport.swift": [
    "FileManager.default.removeItem(atPath: storePath + suffix)",
    "FileHandle.standardError.write(",
  ],
  // The OmniFocus bridge runs `osascript`.
  "Adapters/Sources/OmniFocusAdapter/OmniFocusBridge.swift": ["let process = Process()"],
};

// The one file that may use EventKit, read-only.
const eventStore = "Adapters/Sources/CalendarAdapter/SystemEventStore.swift";

const names = (list) => list.join("|");
// A whole word: `Process`, not `ProcessInfo`.
const word = (list) => new RegExp(`(?<![A-Za-z0-9_])(?:${names(list)})(?![A-Za-z0-9_])`);
// A member call: `.removeItem(`.
const member = (list) => new RegExp(`\\.(?:${names(list)})\\s*\\(`);
// A C call: the name directly followed by `(`; not after a letter, digit, `_` or `.` (so
// `items.remove(at:)` passes), except after the module prefix `Darwin.`, `Glibc.` or
// `Foundation.`; not a declaration (`func remove(`).
const cCall = (list) =>
  new RegExp(
    `(?<![A-Za-z0-9_.])(?<!\\bfunc\\s+)(?:(?:Darwin|Glibc|Foundation)\\.)?(?:${names(list)})\\(`,
  );

// [name, pattern, searched in a line that is only a comment, only under this folder]
const patterns = [
  [
    "FileManager change",
    member([
      "createFile", "createDirectory", "removeItem", "moveItem", "copyItem", "replaceItem",
      "replaceItemAt", "linkItem", "createSymbolicLink", "trashItem", "setAttributes", "setUbiquitous",
    ]),
    true,
  ],
  ["write call", member(["write", "writeAll", "archiveRootObject"]), true],
  [
    "file handle for writing",
    word(["forWritingTo", "forWritingAtPath", "forUpdating", "forUpdatingAtPath", "FileDescriptor"]),
  ],
  ["writing type", word(["OutputStream", "FileWrapper", "NSFileCoordinator", "setResourceValues"])],
  [
    "C file call",
    cCall([
      "fopen", "freopen", "open", "openat", "creat", "write", "writev", "pwrite", "pwritev", "fwrite",
      "fputs", "fputc", "rename", "renameat", "renamex_np", "renameatx_np", "unlink", "unlinkat",
      "remove", "removefile", "mkdir", "mkdirat", "rmdir", "mkstemp", "mkstemps", "mkdtemp",
      "truncate", "ftruncate", "symlink", "symlinkat", "link", "linkat", "copyfile", "clonefile",
      "chmod", "fchmod", "chown", "fchown", "lchown",
    ]),
  ],
  ["database", word(["DatabasePool", "DatabaseQueue", "sqlite3_open", "sqlite3_open_v2"])],
  [
    "process or script",
    word([
      "Process", "NSTask", "posix_spawn", "posix_spawnp", "NSAppleScript", "NSUserAppleScriptTask",
      "NSUserUnixTask", "NSUserScriptTask", "NSUserAutomatorTask", "OSAScript", "NSWorkspace",
    ]),
  ],
  [
    "process or script",
    cCall(["system", "popen", "execv", "execve", "execvp", "execvP", "execl", "execle", "execlp"]),
  ],
  ["URL opener", word(["openURL", "OpenURLAction", "SFSafariViewController"]), false, "Apps"],
  ["URL opener", /(?<![A-Za-z0-9_])Link\s*\(|UIApplication\.shared\.open/, false, "Apps"],
];

// Every import spelling `scripts/check-core-imports.sh` accepts: attributes (`@preconcurrency`),
// access modifiers, a symbol kind (`import class EventKit.EKEventStore`), block comments,
// backticks.
const eventKitImport = new RegExp(
  "(^|;)\\s*((@[A-Za-z_]+(\\s*\\([^)]*\\))?|public|package|internal|fileprivate|private)\\s+)*" +
    "import\\s+(/\\*[^*]*\\*/\\s*)*((typealias|struct|class|enum|protocol|let|var|func)\\s+)?" +
    "(/\\*[^*]*\\*/\\s*)*`?(EventKit|EventKitUI)`?([^A-Za-z0-9_]|$)",
);
// EventKit's writes and reminder access, as member calls (`store.save(`) and bare calls (`save(`
// inside an extension).
const calendarWrites = [
  "save", "remove", "commit", "saveCalendar", "removeCalendar", "saveReminder", "removeReminder",
  "requestWriteOnlyAccessToEvents", "requestFullAccessToReminders",
];
// [name, pattern, searched in a line that is only a comment, applies to this file]
const calendarPatterns = [
  ["EventKit import", eventKitImport, false, (file) => file !== eventStore],
  ["EventKit name", word(["EK[A-Z][A-Za-z0-9_]*"]), false, (file) => file !== eventStore],
  [
    "calendar write",
    new RegExp(
      `${member(calendarWrites).source}|${cCall(calendarWrites).source}|requestAccess\\s*\\(\\s*to:`,
    ),
    true,
    (file) => file === eventStore,
  ],
];

/// Swift files under `dir`, and every symbolic link (a finding, never followed).
function walk(dir, skipTests) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isSymbolicLink()) return [{ path, link: true }];
    if (entry.isDirectory()) {
      const skipped = entry.name === ".build" || (skipTests && entry.name.endsWith("Tests"));
      return skipped ? [] : walk(path, skipTests);
    }
    return entry.isFile() && entry.name.endsWith(".swift") ? [{ path }] : [];
  });
}

const root = process.argv[2] ?? ".";
const isFolder = (path) => existsSync(path) && statSync(path).isDirectory();
const missing = required.filter((dir) => !isFolder(join(root, dir)));
if (missing.length > 0) {
  console.error(`check-vault-writes: not a folder: ${missing.join(", ")}`);
  process.exit(2);
}

const findings = [];
for (const dir of [...required, ...optional.filter((dir) => isFolder(join(root, dir)))]) {
  for (const { path, link } of walk(join(root, dir), optional.includes(dir))) {
    const file = relative(root, path).split(sep).join("/");
    if (link) {
      findings.push(`${file}: symbolic link`);
      continue;
    }
    readFileSync(path, "utf8").split("\n").forEach((text, index) => {
      const line = (allowed[file] ?? []).reduce((rest, allow) => rest.split(allow).join(" "), text);
      const comment = line.trimStart().startsWith("//");
      for (const [name, pattern, inComments, only] of patterns) {
        if (comment && !inComments) continue;
        if (only && !file.startsWith(`${only}/`)) continue;
        if (pattern.test(line)) findings.push(`${file}:${index + 1}: ${name}`);
      }
      for (const [name, pattern, inComments, applies] of calendarPatterns) {
        if ((comment && !inComments) || !applies(file)) continue;
        if (pattern.test(line)) findings.push(`${file}:${index + 1}: ${name}`);
      }
    });
  }
}

if (findings.length > 0) {
  console.log(
    "Calls that can write outside MoonShine's own data (no vault writes before the Write phase, no calendar writes before the Act phase):",
  );
  console.log(findings.join("\n"));
  process.exit(1);
}
console.log("Vault writes: clean");
