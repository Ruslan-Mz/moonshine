import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import ObsidianAdapter

/// The budget note's `lines:` (contract §1). Every note here is invented.
@Suite struct BudgetLinesTests {
  /// The keys of one valid line item, in order; `item` changes them.
  static let base: [(String, String)] = [
    ("id", "core"), ("name", "Core"), ("emoji", "\"🧘\""), ("block", "Foundation"),
    ("state", "active"), ("budget_h_week", "2"),
  ]

  /// One line item as YAML: `changes` replaces a key's value, adds a key, or removes it (nil).
  func item(_ changes: [String: String?] = [:]) -> String {
    var pairs = Self.base.filter { changes[$0.0] == nil }
    pairs += changes.compactMap { key, value in value.map { (key, $0) } }
      .sorted { $0.0 < $1.0 }
    return pairs.enumerated().map { index, pair in
      (index == 0 ? "  - " : "    ") + "\(pair.0): \(pair.1)"
    }.joined(separator: "\n")
  }

  /// The second item every test puts next to the one it checks.
  let other = "  - id: other\n    name: Other\n    block: Life\n    state: paused"
  let otherLine = SourceLine(key: "other", name: "Other", block: "Life", state: .paused)

  /// Keys and values at their limits, all accepted.
  static let valuesAtTheirLimits: [(String, String)] = [
    ("budget_h_week", "0"), ("budget_h_week", "168"), ("budget_h_week", "1.25"),
    ("budget_h_week", "007"), ("floor_h_day", "0"), ("floor_h_day", "24"),
    ("id", String(repeating: "a-9", count: 21) + "z"), ("name", String(repeating: "ж", count: 120)),
    ("block", String(repeating: "b", count: 60)),
    ("emoji", "\"" + String(repeating: "🇮🇹", count: 8) + "\""),
    // A ZWJ family is one cluster of 25 bytes: eight stay under 256 bytes.
    ("emoji", "\"" + String(repeating: "👨‍👩‍👧‍👦", count: 8) + "\""),
    ("name", "\"a\u{301}b\""),
    ("language", "de"), ("language", "zh-Hant-TW"),
    ("language", "abcdefgh-abcdefgh-abcdefgh-abcdefgh"),
    ("omnifocus", "{tags: [\(Array(repeating: "t", count: 100).joined(separator: ", "))]}"),
    ("omnifocus", "{tags: [\(String(repeating: "t", count: 200))]}"),
  ]

  /// Keys and values each invalid on its own.
  static let invalidValues: [(String, String)] = [
    ("budget_h_week", "-1"), ("budget_h_week", "+1"), ("budget_h_week", "1e2"),
    ("budget_h_week", "0x10"), ("budget_h_week", ".nan"), ("budget_h_week", ".inf"),
    ("budget_h_week", "nan"), ("budget_h_week", "\"1,5\""), ("budget_h_week", "1."),
    ("budget_h_week", ".5"), ("budget_h_week", "168.01"), ("budget_h_week", "\"\""),
    ("budget_h_week", "[1]"), ("budget_h_week", "abc"), ("floor_h_day", "24.5"),
    ("floor_h_day", "-0"), ("id", "Core"), ("id", "a_b"), ("id", "\"\""), ("id", "[a]"),
    ("id", String(repeating: "a", count: 65)), ("name", "\"\""), ("name", "{a: 1}"),
    ("name", String(repeating: "ж", count: 121)), ("block", "\"\""),
    ("block", String(repeating: "b", count: 61)), ("emoji", "\"\""),
    ("emoji", "\"" + String(repeating: "🇮🇹", count: 9) + "\""), ("state", "Active"),
    ("state", "done"), ("foundation", "yes"), ("foundation", "True"), ("foundation", "1"),
    ("language", "e"), ("language", "en_US"), ("language", "toolongtag"), ("language", "en-"),
    ("language", "abcdefgh-abcdefgh-abcdefgh-abcdef-ab"), ("parent", "[a]"),
    // One cluster each, over the byte cap: `a` with combining marks.
    ("name", "a" + String(repeating: "\u{301}", count: 600)),
    ("block", "b" + String(repeating: "\u{301}", count: 300)),
    ("emoji", "\"🧘" + String(repeating: "\u{301}", count: 150) + "\""),
    // NUL, other C0 controls and DEL (YAML double-quoted escapes).
    ("name", "\"a\\0b\""), ("block", "\"Life\\0X\""), ("emoji", "\"\\0\""),
    ("parent", "\"[[a\\0]]\""), ("language", "\"de\\0\""), ("name", "\"a\\tb\""),
    ("block", "\"a\\nb\""), ("name", "\"a\\x7Fb\""), ("parent", "\"\\x1B[2K\""),
    ("omnifocus", "[a]"), ("omnifocus", "x"),
  ]

  func read(_ yaml: String) throws -> BudgetLines {
    BudgetLines.read(
      ScannedNote(
        path: "budget.md", frontmatter: try FrontNode.parse(yaml, limits: VaultLimits())))
  }

  func read(items: String...) throws -> BudgetLines {
    try read("moonshine: budget\nlines:\n" + items.joined(separator: "\n"))
  }

  @Test func theFixtureLinesEqualTheDemoVaultLines() throws {
    let read = try ObsidianVault(root: fixtureVault).read()
    #expect(read.lines == DemoVault.snapshot.lines)
    #expect(read.issues.isEmpty)
  }

  @Test func everyKeyIsCarriedToTheLine() throws {
    let yaml = item([
      "parent": "\"[[Practice]]\"", "foundation": "true", "floor_h_day": "1.5",
      "language": "pt-BR",
      "omnifocus": "{tags: [a, b], folders: [F], projects: [P]}",
    ])
    let lines = try read(items: yaml)
    #expect(
      lines.lines
        == .read(
          [
            SourceLine(
              key: "core", name: "Core", emoji: "🧘", block: "Foundation", state: .active,
              budgetHoursPerWeek: 2, parentLink: "[[Practice]]", tags: ["a", "b"],
              folders: ["F"], projects: ["P"], foundation: true, floorHoursPerDay: 1.5,
              language: "pt-BR")
          ], complete: true))
    #expect(lines.issues.isEmpty)
    #expect(lines.skipped == 0)
  }

  @Test(arguments: Self.valuesAtTheirLimits)
  func valuesAtTheirLimitsAreAccepted(key: String, value: String) throws {
    let lines = try read(items: item(foundationWith(key, value)), other)
    #expect(lines.issues.isEmpty)
    #expect(lines.lines.isComplete)
    #expect(lines.lines.read.count == 2)
  }

  @Test(arguments: ["emoji", "budget_h_week", "parent", "omnifocus", "foundation", "language"])
  func aNullOptionalValueIsAbsent(key: String) throws {
    let lines = try read(items: item([key: "null"]))
    #expect(lines.issues.isEmpty)
    let line = try #require(lines.lines.read.first)
    #expect(line.foundation == false && line.language == nil && line.parentLink == nil)
    #expect(line.taskRules == LineTaskRules())
    if key == "budget_h_week" { #expect(line.budgetHoursPerWeek == nil) }
    if key == "emoji" { #expect(line.emoji == nil) }
  }

  @Test(arguments: Self.invalidValues)
  func anInvalidValueSkipsItsItemAndNamesTheKey(key: String, value: String) throws {
    let lines = try read(items: item(foundationWith(key, value)), other)
    #expect(lines.lines == .read([otherLine], complete: false))
    #expect(lines.skipped == 1)
    #expect(problems(lines.issues).map(dropLine) == ["budget.md:invalidValue (lines.\(key))"])
  }

  @Test(arguments: [
    ("tags", "x"), ("tags", "[[a]]"), ("folders", "[\(String(repeating: "f", count: 201))]"),
    ("projects", "[\(Array(repeating: "p", count: 101).joined(separator: ", "))]"),
    ("tags", "[null]"), ("tags", "[\"a\\0\"]"), ("projects", "[\"a\\x7F\"]"),
    ("folders", "[f\(String(repeating: "\u{301}", count: 600))]"),
  ])
  func anInvalidTaskRuleSkipsItsItemAndNamesTheList(list: String, value: String) throws {
    let lines = try read(items: item(["omnifocus": "{\(list): \(value)}"]), other)
    #expect(lines.lines == .read([otherLine], complete: false))
    #expect(
      problems(lines.issues).map(dropLine) == ["budget.md:invalidValue (lines.omnifocus.\(list))"]
    )
  }

  @Test func aSkippedItemIsReportedOnItsOwnLine() throws {
    // `other` takes lines 4–7; a changed key moves to the end of its item, line 13.
    let lines = try read(items: other, item(["state": "done"]))
    #expect(problems(lines.issues) == ["budget.md:13:invalidValue (lines.state)"])
  }

  @Test(arguments: ["id", "name", "block", "state"])
  func aMissingRequiredKeySkipsItsItem(key: String) throws {
    for change: String? in [nil, "null"] {
      let lines = try read(items: item([key: change]), other)
      #expect(lines.lines == .read([otherLine], complete: false))
      #expect(problems(lines.issues).map(dropLine) == ["budget.md:missingKey (lines.\(key))"])
    }
  }

  @Test(arguments: ["  - core", "  - [a, b]", "  - null"])
  func anItemThatIsNotAMappingIsSkipped(yaml: String) throws {
    let lines = try read(items: yaml, other)
    #expect(lines.lines == .read([otherLine], complete: false))
    #expect(problems(lines.issues).map(dropLine) == ["budget.md:invalidValue (lines)"])
  }

  @Test func everyItemWithADuplicateIdIsSkipped() throws {
    let lines = try read(items: item(), other, item(["name": "Copy"]))
    #expect(lines.lines == .read([otherLine], complete: false))
    #expect(lines.skipped == 2)
    #expect(
      problems(lines.issues) == [
        "budget.md:4:duplicateLineId (lines.id)", "budget.md:14:duplicateLineId (lines.id)",
      ])
  }

  @Test func aFloorIsKeptOnALineThatIsNotAFoundationLine() throws {
    for foundation: String? in [nil, "false"] {
      let lines = try read(items: item(["floor_h_day": "0.5", "foundation": foundation]))
      let line = try #require(lines.lines.read.first)
      #expect(lines.lines.isComplete)
      #expect(lines.issues.isEmpty)
      #expect(!line.foundation)
      #expect(line.floorHoursPerDay == 0.5)
      #expect(line.budgetHoursPerWeek == 2)
    }
  }

  @Test func unknownKeysAreIgnored() throws {
    let lines = try read(
      items: item(["colour": "teal", "omnifocus": "{tags: [a], perspectives: x}"]))
    #expect(lines.issues.isEmpty)
    #expect(lines.lines.read.first?.taskRules.tags == ["a"])
  }

  @Test func missingLinesLeaveTheLinesUnavailable() throws {
    for yaml in ["moonshine: budget", "moonshine: budget\nlines:"] {
      let lines = try read(yaml)
      #expect(lines.lines == .unavailable)
      #expect(problems(lines.issues).map(dropLine) == ["budget.md:missingKey (lines)"])
    }
  }

  @Test(arguments: ["lines: core", "lines: {a: 1}", "lines: []"])
  func linesThatAreNotAListLeaveTheLinesUnavailable(yaml: String) throws {
    let lines = try read("moonshine: budget\n" + yaml)
    #expect(lines.lines == .unavailable)
    #expect(problems(lines.issues).map(dropLine) == ["budget.md:invalidValue (lines)"])
  }

  @Test func noValueFromTheNoteReachesAnIssue() throws {
    let secret = "planted-secret"
    let lines = try read(
      items: item(["id": "\(secret)-X", "name": nil]), item(["state": secret]),
      item(["id": "b", "budget_h_week": "\"\(secret)\""]),
      item(["id": "c", "floor_h_day": "1", "language": "\(secret)_x"]))
    // Every problem of an item is reported, so the owner can fix them in one pass.
    #expect(lines.issues.count == 5)
    #expect(!problems(lines.issues).joined().contains(secret))
  }

  @Test func theVaultReadsTheLinesOfTheBudgetNoteOnly() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("lines:\n" + other))
    try vault.write("budget.md", note("moonshine: budget\nlines:\n" + item(["state": "x"])))
    let read = try ObsidianVault(root: vault.root).read()
    #expect(read.lines == .read([], complete: false))
    #expect(read.linesSkipped == 1)
    #expect(read.lineProblems == [.invalidValue: 1])
    #expect(problems(read.issues).map(dropLine) == ["budget.md:invalidValue (lines.state)"])
  }

  @Test func theReportCountsTheLines() throws {
    let report = try ObsidianVault(root: fixtureVault).read().report
    #expect(
      Array(report.suffix(3)) == [
        "lines: 8 read · 0 skipped",
        "line problems: missingKey 0 · invalidValue 0 · duplicateLineId 0",
        "foundation lines: 1 · with a floor: 1 · with a language: 1",
      ])
    let vault = try TemporaryVault()
    try vault.write(
      "b.md",
      note(
        "moonshine: budget\nlines:\n" + item(["floor_h_day": "1"]) + "\n" + other + "\n"
          + item(["id": "x", "state": "x"])))
    #expect(
      Array(try ObsidianVault(root: vault.root).read().report.suffix(3)) == [
        "lines: 2 read · 1 skipped",
        "line problems: missingKey 0 · invalidValue 1 · duplicateLineId 0",
        "foundation lines: 0 · with a floor: 1 · with a language: 0",
      ])
  }

  @Test func theReportSaysWhenTheLinesAreUnavailable() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    #expect(try ObsidianVault(root: vault.root).read().report.contains("lines: unavailable"))
  }

  /// A foundation item with `key` set to `value`.
  func foundationWith(_ key: String, _ value: String) -> [String: String?] {
    var changes: [String: String?] = ["foundation": "true"]
    changes[key] = .some(value)
    return changes
  }

  /// `path:line:problem` without the line, for tests that do not pin it.
  func dropLine(_ problem: String) -> String {
    let parts = problem.split(separator: ":", maxSplits: 2)
    return parts.count == 3 ? "\(parts[0]):\(parts[2])" : problem
  }
}
