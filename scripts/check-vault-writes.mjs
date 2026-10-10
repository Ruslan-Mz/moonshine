#!/usr/bin/env node
// No code path writes to the vault before the Write phase (ADR-0004, ADR-0014, ADR-0015).
// Searches the Swift sources of every target that can reach the vault for calls that write
// files, open a database or start a process or script, and fails on any outside the allowlist
// below. From the Write phase the `VaultWriter` implementation joins the allowlist.
//
// It is a text search: it catches a write added by accident, not one hidden on purpose (a call
// through a variable, a selector or a C function not listed here passes). Comments count: a
// listed call in a comment fails too. `bridge/snapshot.js` (JXA, OmniFocus only) is not searched.
//
// Usage: node scripts/check-vault-writes.mjs [repository root]
// Exit 0 clean, 1 with `file:line: pattern` per finding, 2 when a required folder is missing.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";

const required = ["MoonShineCore/Sources", "Adapters/Sources"];
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
  "Adapters/Sources/OmniFocusAdapter/OmniFocusBridge.swift": [
    "drives osascript through Process,",
    "let process = Process()",
  ],
};

const names = (list) => list.join("|");
// A whole word: `Process`, not `ProcessInfo`.
const word = (list) => new RegExp(`(?<![A-Za-z0-9_])(?:${names(list)})(?![A-Za-z0-9_])`);
// A member call: `.removeItem(`.
const member = (list) => new RegExp(`\\.(?:${names(list)})\\s*\\(`);
// A C call: the name and `(`, not after a letter, digit, `_` or `.` (so `items.remove(at:)`
// passes), except after the module prefix `Darwin.`, `Glibc.` or `Foundation.`.
const cCall = (list) =>
  new RegExp(`(?<![A-Za-z0-9_.])(?:(?:Darwin|Glibc|Foundation)\\.)?(?:${names(list)})\\s*\\(`);

const patterns = [
  [
    "FileManager change",
    member([
      "createFile", "createDirectory", "removeItem", "moveItem", "copyItem", "replaceItem",
      "replaceItemAt", "linkItem", "createSymbolicLink", "trashItem", "setAttributes",
    ]),
  ],
  ["write call", member(["write"])],
  ["file handle for writing", word(["forWritingTo", "forWritingAtPath", "forUpdating", "forUpdatingAtPath"])],
  ["writing type", word(["OutputStream", "FileWrapper", "NSFileCoordinator", "setResourceValues"])],
  [
    "C file call",
    cCall([
      "fopen", "freopen", "open", "openat", "creat", "fwrite", "pwrite", "rename", "renamex_np",
      "unlink", "remove", "mkdir", "rmdir", "truncate", "ftruncate", "symlink", "link", "copyfile",
      "clonefile",
    ]),
  ],
  ["database", word(["DatabasePool", "DatabaseQueue", "sqlite3_open", "sqlite3_open_v2"])],
  [
    "process or script",
    word(["Process", "NSTask", "posix_spawn", "posix_spawnp", "NSAppleScript", "NSUserAppleScriptTask", "OSAScript", "NSWorkspace"]),
  ],
  ["process or script", cCall(["system", "popen"])],
];

function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      return entry.name === ".build" || entry.name.endsWith("Tests") ? [] : swiftFiles(path);
    }
    return entry.isFile() && entry.name.endsWith(".swift") ? [path] : [];
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
  for (const path of swiftFiles(join(root, dir))) {
    const file = relative(root, path).split(sep).join("/");
    readFileSync(path, "utf8").split("\n").forEach((text, index) => {
      const line = (allowed[file] ?? []).reduce((rest, allow) => rest.split(allow).join(" "), text);
      for (const [name, pattern] of patterns) {
        if (pattern.test(line)) findings.push(`${file}:${index + 1}: ${name}`);
      }
    });
  }
}

if (findings.length > 0) {
  console.log("Calls that can write outside MoonShine's own data (no vault writes before the Write phase):");
  console.log(findings.join("\n"));
  process.exit(1);
}
console.log("Vault writes: clean");
