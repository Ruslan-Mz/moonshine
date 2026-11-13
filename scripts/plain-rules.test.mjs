// Tests for the plain/risky rule of gh-post merge (scripts/guard/plain-rules.mjs), on throwaway
// repositories: node --test scripts/plain-rules.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { environment, ok } from "./guard-fixture.mjs";
import { changedLines, classify, readChanges } from "./guard/plain-rules.mjs";

const today = "Apps/Mac/Sources/Today/TodayView.swift";
const todayText = [
  "import SwiftUI",
  "",
  "struct TodayView: View {",
  "  var body: some View {",
  '    TableColumn("Task") { row in Text(row.title) }',
  "    Button(\"Remove\") {",
  "      removal.approve()",
  "    }",
  "    Text(\"one\")",
  "    Text(\"two\")",
  "    Text(\"three\")",
  "    Text(\"four\")",
  "  }",
  "}",
  "",
].join("\n");

const spec = "docs/specs/phase-1-see.md";
const specText = ["# Phase 1", "", "- [ ] **S4-2 — Lines**", "  - [ ] the live checks", "- [ ] **S5**", ""].join("\n");

/// A repository whose first commit holds `base`, and whose second applies `head` (a path to text,
/// or null to delete), with `setUp(work)` run before the second commit. Returns the git function the
/// rules take, the two commits and the repository.
function twoCommits(base, head, setUp = () => {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "plain-")));
  const work = { root, home: root, env: {}, cwd: join(root, "work") };
  ok({ ...work, cwd: root }, "init", "-q", work.cwd);
  const write = (files) => {
    for (const [path, text] of Object.entries(files)) {
      const full = join(work.cwd, path);
      if (text === null) {
        rmSync(full);
      } else {
        mkdirSync(dirname(full), { recursive: true });
        writeFileSync(full, text);
      }
    }
  };
  write({ "README.md": "hello\n", [today]: todayText, [spec]: specText, ...base });
  ok(work, "add", "-A");
  ok(work, "commit", "-q", "-m", "base");
  const from = ok(work, "rev-parse", "HEAD").trim();
  write(head);
  setUp(work);
  ok(work, "add", "-A");
  ok(work, "commit", "-q", "--allow-empty", "-m", "head");
  const to = ok(work, "rev-parse", "HEAD").trim();
  const git = (args, options = {}) => {
    const result = spawnSync("git", args, {
      cwd: work.cwd,
      env: environment(work.home),
      encoding: "utf8",
      maxBuffer: 1 << 30,
      ...options,
    });
    assert.equal(result.status, 0, `git ${args.join(" ")}\n${result.stderr}`);
    return result.stdout;
  };
  return { git, from, to, work };
}

function judge(base, head, setUp) {
  const { git, from, to } = twoCommits(base, head, setUp);
  return classify(readChanges(git, from, to), []);
}

function plain(base, head, setUp) {
  const result = judge(base, head, setUp);
  assert.equal(result.plain, true, `expected plain, got: ${result.reasons.join("; ")}`);
}

function risky(base, head, expected, setUp) {
  const result = judge(base, head, setUp);
  assert.equal(result.plain, false, "expected risky");
  assert.ok(
    result.reasons.some((reason) => reason.includes(expected)),
    `missing "${expected}" in: ${result.reasons.join("; ")}`,
  );
  return result;
}

for (const path of [
  "Apps/Mac/Sources/Today/TodayRail.swift",
  "Apps/Mac/Sources/Lines/LinesView.swift",
  "Apps/Mac/Sources/Week/WeekView.swift",
  "Apps/Mac/Sources/Palette/Palette.swift",
  "Apps/Mac/Sources/RootView.swift",
  "Apps/Mac/Sources/Tokens.swift",
  "Apps/Mac/Tests/TodayScreenTests.swift",
  "MoonShineCore/Tests/MoonShineCoreTests/StatsTests.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/Overview.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/Stats.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/Trace.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/DayLoad.swift",
  "MoonShineCore/Sources/MoonShineFixtures/DemoData.swift",
]) {
  test(`a new plain file passes: ${path}`, () => plain({}, { [path]: "import SwiftUI\n\nlet width = 12\n" }));
}

for (const [path, text] of [
  ["Apps/Mac/Resources/Localizable.xcstrings", '{ "strings": {} }\n'],
  ["fixtures/vault/Lines/Health.md", "---\nstatus: active\n---\n"],
  ["docs/method/log/2026-11.md", "| row |\n"],
  ["docs/method/forecast.md", "The factor is 1.57.\n"],
]) {
  test(`a plain non-Swift file passes: ${path}`, () => plain({}, { [path]: text }));
}

for (const path of [
  "Adapters/Sources/ObsidianAdapter/Vault.swift",
  "Apps/Mac/Sources/Live/LiveEnvironment.swift",
  "Apps/Mac/Sources/Settings/SettingsView.swift",
  "Apps/Mac/Sources/AppModel.swift",
  "Apps/Mac/Sources/Foo/Foo.swift",
  "Apps/Mac/Sources/Today/Nested/Deep.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/New.swift",
  "MoonShineCore/Sources/MoonShineCore/Domain/Line.swift",
  "Apps/Mac/Resources/InfoPlist.xcstrings",
  "design/screens/today.md",
  "docs/method/log.md",
  "docs/method/log/notes.md",
  ".github/workflows/ci.yml",
  "CLAUDE.md",
  "scripts/guard/merge.mjs",
  "project.yml",
  "MoonShineCore/Tests/MoonShineCoreTests/Data.json",
]) {
  test(`a risky path is risky: ${path}`, () => risky({}, { [path]: "x\n" }, "a path outside the plain list"));
}

test("a rename from a risky path is risky, though the new path is plain", () => {
  risky(
    { "Apps/Mac/Sources/Live/Old.swift": "let a = 1\n" },
    { "Apps/Mac/Sources/Live/Old.swift": null, "Apps/Mac/Sources/Today/Old.swift": "let a = 1\n" },
    '"Apps/Mac/Sources/Live/Old.swift"',
  );
});

test("deleting a plain file passes; deleting a risky one does not", () => {
  plain({ "Apps/Mac/Sources/Today/Gone.swift": "let a = 1\n" }, { "Apps/Mac/Sources/Today/Gone.swift": null });
  risky({ "Apps/Mac/Sources/Live/Gone.swift": "let a = 1\n" }, { "Apps/Mac/Sources/Live/Gone.swift": null }, "a path outside");
});

test("an executable mode is risky", () => {
  risky({}, { "fixtures/run.sh": "echo\n" }, "a mode", (work) => chmodSync(join(work.cwd, "fixtures", "run.sh"), 0o755));
});

test("a symbolic link is risky", () => {
  risky({}, {}, "a mode", (work) => {
    mkdirSync(join(work.cwd, "fixtures"), { recursive: true });
    symlinkSync("../README.md", join(work.cwd, "fixtures", "link.md"));
  });
});

test("a binary file is risky", () => {
  risky({}, { "fixtures/data.bin": Buffer.from([0, 1, 2, 0, 3]) }, "binary");
});

test("ticking a spec box passes", () => {
  plain({}, { [spec]: specText.replace("- [ ] **S4-2", "- [x] **S4-2").replace("  - [ ] the live", "  - [x] the live") });
});

test("a tick plus a word in the spec is risky", () => {
  risky({}, { [spec]: specText.replace("- [ ] **S4-2 — Lines**", "- [x] **S4-2 — Lines, done**") }, "spec");
});

test("unticking a spec box is risky", () => {
  risky({ [spec]: specText.replace("- [ ] **S5**", "- [x] **S5**") }, { [spec]: specText }, "spec");
});

test("a new line in the spec is risky", () => {
  risky({}, { [spec]: specText + "- [x] **S6**\n" }, "spec");
});

test("Task followed by a brace, added, is risky", () => {
  risky({}, { [today]: todayText.replace('    Text("two")', '    Task { await load() }') }, "concurrency");
});

test("Task.detached removed is risky", () => {
  risky(
    { [today]: todayText.replace('    Text("two")', "    Task.detached { }") },
    { [today]: todayText },
    "concurrency",
  );
});

test("a TableColumn named Task passes", () => {
  plain({}, { "Apps/Mac/Sources/Today/Columns.swift": 'TableColumn("Task") { row in Text(row.title) }\n' });
});

for (const [line, kind] of [
  ["Button(action: model.refresh) { }", "model action"],
  ["model.refresh()", "model action"],
  ["Link(destination: url) { }", "URL"],
  ["URLSession.shared.data(from: url)", "URL"],
  ["let data = try Data(contentsOfFile: path)", "storage"],
  ["let url = URL(filePath: path)", "storage"],
  ["let home = NSHomeDirectory()", "storage"],
  ["let p = Process()", "process"],
  ["let value = getenv(name)", "process"],
  ["_ = kill(pid, 9)", "process"],
  ["typealias Shell = Foo", "process"],
  ["@_silgen_name(\"x\") func x()", "process"],
  ["DispatchQueue.main.async { }", "concurrency"],
  ["actor Store { }", "concurrency"],
  [".task { }", "concurrency"],
  ["let ok = removal.canApprove", "line removal"],
  ["let hold = LineRemovalHold()", "line removal"],
  ["import EventKit", "an import"],
  ["@testable import ObsidianAdapter", "an import"],
  ["import struct Foundation.URL", "an import"],
]) {
  test(`a risky token is risky: ${line}`, () => {
    risky({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` }, kind);
  });
}

for (const line of [
  "NavigationLink(value: item) { }",
  "let width = TodayColumns.taskMinimum",
  "@MainActor final class Probe { }",
  "let skill = 1",
  "import Charts",
  "import SwiftUI",
  "@AppStorage(\"density\") var density = 0",
  "@SceneStorage(\"tab\") var tab = 0",
  "let selection = model.selection",
]) {
  test(`a harmless line passes: ${line}`, () => {
    plain({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` });
  });
}

test("a token on a context line next to a change is risky", () => {
  risky({}, { [today]: todayText.replace('    }\n    Text("one")', '    }\n    .keyboardShortcut("r")\n    Text("one")') }, "line removal");
});

test("a change far from a token passes", () => {
  plain({}, { [today]: todayText.replace('    Text("four")', '    Text("vier")') });
});

test("in a test file, async, await, .load( and .start( pass", () => {
  plain({}, { "Apps/Mac/Tests/ProbeTests.swift": "@Test func a() async throws {\n  await model.load()\n  model.start()\n}\n" });
});

test("in a test file, other model actions and tokens stay risky", () => {
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "@Test func a() {\n  model.refresh()\n}\n" }, "model action");
  risky({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": "let p = Process()\n" }, "process");
});

test("@testable import of the app or Core passes in a test file", () => {
  plain({}, { "Apps/Mac/Tests/ProbeTests.swift": "@testable import MoonShineMac\n@testable import MoonShineCore\nimport Testing\n" });
});

test("a reason names the path, never the line's text", () => {
  const result = risky({}, { "Apps/Mac/Sources/Today/Probe.swift": "let secretWord = Process()\n" }, "Probe.swift");
  assert.ok(result.reasons.every((reason) => !reason.includes("secretWord")), result.reasons.join("; "));
});

test("a global config with colour, a relative diff and no prefix changes nothing", () => {
  const { git, from, to, work } = twoCommits({}, { "Adapters/Sources/X.swift": "let a = 1\n", "Apps/Mac/Sources/Today/P.swift": "let p = Process()\n" });
  const config = join(work.root, "gitconfig");
  writeFileSync(config, "[color]\n\tui = always\n[diff]\n\trelative = true\n\tnoprefix = true\n");
  mkdirSync(join(work.cwd, "Apps", "Mac"), { recursive: true });
  const calls = [];
  const fromSubfolder = (args, options = {}) => {
    calls.push(args);
    return git(args, { cwd: join(work.cwd, "Apps", "Mac"), env: environment(work.home, { GIT_CONFIG_GLOBAL: config }), ...options });
  };
  const result = classify(readChanges(fromSubfolder, from, to), []);
  assert.equal(result.plain, false);
  assert.ok(result.reasons.some((reason) => reason.includes("Adapters/Sources/X.swift")), result.reasons.join("; "));
  assert.ok(result.reasons.some((reason) => reason.includes("process")), result.reasons.join("; "));
  // diff-tree is plumbing and ignores most of that config today; the flags keep it so.
  const diffs = calls.filter((args) => args[0] === "diff-tree");
  assert.equal(diffs.length, 4);
  for (const args of diffs) {
    for (const flag of ["--no-color", "--no-relative", "--no-ext-diff", "--no-textconv", "--no-renames"]) {
      if (flag === "--no-renames" && args.includes("-p")) continue;
      assert.ok(args.includes(flag), `${flag} missing in: ${args.join(" ")}`);
    }
  }
  for (const args of diffs.filter((call) => call.includes("-p"))) {
    for (const flag of ["--src-prefix=a/", "--dst-prefix=b/", "--text", "--unified=3"]) assert.ok(args.includes(flag), `${flag} missing`);
  }
});

test("a patch that does not match git's line counts stops", () => {
  const { git, from, to } = twoCommits({}, { "fixtures/a.md": "1\n2\n" });
  const padded = (args, options) => {
    const out = git(args, options);
    return args.includes("-p") ? out + "+3\n" : out;
  };
  assert.throws(() => readChanges(padded, from, to), /line counts/);
});

test("file lists that do not agree stop", () => {
  const { git, from, to } = twoCommits({}, { "fixtures/a.md": "1\n", "fixtures/b.md": "2\n" });
  const short = (args, options) => {
    const out = git(args, options);
    return args.includes("--numstat") ? out.split("\0").slice(1).join("\0") : out;
  };
  assert.throws(() => readChanges(short, from, to), /do not agree/);
});

test("a spec run whose added line comes before its removed one is not a tick", () => {
  const change = (hunk) => ({ path: spec, status: "M", oldMode: "100644", newMode: "100644", binary: false, hunks: [hunk] });
  const tick = [
    { kind: "-", text: "- [ ] **S5**" },
    { kind: "+", text: "- [x] **S5**" },
  ];
  assert.equal(classify([change(tick)], []).plain, true);
  assert.equal(classify([change([...tick].reverse())], []).plain, false);
});

test("classify needs the deny-list, and names a matching path by kind only", () => {
  const changes = [{ path: "Adapters/Mirelbrook.swift", status: "A", oldMode: "000000", newMode: "100644", binary: false, hunks: [] }];
  assert.throws(() => classify(changes), /deny-list/);
  const result = classify(changes, ["mirelbrook"]);
  assert.equal(result.plain, false);
  assert.ok(result.reasons.every((reason) => !/mirelbrook/i.test(reason)), result.reasons.join("; "));
  assert.ok(result.reasons.some((reason) => reason.includes("a file whose name matches")), result.reasons.join("; "));
});

for (const line of [
  "if from < span.start {",
  "let first = range.start",
  "Text(event.start, style: .time)",
  "let end = DateInterval(start: a, end: b).end",
  "let hours = day.load",
  "let selection = appModel.selection",
  "items.remove(at: 0)",
  "items.removeAll()",
  "let name = file.rename",
  "let id = Foundation.UUID()",
  "let done = job.executed",
  "items.truncateTail(2)",
]) {
  test(`a harmless member passes: ${line}`, () => {
    plain({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` });
  });
}

for (const [line, kind] of [
  ["Button(\"Go\", action: model.start)", "model action"],
  ["Button(\"Go\", action: appModel.load)", "model action"],
  ["appModel.refresh()", "model action"],
  ["model .load()", "model action"],
  ["feed.start()", "model action"],
  ["store.load ()", "model action"],
  [".onDrop(of: [.data], isTargeted: nil) { _ in true }", "drag, pasteboard or sharing"],
  [".dropDestination(for: Data.self) { items, _ in true }", "drag, pasteboard or sharing"],
  [".draggable(row.title)", "drag, pasteboard or sharing"],
  ["let provider = NSItemProvider(object: text)", "drag, pasteboard or sharing"],
  ["NSPasteboard.general.clearContents()", "drag, pasteboard or sharing"],
  ["let board = UIPasteboard.general", "drag, pasteboard or sharing"],
  ["ShareLink(item: url)", "drag, pasteboard or sharing"],
  ["let service = NSSharingService(named: .sendViaAirDrop)", "drag, pasteboard or sharing"],
  ["_ = execv(\"/bin/sh\", argv)", "process"],
  ["_ = execve(path, argv, envp)", "process"],
  ["_ = execlp(\"sh\", \"sh\")", "process"],
  ["_ = fexecve(fd, argv, envp)", "process"],
  ["let task = try NSUserUnixTask(url: script)", "process"],
  ["let task = try NSUserScriptTask(url: script)", "process"],
  ["let task = try NSUserAppleScriptTask(url: script)", "process"],
  ["let task = try NSUserAutomatorTask(url: script)", "process"],
  ["_ = unlink(path)", "storage"],
  ["_ = rename(from, to)", "storage"],
  ["_ = rmdir(path)", "storage"],
  ["_ = remove(path)", "storage"],
  ["Text(row.title).copyable([row.title])", "drag, pasteboard or sharing"],
  [".cuttable(for: String.self) { [row.title] }", "drag, pasteboard or sharing"],
  ["PasteButton(payloadType: String.self) { _ in }", "drag, pasteboard or sharing"],
  [".pasteDestination(for: String.self) { _ in }", "drag, pasteboard or sharing"],
  [".onPasteCommand(of: [.text]) { _ in }", "drag, pasteboard or sharing"],
  [".onCopyCommand { [] }", "drag, pasteboard or sharing"],
  [".onCutCommand { [] }", "drag, pasteboard or sharing"],
  [".onDrag { makeProvider(row) }", "drag, pasteboard or sharing"],
  [".exportableToServices { [row.title] }", "drag, pasteboard or sharing"],
  [".importableFromServices(for: String.self) { _ in true }", "drag, pasteboard or sharing"],
  [".importsItemProviders([.text]) { _ in true }", "drag, pasteboard or sharing"],
  ["_ = execvP(\"sh\", \"/bin\", argv)", "process"],
  ["_ = execvpe(file, argv, envp)", "process"],
  ["_ = unlinkat(AT_FDCWD, path, 0)", "storage"],
  ["_ = renameat(a, from, b, to)", "storage"],
  ["_ = renamex_np(from, to, 0)", "storage"],
  ["_ = renameatx_np(a, from, b, to, 0)", "storage"],
  ["_ = truncate(path, 0)", "storage"],
  ["_ = ftruncate(fd, 0)", "storage"],
  ["_ = creat(path, 0o644)", "storage"],
  ["_ = Foundation.unlink(path)", "storage"],
  ["_ = Foundation . rename(from, to)", "storage"],
  ["_ = Glibc.truncate(path, 0)", "storage"],
  ["_ = Foundation.kill(pid, SIGTERM)", "process"],
  ["_ = Foundation.open(path, O_RDONLY)", "process"],
  ["_ = Foundation.system(command)", "process"],
  ["AsyncImage(url: url)", "URL"],
  ["let image = NSImage(byReferencing: url)", "URL"],
  ["let type = Bundle.main.classNamed(name)", "process"],
  ["_ = object.perform(NSSelectorFromString(name))", "process"],
  ["let stream = InputStream(url: url)", "process"],
  ["let stream = OutputStream(toFileAtPath: path, append: false)", "process"],
  ["_ = Bundle(path: path)?.load()", "process"],
]) {
  test(`a risky token is risky: ${line}`, () => {
    risky({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` }, kind);
  });
}

test("in a test file, drag and pasteboard tokens stay risky, and import Synchronization too", () => {
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "let board = NSPasteboard.general\n" }, "drag, pasteboard or sharing");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "import Synchronization\n" }, "an import");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "Text(title).copyable([title])\n" }, "drag, pasteboard or sharing");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "_ = Foundation.unlink(path)\n" }, "storage");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "let image = AsyncImage(url: url)\n" }, "URL");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "_ = Bundle(path: path)?.load()\n" }, "process");
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "let stream = InputStream(url: url)\n" }, "process");
});

test("@testable import MoonShineFixtures passes in a test file", () => {
  plain({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": "@testable import MoonShineFixtures\nimport Testing\n" });
});

// The screen slices S4-2 and S5 (owner, 2026-11-11): on the repository's own files, a new screen,
// its sidebar case and its shortcut compute plain; the held line removal stays risky.
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const own = (path) => readFileSync(join(repoRoot, path), "utf8");
const screenFiles = ["Apps/Mac/Sources/RootView.swift", "Apps/Mac/Sources/ViewCommands.swift", "Apps/Mac/Sources/LineRemoval.swift", today];

// Each edit must find its text, so a test cannot pass on an edit that did nothing.
function edited(path, ...edits) {
  let text = own(path);
  for (const [old, replacement] of edits) {
    assert.ok(text.includes(old), `${path} no longer holds: ${old}`);
    text = text.replace(old, replacement);
  }
  return text;
}

// The edits are anchored on the lines a screen slice adds to, not on lines it rewrites: the
// sidebar enum's header, the sidebar list, the detail's switch on the selection and the View
// menu's group (S4-2a rewrote the old anchor, `TodayDetail(…)`, into that switch; PR #58 round 1).
test("a screen slice computes plain: a new view, a sidebar case and its shortcut", () => {
  const base = Object.fromEntries(screenFiles.map((path) => [path, own(path)]));
  plain(base, {
    "Apps/Mac/Sources/Week/WeekView.swift": "import SwiftUI\n\nstruct WeekView: View {\n  var body: some View { Text(\"Week\") }\n}\n",
    "Apps/Mac/Sources/RootView.swift": edited(
      "Apps/Mac/Sources/RootView.swift",
      ["enum SidebarItem: Hashable {\n", "enum SidebarItem: Hashable {\n  case week\n"],
      [
        "      List(selection: $model.selection) {\n",
        '      List(selection: $model.selection) {\n        Label("Week", systemImage: "calendar").tag(SidebarItem.week)\n',
      ],
      ["        switch model.selection {\n", "        switch model.selection {\n        case .week: WeekView()\n"],
    ),
    "Apps/Mac/Sources/ViewCommands.swift": edited(
      "Apps/Mac/Sources/ViewCommands.swift",
      [
        "    CommandGroup(before: .sidebar) {\n",
        '    CommandGroup(before: .sidebar) {\n      Button("Week") { model.selection = .week }\n        .keyboardShortcut("2", modifiers: .command)\n',
      ],
    ),
  });
});

test("a slice that touches the held line removal computes risky", () => {
  const base = Object.fromEntries(screenFiles.map((path) => [path, own(path)]));
  risky(
    base,
    { "Apps/Mac/Sources/LineRemoval.swift": edited("Apps/Mac/Sources/LineRemoval.swift", ["        Divider()\n", "        Divider().padding(.top, 2)\n"]) },
    "a path outside the plain list",
  );
});

test("changedLines counts added and removed lines, and null for a binary change", () => {
  const text = twoCommits({}, { "fixtures/a.md": "1\n2\n3\n" });
  assert.equal(changedLines(text.git, text.from, text.to), 3);
  const binary = twoCommits({}, { "fixtures/data.bin": Buffer.from([0, 1, 2]) });
  assert.equal(changedLines(binary.git, binary.from, binary.to), null);
});
