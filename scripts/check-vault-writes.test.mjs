// Tests for check-vault-writes.mjs on throwaway folders: node --test scripts/check-vault-writes.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "check-vault-writes.mjs");
const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const store = "Adapters/Sources/SQLiteStore/SQLiteStore.swift";
const tool = "Adapters/Sources/moonshine-import/MoonShineImport.swift";
const bridge = "Adapters/Sources/OmniFocusAdapter/OmniFocusBridge.swift";

function run(root) {
  return spawnSync("node", [script, root], { encoding: "utf8" });
}

/// A throwaway repository with the two required folders and the given files.
function check(files, folders = ["MoonShineCore/Sources", "Adapters/Sources"]) {
  const root = mkdtempSync(join(tmpdir(), "vault-writes-"));
  for (const folder of folders) mkdirSync(join(root, folder), { recursive: true });
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return run(root);
}

function fails(line, where = "Adapters/Sources/ObsidianAdapter/A.swift") {
  const result = check({ [where]: `import Foundation\n${line}\n` });
  assert.equal(result.status, 1, `${line}\n${result.stdout}${result.stderr}`);
  assert.match(result.stdout, new RegExp(`${where.replaceAll(".", "\\.")}:2: `), line);
}

function passes(line, where = "Adapters/Sources/ObsidianAdapter/A.swift") {
  const result = check({ [where]: `import Foundation\n${line}\n` });
  assert.equal(result.status, 0, `${line}\n${result.stdout}${result.stderr}`);
  assert.match(result.stdout, /clean/);
}

const fileManager = [
  "createFile", "createDirectory", "removeItem", "moveItem", "copyItem", "replaceItem", "replaceItemAt",
  "linkItem", "createSymbolicLink", "trashItem", "setAttributes",
];
const cCalls = [
  "fopen", "freopen", "open", "openat", "creat", "fwrite", "pwrite", "rename", "renamex_np", "unlink",
  "remove", "mkdir", "rmdir", "truncate", "ftruncate", "symlink", "link", "copyfile", "clonefile",
  "system", "popen",
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
    'try text.write(toFile: path, atomically: true, encoding: .utf8)',
    "handle.write(data)",
    "FileHandle.standardError.write(data)",
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

test("a C call fails bare, after a module prefix and mid-line; a member of the same name passes", () => {
  for (const name of cCalls) {
    fails(`${name}(path)`);
    fails(`  let result = ${name}(path, 0)`);
    fails(`if (${name} (path) == 0) {}`);
    for (const module of ["Darwin", "Glibc", "Foundation"]) fails(`_ = ${module}.${name}(path)`);
    passes(`items.${name}(at: 0)`);
    passes(`let re${name}_x = 1`);
    passes(`my_${name}(path)`);
    passes(`Other.${name}(path)`);
  }
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
    "let script = OSAScript(source: source)",
    "NSWorkspace.shared.open(url)",
  ]) {
    fails(line);
  }
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

test("a call in a comment fails", () => {
  fails("// try data.write(to: url)");
});

test("tests and build folders are not searched", () => {
  const result = check({
    "Adapters/Sources/.build/checkouts/B.swift": "try data.write(to: url)\n",
    "Adapters/Sources/SomeTests/T.swift": "try data.write(to: url)\n",
    "Adapters/Tests/ObsidianAdapterTests/T.swift": "try data.write(to: url)\n",
    "MoonShineCore/Tests/T.swift": "try data.write(to: url)\n",
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test("Core is searched, and files that are not Swift are not", () => {
  fails("try data.write(to: url)", "MoonShineCore/Sources/MoonShineCore/Services/A.swift");
  passes("try data.write(to: url)", "MoonShineCore/Sources/MoonShineCore/notes.md");
});

test("Apps is searched when it exists and is not needed when it does not", () => {
  fails("try data.write(to: url)", "Apps/MoonShineMac/Sources/A.swift");
  passes("let x = 1", "Apps/MoonShineMac/Sources/A.swift");
  assert.equal(check({}).status, 0);
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
  // Without the allowlist the same sources fail: the search does see them.
  for (const [path, text] of [
    [store, "DatabasePool(path: path)"],
    [tool, "FileHandle.standardError.write("],
    [bridge, "let process = Process()"],
  ]) {
    fails(text, path.replace(".swift", "Copy.swift"));
  }
});
