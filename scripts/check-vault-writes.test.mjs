// Tests for check-vault-writes.mjs on throwaway folders: node --test scripts/check-vault-writes.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "check-vault-writes.mjs");
const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const store = "Adapters/Sources/SQLiteStore/SQLiteStore.swift";
const tool = "Adapters/Sources/moonshine-import/MoonShineImport.swift";
const bridge = "Adapters/Sources/OmniFocusAdapter/OmniFocusBridge.swift";
const adapter = "Adapters/Sources/ObsidianAdapter/A.swift";
const app = "Apps/MoonShineMac/Sources/A.swift";

function run(root) {
  return spawnSync("node", [script, root], { encoding: "utf8" });
}

/// A throwaway repository with the two required folders and the given files.
function repositoryWith(files, folders = ["MoonShineCore/Sources", "Adapters/Sources"]) {
  const root = mkdtempSync(join(tmpdir(), "vault-writes-"));
  for (const folder of folders) mkdirSync(join(root, folder), { recursive: true });
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return root;
}

function check(files, folders) {
  return run(repositoryWith(files, folders));
}

function fails(line, where = adapter) {
  const result = check({ [where]: `import Foundation\n${line}\n` });
  assert.equal(result.status, 1, `${line}\n${result.stdout}${result.stderr}`);
  assert.match(result.stdout, new RegExp(`${where.replaceAll(".", "\\.")}:2: `), line);
}

function passes(line, where = adapter) {
  const result = check({ [where]: `import Foundation\n${line}\n` });
  assert.equal(result.status, 0, `${line}\n${result.stdout}${result.stderr}`);
  assert.match(result.stdout, /clean/);
}

const fileManager = [
  "createFile", "createDirectory", "removeItem", "moveItem", "copyItem", "replaceItem", "replaceItemAt",
  "linkItem", "createSymbolicLink", "trashItem", "setAttributes", "setUbiquitous",
];
const cCalls = [
  "fopen", "freopen", "open", "openat", "creat", "write", "writev", "pwrite", "pwritev", "fwrite", "fputs",
  "fputc", "rename", "renameat", "renamex_np", "renameatx_np", "unlink", "unlinkat", "remove", "removefile",
  "mkdir", "mkdirat", "rmdir", "mkstemp", "mkstemps", "mkdtemp", "truncate", "ftruncate", "symlink",
  "symlinkat", "link", "linkat", "copyfile", "clonefile", "chmod", "fchmod", "chown", "fchown", "lchown",
  "system", "popen", "execv", "execve", "execvp", "execvP", "execl", "execle", "execlp",
];

test("reading code passes", () => {
  passes(
    [
      "let handle = try FileHandle(forReadingFrom: url)",
      "let data = try Data(contentsOf: url)",
      "let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)",
      "let name = ProcessInfo.processInfo.processName",
      "try await writer.write { db in }",
      "let rewritten = text; let overwrite = true",
    ].join("\n"),
  );
});

test("every FileManager change fails", () => {
  for (const name of fileManager) {
    fails(`try FileManager.default.${name}(at: url)`);
    fails(`try manager.${name} (at: url)`);
  }
});

test("every way to write a file fails", () => {
  for (const line of [
    "try data.write(to: url)",
    "try text.write(toFile: path, atomically: true, encoding: .utf8)",
    "handle.write(data)",
    "FileHandle.standardError.write(data)",
    "try descriptor.writeAll(bytes)",
    "NSKeyedArchiver.archiveRootObject(object, toFile: path)",
    "let fd = try FileDescriptor.open(FilePath(path), .writeOnly, options: [.create, .truncate])",
    "var descriptor: FileDescriptor",
    "let handle = try FileHandle(forWritingTo: url)",
    "let handle = FileHandle(forWritingAtPath: path)",
    "let handle = try FileHandle(forUpdating: url)",
    "let handle = FileHandle(forUpdatingAtPath: path)",
    "let stream = OutputStream(url: url, append: false)",
    "let wrapper = FileWrapper(regularFileWithContents: data)",
    "let coordinator = NSFileCoordinator()",
    "try url.setResourceValues(values)",
  ]) {
    fails(line);
  }
});

test("a C call fails bare, after a module prefix and mid-line", () => {
  for (const name of cCalls) {
    fails(`${name}(path)`);
    fails(`  let result = ${name}(path, 0)`);
    fails(`if (${name}(path) == 0) {}`);
    for (const module of ["Darwin", "Glibc", "Foundation"]) fails(`_ = ${module}.${name}(path)`);
  }
});

test("a member, a declaration or another name with the same letters passes", () => {
  for (const name of cCalls) {
    // `.write(` is a member rule of its own: it fails after a dot too.
    if (name !== "write") {
      passes(`items.${name}(at: 0)`);
      passes(`self.${name}(path)`);
      passes(`Other.${name}(path)`);
    }
    passes(`func ${name}(_ id: Int) {}`);
    passes(`  public mutating func  ${name}(_ id: Int) {}`);
    passes(`let re${name}_x = 1; my_${name}(path)`);
    // The name must touch its parenthesis: prose such as "a link (see below)" is not a call.
    passes(`let text = "the parent ${name} (a wikilink)"`);
  }
  // A declaration does not excuse a call after it on the same line.
  fails("func remove(_ id: Int) { unlink(path) }");
});

test("a database fails", () => {
  for (const line of [
    "let pool = try DatabasePool(path: path)",
    "let queue = try DatabaseQueue()",
    "let queue: DatabaseQueue",
    "sqlite3_open(path, &db)",
    "sqlite3_open_v2(path, &db, flags, nil)",
  ]) {
    fails(line);
  }
  passes("let writer: any DatabaseWriter");
});

test("a process or a script fails in every form", () => {
  for (const line of [
    "let process = Process()",
    "try Process.run(url, arguments: [])",
    "var child: Process?",
    "let task = NSTask()",
    "posix_spawn(&pid, path, nil, nil, argv, nil)",
    "posix_spawnp(&pid, path, nil, nil, argv, nil)",
    'let script = NSAppleScript(source: "x")',
    "let task = try NSUserAppleScriptTask(url: url)",
    "let task = try NSUserUnixTask(url: url)",
    "let task = try NSUserScriptTask(url: url)",
    "let task = try NSUserAutomatorTask(url: url)",
    "let script = OSAScript(source: source)",
    "NSWorkspace.shared.open(url)",
  ]) {
    fails(line);
  }
});

test("a line that is only a comment is searched for member calls, not for names", () => {
  passes("/// Process the snapshot in one pass.");
  passes("  // Follows the note's parent link (a wikilink) to the artifact, then remove(it).");
  passes("// let process = Process()");
  fails("// try data.write(to: url)");
  fails("/// See FileManager.default.removeItem(at: url).");
  // A comment after code is part of a code line.
  fails("let x = 1 // Process the rest later");
});

test("an allowed text passes in its own file only", () => {
  passes("try self.init(writer: DatabasePool(path: path), timeZone: timeZone)", store);
  passes("try self.init(writer: DatabaseQueue(), timeZone: timeZone)", store);
  passes("try FileManager.default.removeItem(atPath: storePath + suffix)", tool);
  passes('FileHandle.standardError.write(Data((refusal + "\\n").utf8))', tool);
  passes("let process = Process()", bridge);
  fails("try self.init(writer: DatabasePool(path: path), timeZone: timeZone)", tool);
  fails("try FileManager.default.removeItem(atPath: storePath + suffix)", store);
  fails("let process = Process()", "Adapters/Sources/ObsidianAdapter/ObsidianVault.swift");
  fails("FileHandle.standardError.write(data)", bridge);
});

test("an allowed file fails on any other call, also on the same line", () => {
  fails("try data.write(to: vault)", tool);
  fails("FileHandle.standardError.write(data); try data.write(to: vault)", tool);
  fails("try FileManager.default.removeItem(atPath: folder)", tool);
  fails("try FileManager.default.removeItem(at: url)", tool);
  fails("let pool = try DatabasePool(path: other)", store);
  fails("let process = Process(); try Process.run(url, arguments: [])", bridge);
});

test("everything SwiftPM compiles under the required folders is searched; build folders are not", () => {
  fails("try data.write(to: url)", "Adapters/Sources/SomeTests/T.swift");
  fails("try data.write(to: url)", "Adapters/Sources/ObsidianAdapter/GoldenTests/B.swift");
  fails("try data.write(to: url)", "MoonShineCore/Sources/MoonShineCore/Services/A.swift");
  passes("try data.write(to: url)", "MoonShineCore/Sources/MoonShineCore/notes.md");
  const result = check({
    "Adapters/Sources/.build/checkouts/B.swift": "try data.write(to: url)\n",
    "Adapters/Tests/ObsidianAdapterTests/T.swift": "try data.write(to: url)\n",
    "MoonShineCore/Tests/T.swift": "try data.write(to: url)\n",
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test("a symbolic link under a searched folder is a finding, file or folder", () => {
  for (const [target, link] of [
    ["Elsewhere/B.swift", "Adapters/Sources/ObsidianAdapter/B.swift"],
    ["Elsewhere", "MoonShineCore/Sources/Linked"],
    ["Elsewhere/B.swift", "Apps/MoonShineMac/B.swift"],
  ]) {
    const root = repositoryWith({ "Elsewhere/B.swift": "let x = 1\n", "Apps/MoonShineMac/A.swift": "let y = 2\n" });
    mkdirSync(dirname(join(root, link)), { recursive: true });
    symlinkSync(join(root, target), join(root, link));
    const result = run(root);
    assert.equal(result.status, 1, `${link}\n${result.stdout}${result.stderr}`);
    assert.match(result.stdout, new RegExp(`${link.replaceAll(".", "\\.")}: symbolic link`));
  }
});

test("Apps is searched when it exists, its test folders are not, and it is not required", () => {
  fails("try data.write(to: url)", app);
  passes("let x = 1", app);
  passes("try data.write(to: url)", "Apps/MoonShineMacTests/A.swift");
  passes("try data.write(to: url)", "Apps/MoonShineMac/UITests/A.swift");
  assert.equal(check({}).status, 0);
});

test("in Apps anything that opens a URL fails; elsewhere those names are free", () => {
  const openers = [
    "@Environment(\\.openURL) private var openURL",
    "openURL(url)",
    "let action = OpenURLAction { _ in .handled }",
    'Link("Open in Obsidian", destination: url)',
    "Link(destination: url) { Text(title) }",
    "UIApplication.shared.open(url)",
    "let safari = SFSafariViewController(url: url)",
  ];
  for (const line of openers) {
    fails(line, app);
    passes(line, adapter);
  }
  fails("NSWorkspace.shared.open(url)", app);
  passes("ShareLink(item: text)", app);
  passes("NavigationLink(value: line) { Text(line.name) }", app);
  passes("let scenes = UIApplication.shared.connectedScenes", app);
});

const eventStore = "Adapters/Sources/CalendarAdapter/SystemEventStore.swift";
const calendarFile = "Adapters/Sources/CalendarAdapter/Provider.swift";

test("EventKit is imported only by the event store, in any spelling", () => {
  const spellings = [
    "import EventKit",
    "@preconcurrency import EventKit",
    "public import EventKit",
    "@_spi(X) internal import EventKit",
    "import class EventKit.EKEventStore",
    "import /* read only */ EventKit",
    "import `EventKit`",
    "let x = 1; import EventKit",
    "import EventKitUI",
  ];
  for (const where of [calendarFile, adapter, app, "MoonShineCore/Sources/MoonShineCore/A.swift"]) {
    for (const spelling of spellings) fails(spelling, where);
  }
  for (const spelling of spellings) passes(spelling, eventStore);
  passes("import EventKitty");
  passes("// import EventKit");
});

test("no other file names an EventKit type", () => {
  for (const where of [calendarFile, app, adapter]) {
    for (const line of ["let store: EKEventStore", "let view = EKEventEditViewController()", "_ = EKEvent.self"]) {
      fails(line, where);
    }
  }
  passes("let store = EKEventStore()", eventStore);
  passes("/// Wraps EKEventStore.", calendarFile);
  passes("let speaker = SPEAKer()", calendarFile);
});

test("the event store calls no EventKit write and asks for no reminders", () => {
  for (const line of [
    "try store.save(event, span: .thisEvent)",
    "try store.remove(event, span: .thisEvent, commit: true)",
    "try store.commit()",
    "try store.saveCalendar(calendar, commit: true)",
    "try store.removeCalendar(calendar, commit: true)",
    "try store.saveReminder(reminder, commit: true)",
    "try store.removeReminder(reminder, commit: true)",
    "try await store.requestWriteOnlyAccessToEvents()",
    "try await store.requestFullAccessToReminders()",
    "store.requestAccess(to: .event) { _, _ in }",
    "try save(event, span: .thisEvent)",
    "// store.save(event, span: .thisEvent)",
  ]) {
    fails(line, eventStore);
  }
  for (const line of [
    "try await store.requestFullAccessToEvents()",
    "store.reset()",
    "func remove(_ x: Int) {}",
    "let saved = store.calendars(for: .event)",
  ]) {
    passes(line, eventStore);
  }
  // Elsewhere these names are free: `Array.remove` is not a calendar write.
  passes("items.remove(at: 0)", calendarFile);
  passes("try context.save()", calendarFile);
});

test("a missing required folder exits 2", () => {
  for (const folders of [["MoonShineCore/Sources"], ["Adapters/Sources"], []]) {
    const result = check({}, folders);
    assert.equal(result.status, 2, result.stdout + result.stderr);
    assert.match(result.stderr, /not a folder/);
  }
});

test("the repository is clean, and not by accident", () => {
  const result = run(repository);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  // Without the allowlist the same texts fail: the search does see them.
  for (const [path, text] of [
    [store, "DatabasePool(path: path)"],
    [tool, "FileHandle.standardError.write("],
    [bridge, "let process = Process()"],
  ]) {
    fails(text, path.replace(".swift", "Copy.swift"));
  }
});
