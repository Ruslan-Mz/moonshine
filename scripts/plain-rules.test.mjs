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
  ["docs/specs/phase-3-x.md", "# Phase 3\n"],
  ["docs/specs/notes/deep/a.md", "a note\n"],
  ["fixtures/omnifocus.snapshot.json", "{}\n"],
  ["fixtures/a/b.yaml", "a: 1\n"],
  ["fixtures/a/b.yml", "a: 1\n"],
  ["fixtures/a/b.txt", "a\n"],
  ["fixtures/.gitkeep", ""],
  ["design/copy.md", "Words.\n"],
  ["design/screens/x.md", "A screen.\n"],
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
  "design/mockups/today.html",
  "design/tokens.json",
  "design/screens/today.html",
  "docs/VISION.md",
  "docs/setup/github.md",
  "docs/spec.md",
  ".claude/agents/x.md",
  ".claude/skills/review-pr/SKILL.md",
  ".mcp.json",
  "CLAUDE.local.md",
  // P-HR: Claude Code's instructions under a plain folder stay risky, at any depth and in any case.
  "docs/specs/CLAUDE.md",
  "docs/specs/x/claude.local.md",
  "docs/specs/.claude/settings.json",
  "docs/specs/.Claude/x.md",
  "docs/specs/.mcp.json",
  "design/screens/CLAUDE.md",
  "design/.claude/agents/x.md",
  "docs/method/log.md",
  "docs/method/log/notes.md",
  ".github/workflows/ci.yml",
  "CLAUDE.md",
  "scripts/guard/merge.mjs",
  "project.yml",
  "MoonShineCore/Tests/MoonShineCoreTests/Data.json",
  // PR #63 round 1 (owner, 2026-11-17): only Markdown under docs/specs/, only data in fixtures/.
  "docs/specs/notes/a.txt",
  "docs/specs/.prettierrc.mjs",
  "docs/specs/prettier.config.js",
  "docs/specs/node_modules/x/index.js",
  "fixtures/run.sh",
  "fixtures/a/b.js",
  "fixtures/a/.gitkeep.sh",
  // A tool's config is risky wherever it sits, though its extension is data or Markdown.
  "fixtures/.prettierrc",
  "fixtures/.prettierrc.json",
  "fixtures/a/.prettierignore",
  "fixtures/prettier.config.json",
  "fixtures/.eslintrc.yml",
  "fixtures/eslint.config.json",
  "fixtures/package.json",
  "fixtures/a/package-lock.json",
  "fixtures/.npmrc",
  "fixtures/.nvmrc",
  "fixtures/tsconfig.json",
  "fixtures/a/tsconfig.base.json",
  "fixtures/jsconfig.json",
  "fixtures/.editorconfig",
  "fixtures/a/.gitattributes",
  "fixtures/.gitignore",
  "fixtures/node_modules/x/a.json",
  "fixtures/Package.JSON",
  "docs/specs/node_modules/a.md",
  "docs/specs/.prettierrc.md",
  "design/x/.eslintrc.md",
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
  risky({}, { "fixtures/run.md": "echo\n" }, "a mode", (work) => chmodSync(join(work.cwd, "fixtures", "run.md"), 0o755));
});

test("a symbolic link is risky", () => {
  risky({}, {}, "a mode", (work) => {
    mkdirSync(join(work.cwd, "fixtures"), { recursive: true });
    symlinkSync("../README.md", join(work.cwd, "fixtures", "link.md"));
  });
});

test("a binary file is risky", () => {
  risky({}, { "fixtures/data.json": Buffer.from([0, 1, 2, 0, 3]) }, "binary");
});

test("a Prettier config next to a spec file is risky; the spec file alone is plain", () => {
  plain({}, { "docs/specs/x.md": "# X\n" });
  risky({}, { "docs/specs/x.md": "# X\n", "docs/specs/.prettierrc.mjs": "export default {};\n" }, '"docs/specs/.prettierrc.mjs"');
});

// P-HR (owner, 2026-11-16): a spec change of any kind is plain, so a plain PR can record an owner
// decision; a link, an executable, a binary file or a risky path beside it still is not.
test("ticking a spec box passes", () => {
  plain({}, { [spec]: specText.replace("- [ ] **S4-2", "- [x] **S4-2").replace("  - [ ] the live", "  - [x] the live") });
});

test("a tick plus a word, an unticked box, a new and a removed line in the spec pass", () => {
  plain({}, { [spec]: specText.replace("- [ ] **S4-2 — Lines**", "- [x] **S4-2 — Lines, done**") });
  plain({ [spec]: specText.replace("- [ ] **S5**", "- [x] **S5**") }, { [spec]: specText });
  plain({}, { [spec]: specText + "\nOwner, 2026-11-16: a decision.\n" });
  plain({}, { [spec]: specText.replace("- [ ] **S5**\n", "") });
});

test("a link or an executable under docs/specs is risky", () => {
  risky({}, { "docs/specs/run.md": "echo\n" }, "a mode", (work) => chmodSync(join(work.cwd, "docs", "specs", "run.md"), 0o755));
  risky({}, {}, "a mode", (work) => symlinkSync("../../README.md", join(work.cwd, "docs", "specs", "link.md")));
});

test("a binary file under design is risky", () => {
  risky({}, { "design/x.md": Buffer.from([0, 1, 2, 0, 3]) }, "binary");
});

test("a spec change next to a risky path is risky", () => {
  risky({}, { [spec]: specText + "More.\n", "scripts/x.mjs": "x\n" }, '"scripts/x.mjs"');
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

// P-AM (owner, 2026-11-12 and 2026-11-15): `Sendable` in a one-line conformance list passes in every
// plain path; everything else that names `Sendable` stays risky.
const plainSwiftPaths = [
  "Apps/Mac/Sources/Today/Probe.swift",
  "Apps/Mac/Sources/Lines/Probe.swift",
  "MoonShineCore/Sources/MoonShineCore/Services/Overview.swift",
  "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift",
  "Apps/Mac/Tests/ProbeTests.swift",
];

for (const line of [
  "public struct LineTier: Hashable, Sendable {",
  "public enum Kind: Hashable, Sendable, CaseIterable {",
  "extension Row: Sendable {}",
  "@MainActor final class Probe: Sendable {",
  "struct Row: Sendable { // checked by the compiler",
  "public protocol Reading: Sendable {",
]) {
  for (const path of plainSwiftPaths) {
    test(`a Sendable conformance passes: ${line} in ${path}`, () => plain({}, { [path]: `${line}\n` }));
  }
}

for (const [line, kind] of [
  ["final class Box: @unchecked Sendable {", "concurrency"],
  ["final class Box: NSObject, @unchecked Sendable {", "concurrency"],
  ["struct Box<T: Sendable>: Hashable {", "concurrency"],
  ["extension Box: Hashable where T: Sendable {}", "concurrency"],
  ["let run: @Sendable () -> Void", "concurrency"],
  ["let value: any Sendable", "concurrency"],
  ["func f(_ x: some Hashable & Sendable) {}", "concurrency"],
  ["struct Row: Swift.Sendable {", "concurrency"],
  ["actor Store: Sendable {}", "concurrency"],
  ["@_spi(Probe) public struct Row: Sendable {}", "concurrency"],
  ["@_frozen public struct Row: Sendable {}", "process"],
  ["struct Row: Sendable { let p = Process() }", "concurrency"],
  ["// Sendable because nothing mutates", "concurrency"],
  ["final class Decoder: JSONDecoder, Sendable {", "concurrency"],
  ["final class PushSource: ChangeSignalSource, Sendable {", "concurrency"],
]) {
  test(`a Sendable outside a conformance list stays risky: ${line}`, () => {
    risky({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` }, kind);
    risky({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": `${line}\n` }, kind);
  });
}

test("a conformance check stays fast on a long line, and a line too long for it stays risky", () => {
  // The old pattern took about 5 s at 3,200 spaces and grew with the cube. The bound is far above a
  // working run and far below a broken one, so a slow runner cannot fail it (CLAUDE.md, "Pull requests").
  const lines = [
    `extension Row: Sendable${" ".repeat(10_000)}where T == Int {}`,
    `struct Row: ${"Hashable, ".repeat(2_000)}Sendable {`,
    `struct Row${" ".repeat(10_000)}: Sendable {`,
    `struct Row: Sendable${" ".repeat(10_000)}{`,
  ];
  for (const text of lines) {
    const started = performance.now();
    const result = classify([{ path: "Apps/Mac/Sources/Today/Probe.swift", oldMode: "000000", newMode: "100644", status: "A", binary: false, hunks: [[{ kind: "+", text }]] }], []);
    const took = performance.now() - started;
    console.log(`a ${text.length}-character declaration line: ${took.toFixed(1)} ms`);
    assert.ok(took < 2_000, `${took} ms`);
    assert.equal(result.plain, false);
  }
});

test("a conformance list split over lines stays risky", () => {
  risky({}, { "Apps/Mac/Sources/Today/Probe.swift": "struct Row:\n  Hashable, Sendable {\n}\n" }, "concurrency");
});

test("dropping Sendable leaves every other token on the line", () => {
  risky({}, { "Apps/Mac/Sources/Today/Probe.swift": "struct LineRemovalRow: Hashable, Sendable {\n" }, "line removal");
});

// `.task` that cannot be SwiftUI's modifier passes: a property chain or an enum case pattern, and a
// call on a receiver of the rules' list, in its paths (owner, 2026-11-15 and 2026-11-16). The
// modifier takes its action unlabeled (`task(priority:_:)`), so every other `.task` stays risky.
for (const line of [
  "let id = item.task.id",
  "let titles = rows.map(\\.task.title)",
  "case .task(let task): Text(task.title)",
  "case let .task(row): Text(row.title)",
  "if case .task(let row) = item { }",
]) {
  for (const path of plainSwiftPaths) {
    test(`a .task that is not the modifier passes: ${line} in ${path}`, () => plain({}, { [path]: `${line}\n` }));
  }
}

const dayLoadTests = "MoonShineCore/Tests/MoonShineCoreTests/DayLoadTests.swift";
for (const [line, passes] of [
  ["TableRow(TodayTableRow.task(item))", ["Apps/Mac/Sources/Today/Probe.swift", "Apps/Mac/Tests/ProbeTests.swift"]],
  ['world.task("Etude", line: violin)', ["MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift", "Apps/Mac/Tests/ProbeTests.swift", dayLoadTests]],
  ["let group = world.task(\n  \"Group\", line: violin, estimate: 40)", ["MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift", "Apps/Mac/Tests/ProbeTests.swift", dayLoadTests]],
  ["let row = TestWorld.task(id: 1)", ["MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift", "Apps/Mac/Tests/ProbeTests.swift", dayLoadTests]],
  ["let over = R.load([event], tasks: [R.task(R.at(13, 45), estimate: 30)])", [dayLoadTests]],
  ["let task = RigaDay.task(RigaDay.at(10), estimate: 30)", [dayLoadTests]],
]) {
  for (const path of [...plainSwiftPaths, dayLoadTests]) {
    const expected = passes.includes(path) ? "passes" : "stays risky";
    test(`a .task on a listed receiver ${expected} in ${path}: ${line.split("\n")[0]}`, () => {
      if (passes.includes(path)) plain({}, { [path]: `${line}\n` });
      else risky({}, { [path]: `${line}\n` }, "concurrency");
    });
  }
}

for (const line of [
  ".task { }",
  ".task(reload)",
  "  .task(reload)",
  ".task({ work() })",
  "content.task(reload)",
  "case .view(let V): return V.task(reload)",
  "for Row in views { result.append(AnyView(Row.task(reload))) }",
  "view.task(store.pollForever)",
  'content.task("poll")',
  'huge.task("Big", line: .lifeOps, flagged: true, estimate: .max)',
  "self.world.task(reload)",
  "let row = R.task(reload)",
  ".task(id: model.selection) { }",
  ".task(priority: .low) { }",
  ".task(name: \"poll\") { }",
  "Text(title).task { }",
  "let run = view.task",
]) {
  test(`the .task modifier stays risky: ${line}`, () => {
    risky({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` }, "concurrency");
    risky({}, { "Apps/Mac/Tests/ProbeTests.swift": `${line}\n` }, "concurrency");
    risky({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": `${line}\n` }, "concurrency");
  });
}

test("a multi-line .task( stays risky unless its receiver is listed", () => {
  for (const path of ["Apps/Mac/Tests/ProbeTests.swift", "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift"]) {
    risky({}, { [path]: "let hosted = content.task(\n  priority: .low) { reload() }\n" }, "concurrency");
    risky({}, { [path]: "Text(title).task(\n  id: key) { }\n" }, "concurrency");
    risky({}, { [path]: ".task(\n  id: key) { }\n" }, "concurrency");
  }
  risky({}, { "Apps/Mac/Sources/Today/Probe.swift": 'let row = world.task(\n  "Etude", line: violin)\n' }, "concurrency");
});

// `typealias X = Y` in a test file passes when `Y` is one name and no token needs text after it
// (owner, 2026-11-15). The names are read from the rules' own source: a capitalised name followed
// in a pattern by `\s` or `\(`, so a token added later keyed on a type name is covered here too.
const ruleSource = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "guard", "plain-rules.mjs"), "utf8");
const namesNeedingText = [...new Set([...ruleSource.matchAll(/(?<![A-Za-z0-9_])([A-Z][A-Za-z0-9_]*)\\{1,2}(?:s\*|\()/g)].map((m) => m[1]))];

test("the rules name the type names whose tokens need text after them", () => {
  for (const name of ["Task", "Link", "Bundle", "URL"]) assert.ok(namesNeedingText.includes(name), `${name}: ${namesNeedingText.join(", ")}`);
});

for (const name of namesNeedingText) {
  test(`a typealias of ${name} stays risky in a test file`, () => {
    const result = judge({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": `  typealias X = ${name}\n` });
    assert.equal(result.plain, false, `typealias X = ${name} computed plain`);
  });
}

for (const line of ["  typealias W = TestWorld", "typealias R = RigaDay", "  private typealias W = TestWorld // short"]) {
  test(`a typealias of one name passes in a test file: ${line}`, () => {
    plain({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": `${line}\n` });
    plain({}, { "Apps/Mac/Tests/ProbeTests.swift": `${line}\n` });
  });
}

for (const [line, kind] of [
  ["typealias P = Process", "process"],
  ["typealias U = Foundation.URL", "process"],
  ["typealias Box<T> = Array<T>", "process"],
  ["typealias Pair = (Int, Int)", "process"],
  ["typealias Run = () -> Void", "process"],
]) {
  test(`a typealias stays risky in a test file: ${line}`, () => {
    risky({}, { "MoonShineCore/Tests/MoonShineCoreTests/ProbeTests.swift": `${line}\n` }, kind);
  });
}

test("a typealias stays risky outside test files", () => {
  risky({}, { "Apps/Mac/Sources/Today/Probe.swift": "typealias W = TestWorld\n" }, "process");
  risky({}, { "MoonShineCore/Sources/MoonShineCore/Services/Overview.swift": "typealias W = TestWorld\n" }, "process");
});

test("a held line removal in a test file stays risky", () => {
  risky({}, { "Apps/Mac/Tests/ProbeTests.swift": "workspace.issues.append(.lineRemovalHeld([held.key]))\n" }, "line removal");
});

// Gaps added in passing (P-AM; owner, 2026-11-15), in sources and in tests.
for (const [line, kind] of [
  ["let lock = NSLock()", "concurrency"],
  ["let lock = NSRecursiveLock()", "concurrency"],
  ["let ready = NSCondition()", "concurrency"],
  ["let gate = NSConditionLock(condition: 0)", "concurrency"],
  ["_ = pthread_create(&thread, nil, body, nil)", "concurrency"],
  ["var lock = os_unfair_lock()", "concurrency"],
  ["MainActor.assumeIsolated { run() }", "concurrency"],
  ["func f(on a: isolated (any Actor)) {}", "concurrency"],
  ["@concurrent func work() async {}", "concurrency"],
  ["let link = NSXPCConnection(serviceName: name)", "process"],
  ["let peer = xpc_connection_create(name, nil)", "process"],
  ["let event = NSAppleEventDescriptor(eventClass: a, eventID: b, targetDescriptor: c, returnID: 0, transactionID: 0)", "process"],
  ["let manager = NSAppleEventManager.shared()", "process"],
  ["NSRunningApplication.current.terminate()", "process"],
  ["_ = setenv(name, value, 1)", "process"],
  ["_ = unsetenv(name)", "process"],
  ["_ = putenv(entry)", "process"],
  ["_ = chdir(path)", "process"],
  ["_ = mkdir(path, 0o700)", "storage"],
  ["_ = mkdirat(fd, path, 0o700)", "storage"],
  ["_ = symlink(target, path)", "storage"],
  ["_ = link(from, to)", "storage"],
  ["_ = chmod(path, 0o600)", "storage"],
  ["_ = fchmod(fd, 0o600)", "storage"],
  ["_ = copyfile(from, to, nil, 0)", "storage"],
  ["_ = clonefile(from, to, 0)", "storage"],
  ["_ = setxattr(path, name, value, size, 0, 0)", "storage"],
  ["_ = removexattr(path, name, 0)", "storage"],
  ["let fd = mkstemp(&template)", "storage"],
  ["let dir = mkdtemp(&template)", "storage"],
  ["let dir = opendir(path)", "storage"],
  ["let entry = readdir(dir)", "storage"],
  ["_ = scandir(path, &list, nil, nil)", "storage"],
  ["let walk = fts_open(paths, 0, nil)", "storage"],
  ["_ = realpath(path, nil)", "storage"],
  ["_ = Darwin.mkdir(path, 0o700)", "storage"],
  ["let wrapper = try FileWrapper(url: url)", "storage"],
  ["NSUbiquitousKeyValueStore.default.set(value, forKey: key)", "storage"],
  ["DocumentGroup(newDocument: Note()) { _ in EmptyView() }", "storage"],
  ["struct Note: FileDocument {", "storage"],
  ["final class Book: NSDocument {", "storage"],
  ["let service = NetService(domain: \"\", type: kind, name: name)", "URL"],
  ["Stream.getStreamsToHost(withName: host, port: 80, inputStream: &a, outputStream: &b)", "URL"],
  ["let connection = NSURLConnection(request: request, delegate: self)", "URL"],
  ["let activity = NSUserActivity(activityType: kind)", "drag, pasteboard or sharing"],
  [".userActivity(kind) { _ in }", "drag, pasteboard or sharing"],
  [".onContinueUserActivity(kind) { _ in }", "drag, pasteboard or sharing"],
  [".handlesExternalEvents(preferring: [], allowing: [\"*\"])", "drag, pasteboard or sharing"],
  // Round 1 (PR #59): the C-call siblings, sockets, selectors, file reads and markdown links.
  ["let fd = openat(AT_FDCWD, path, O_CREAT | O_WRONLY, 0o644)", "storage"],
  ["_ = fchdir(fd)", "process"],
  ["_ = chown(path, 0, 0)", "storage"],
  ["_ = lchown(path, 0, 0)", "storage"],
  ["_ = fchown(fd, 0, 0)", "storage"],
  ["_ = fchownat(fd, path, 0, 0, 0)", "storage"],
  ["_ = lchmod(path, 0o600)", "storage"],
  ["_ = mkfifo(path, 0o600)", "storage"],
  ["_ = mkfifoat(fd, path, 0o600)", "storage"],
  ["_ = mknod(path, 0o600, 0)", "storage"],
  ["let fd = mkostemp(&template, 0)", "storage"],
  ["let fd = mkostemps(&template, 4, 0)", "storage"],
  ["let dir = fdopendir(fd)", "storage"],
  ["_ = readdir_r(dir, &entry, &result)", "storage"],
  ["_ = nftw(path, visit, 8, 0)", "storage"],
  ["_ = ftw(path, visit, 8)", "storage"],
  ["_ = utimes(path, nil)", "storage"],
  ["_ = lutimes(path, nil)", "storage"],
  ["_ = futimens(fd, nil)", "storage"],
  ["_ = utimensat(fd, path, nil, 0)", "storage"],
  ["_ = fclonefileat(fd, dirfd, path, 0)", "storage"],
  ["CFStreamCreatePairWithSocketToHost(nil, host as CFString, 443, &readStream, &writeStream)", "URL"],
  ["var writeStream: Unmanaged<CFWriteStream>?", "URL"],
  ["_ = CFWriteStreamWrite(output, bytes, bytes.count)", "URL"],
  ["let read: Unmanaged<CFReadStream>? = nil", "URL"],
  ["let socket = CFSocketCreate(nil, 0, 0, 0, 0, nil, nil)", "URL"],
  ["let service = CFNetServiceCreate(nil, domain, kind, name, 0)", "URL"],
  ["let fd = socket(AF_INET, SOCK_STREAM, 0)", "URL"],
  ["_ = connect(fd, address, size)", "URL"],
  ["_ = bind(fd, address, size)", "URL"],
  ["_ = sendto(fd, bytes, count, 0, address, size)", "URL"],
  ["self.performSelector(inBackground: #selector(work), with: nil)", "concurrency"],
  ["performSelector(onMainThread: #selector(work), with: nil, waitUntilDone: false)", "concurrency"],
  ["perform(#selector(work), with: nil, afterDelay: 1)", "concurrency"],
  ["let reps = NSImageRep.imageReps(withContentsOf: noteURL)", "storage"],
  ["let reps = NSImageRep.imageReps(withContentsOfFile: path)", "storage"],
  ["let text = try NSAttributedString(url: noteURL, options: [:], documentAttributes: nil)", "storage"],
  ["let text = NSAttributedString(path: path, documentAttributes: nil)", "storage"],
  ["let data = CGDataProvider(url: url as CFURL)", "storage"],
  ["let data = CGDataProvider(filename: path)", "storage"],
  ["let pdf = CGPDFDocument(url as CFURL)", "storage"],
  ["let image = CGImageSourceCreateWithURL(url as CFURL, nil)", "storage"],
  ["let folder = URL.applicationSupportDirectory", "storage"],
  ["let folder = URL.documentsDirectory", "storage"],
  ["let url = URL(fileURLWithFileSystemRepresentation: path, isDirectory: false, relativeTo: nil)", "storage"],
  ['Text(.init("[Open](https://example.com/?q=\\(row.title))"))', "URL"],
  ['Text(try! AttributedString(markdown: text))', "URL"],
  ['Text("[Mail](mailto:someone)")', "URL"],
  ["s.link = URL(string: address)", "URL"],
]) {
  test(`a risky token added in P-AM is risky: ${line}`, () => {
    risky({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` }, kind);
    risky({}, { "Apps/Mac/Tests/ProbeTests.swift": `${line}\n` }, kind);
  });
}

for (const line of [
  "NavigationLink(value: item) { }",
  "let unlinked = rows.unlink",
  "items.link(to: other)",
  "let lockedOut = false",
  "let dirName = folder.name",
  "Text(isolatedCount.formatted())",
  "items.connect(to: other)",
  "let socketCount = rows.count",
  "let contents = item.contents",
  "let row = rows[index](value)",
  'Text("[draft]")',
  "let linked = row.isLinked",
]) {
  test(`a harmless line next to a P-AM token passes: ${line}`, () => {
    plain({}, { "Apps/Mac/Sources/Today/Probe.swift": `${line}\n` });
  });
}

test("a markdown link in a String Catalog's value is risky", () => {
  const catalog = "Apps/Mac/Resources/Localizable.xcstrings";
  const value = (text) => `{\n  "strings" : {\n    "Open" : {\n      "localizations" : { "en" : { "stringUnit" : { "value" : "${text}" } } }\n    }\n  }\n}\n`;
  risky({}, { [catalog]: value("[Open](https://example.com)") }, "URL");
  plain({}, { [catalog]: value("Open [this] one") });
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

// S4-2a as merged (PR #58), read from the repository's history: its Core and test files compute
// plain under P-AM's rules, except the test of the held line removal; the rest stays risky for its
// own reasons. CI's docs job checks out full history (fetch-depth: 0).
const s42a = { base: "5728d4f8c0aa5f8097f971f0a240c581f27b0b89", head: "3d398b86d3562164bc9b17f53540a68c63456fc9" };
const repoGit = (args, options = {}) => {
  const result = spawnSync("git", args, { cwd: repoRoot, encoding: "utf8", maxBuffer: 1 << 30, ...options });
  assert.equal(result.status, 0, `git ${args.join(" ")}\n${result.stderr}`);
  return result.stdout;
};

test("S4-2a: its Core and test files compute plain; the rest stays risky for its own reasons", () => {
  for (const commit of [s42a.base, s42a.head]) {
    const found = spawnSync("git", ["cat-file", "-e", `${commit}^{commit}`], { cwd: repoRoot });
    assert.equal(found.status, 0, `the S4-2a commit ${commit} is missing: this test needs the full history (git fetch --unshallow)`);
  }
  const changes = readChanges(repoGit, s42a.base, s42a.head);
  const judged = Object.fromEntries(changes.map((change) => [change.path, classify([change], []).reasons]));
  for (const path of [
    "MoonShineCore/Sources/MoonShineCore/Services/Overview.swift",
    "MoonShineCore/Tests/MoonShineCoreTests/LinesTests.swift",
    "MoonShineCore/Tests/MoonShineCoreTests/TestWorld.swift",
    "Apps/Mac/Tests/TodayScreenTests.swift",
    "Apps/Mac/Sources/Lines/LinesFormat.swift",
    "Apps/Mac/Sources/Lines/LinesScreen.swift",
    "Apps/Mac/Sources/Lines/LinesView.swift",
    "Apps/Mac/Sources/Lines/Sparkline.swift",
    "Apps/Mac/Sources/RootView.swift",
    "Apps/Mac/Sources/ViewCommands.swift",
    "Apps/Mac/Resources/Localizable.xcstrings",
    "docs/method/forecast.md",
    "docs/method/log/2026-11.md",
    // P-HR: specs and design notes are plain.
    spec,
    "design/README.md",
    "design/components.md",
    "design/copy.md",
    "design/demo-data.md",
    "design/principles.md",
    "design/screens/line-detail.md",
    "design/screens/lines.md",
    "design/screens/week.md",
  ]) {
    assert.deepEqual(judged[path], [], `${path}: ${judged[path]?.join("; ")}`);
  }
  assert.deepEqual(judged["Apps/Mac/Tests/LinesScreenTests.swift"], ["a risky token (line removal) in or next to a change: \"Apps/Mac/Tests/LinesScreenTests.swift\""]);
  const byPath = Object.entries(judged).filter(([, reasons]) => reasons.some((reason) => reason.startsWith("a path outside the plain list")));
  assert.deepEqual(
    byPath.map(([path]) => path).sort(),
    [
      "Adapters/Tests/OmniFocusAdapterTests/DemoDataGoldenTests.swift",
      "Adapters/Tests/OmniFocusAdapterTests/OverviewSmokeTests.swift",
      "Apps/Mac/Sources/LineRemoval.swift",
      "scripts/plain-rules.test.mjs",
    ],
  );
  assert.equal(Object.keys(judged).length, 27);
  assert.equal(classify(changes, []).plain, false);
});
