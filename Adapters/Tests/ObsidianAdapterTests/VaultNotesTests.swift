import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import ObsidianAdapter

@Suite struct VaultNotesTests {
  let calendar = Calendar.iso8601(in: moscow)

  func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  /// One note at `path` in a vault of its own.
  func read(_ yaml: String, at path: String = "n.md") throws -> VaultRead {
    let vault = try TemporaryVault()
    try vault.write(path, note(yaml))
    return try ObsidianVault(root: vault.root, timeZone: moscow).read()
  }

  /// The problems of notes as notes: not the vault-wide "no budget note", not `lines:`.
  func noteProblems(_ read: VaultRead) -> [String] {
    problems(
      read.issues.filter {
        if case .vault(_, _, let problem) = $0 {
          problem.key?.hasPrefix("notes.") == true
        } else {
          false
        }
      })
  }

  /// The note is skipped with exactly this problem, and its path is kept as unread.
  func expectSkipped(_ yaml: String, _ problem: String, at path: String = "n.md") throws {
    let read = try read(yaml, at: path)
    #expect(read.notes.isEmpty)
    #expect(noteProblems(read) == ["\(path):\(problem)"])
    #expect(read.unread == VaultUnread(paths: [path], artifactLists: [], notRecognised: []))
  }

  @Test func theFixtureNotesEqualTheDemoVaultNotes() throws {
    let read = try ObsidianVault(root: fixtureVault, timeZone: moscow).read()
    #expect(read.notes == DemoVault.snapshot.notes)
    #expect(read.unread == .nothing)
    #expect(read.issues.isEmpty)
  }

  // MARK: Fields

  @Test func everyFieldIsCarriedToTheNote() throws {
    let read = try read(
      """
      title: Plan
      type: "month_plan, journal"
      parent: "[[Folder/Quarter|Q]]"
      line: violin
      status: living
      scale: month
      period: 2026-10
      """)
    #expect(
      read.notes == [
        SourceNote(
          path: "n.md", title: "Plan", type: "month_plan", scale: .month,
          period: Horizon(scale: .month, start: day(2026, 10, 1), end: day(2026, 11, 1)),
          parentLink: "[[Folder/Quarter|Q]]", lineKey: "violin", status: "living")
      ])
    #expect(noteProblems(read).isEmpty)
    #expect(read.unread == .nothing)
  }

  @Test func aNoteWithoutATitleTakesItsFileName() throws {
    let read = try read("type: lifetime\ntitle:", at: "Notes/Whole life.MD")
    #expect(read.notes.map(\.title) == ["Whole life"])
    #expect(read.notes.map(\.scale) == [.lifetime])
    #expect(read.notes.map(\.period) == [nil])
  }

  @Test func aFileNameOverTheTitleCapsSkipsTheNote() throws {
    let name = String(repeating: "a", count: 201) + ".md"
    try expectSkipped("type: lifetime", "2:invalidValue (notes.title)", at: name)
  }

  static let long = String(repeating: "a", count: 61)
  static let invalidValues: [(String, String)] = [
    ("title: \"\"", "title"), ("title: [a]", "title"),
    ("title: \(long)\(long)\(long)\(long)", "title"),
    // 100 characters, over 1 KiB.
    (
      "title: \"\(String(repeating: "e\u{301}\u{302}\u{303}\u{304}\u{305}", count: 100))\"", "title"
    ),
    ("title: \"a\\u0007b\"", "title"),
    ("parent: \"\(String(repeating: "a", count: 1025))\"", "parent"),
    ("parent: \"a\\0b\"", "parent"), ("parent: [[a]]", "parent"),
    ("line: Violin", "line"), ("line: \(long)aaaa", "line"), ("line: \"\"", "line"),
    ("status: \"\"", "status"), ("status: \(long)", "status"), ("status: {a: b}", "status"),
    ("scale: decade", "scale"), ("scale: [year]", "scale"),
  ]

  @Test(arguments: invalidValues)
  func anInvalidValueSkipsTheNote(yaml: String, key: String) throws {
    try expectSkipped("type: lifetime\n\(yaml)", "3:invalidValue (notes.\(key))")
  }

  @Test func everyProblemOfANoteIsReported() throws {
    let read = try read("type: year_artifacts\ntitle: \"\"\nline: X\nyear: 26")
    #expect(
      noteProblems(read) == [
        "n.md:3:invalidValue (notes.title)", "n.md:4:invalidValue (notes.line)",
        "n.md:5:invalidValue (notes.year)",
      ])
  }

  @Test func aProblemNeverCarriesAValue() throws {
    let secret = "planted-secret"
    let read = try read("type: month_plan\nmonth: \(secret)\nstatus: [\(secret)]")
    #expect(read.issues.count == 3)
    #expect(!"\(read.issues)".contains(secret))
    #expect(!read.report.joined().contains(secret))
  }

  // MARK: Which notes are read

  @Test func notesOfAnotherTypeAndNotesWithoutFrontmatterAreNotRecognised() throws {
    let vault = try TemporaryVault()
    try vault.write("other.md", note("type: journal"))
    try vault.write("untyped.md", note("title: x"))
    try vault.write("list.md", note("type: [month_plan]"))
    try vault.write("second.md", note("type: \"journal, month_plan\""))
    try vault.write("case.md", note("type: Month_plan"))
    try vault.write("plain.md", "# No frontmatter\n")
    try vault.write("empty.md", "")
    try vault.write("shifted.md", "\n" + note("type: lifetime"))
    try vault.write("ok.md", note("type: lifetime"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.notes.map(\.path) == ["ok.md"])
    #expect(
      read.unread
        == VaultUnread(
          paths: [], artifactLists: [],
          notRecognised: [
            "other.md", "untyped.md", "list.md", "second.md", "case.md", "plain.md", "empty.md",
            "shifted.md",
          ]))
    #expect(noteProblems(read).isEmpty)
  }

  @Test func theBudgetNoteIsStoredWhateverItsType() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: budget\ntype: \"strategic, x\"\nscale: year"))
    try vault.write("b.md", note("moonshine: budget\nperiod: 2026-W53"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .ambiguous(marked: 2))
    #expect(read.lines == .unavailable)
    #expect(
      read.notes == [
        SourceNote(path: "a.md", title: "a", type: "strategic"),
        SourceNote(
          path: "b.md", title: "b", scale: .week,
          period: Horizon(scale: .week, start: day(2026, 12, 28), end: day(2027, 1, 4))),
      ])
    #expect(read.notesByType == [VaultNotes.budgetName: 2])
  }

  @Test(arguments: ["type: [a]", "type: \(long)", "type: \"a\\u0001\""])
  func aBudgetNoteWithAnInvalidTypeIsSkippedAsANote(type: String) throws {
    try expectSkipped("moonshine: budget\n\(type)", "3:invalidValue (notes.type)")
  }

  @Test func rejectedNotesAndWhatTheWalkSkippedAreKeptAsUnread() throws {
    let vault = try TemporaryVault()
    let outside = try TemporaryVault()
    try outside.write("x.md", note("type: lifetime"))
    try vault.write("broken.md", note("type: lifetime\na: [unclosed"))
    try vault.write("open.md", "---\ntype: lifetime\n")
    try vault.write("Locked/in.md", note("type: lifetime"))
    try vault.write("secret.md", note("type: lifetime"))
    try vault.link("Linked", to: outside.root)
    try vault.link("linked.md", to: outside.root.appending(path: "x.md"))
    let locked = vault.root.appending(path: "Locked").path
    let secret = vault.root.appending(path: "secret.md").path
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: secret)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked)
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret)
    }
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.notes.isEmpty)
    #expect(
      read.unread
        == VaultUnread(
          paths: ["broken.md", "open.md", "Locked", "secret.md", "Linked", "linked.md"],
          artifactLists: [], notRecognised: []))
    #expect(read.unread.covers("Locked/in.md"))
  }

  // MARK: Scale and period

  func period(_ yaml: String, at path: String = "n.md") throws -> Horizon? {
    let read = try read(yaml, at: path)
    #expect(noteProblems(read).isEmpty)
    #expect(read.notes.count == 1)
    return read.notes.first?.period
  }

  @Test func anExplicitPeriodIsReadInEveryShape() throws {
    #expect(
      try period("type: focus\nperiod: 2026-W01")
        == Horizon(scale: .week, start: day(2025, 12, 29), end: day(2026, 1, 5)))
    #expect(
      try period("type: focus\nperiod: 2026-02")
        == Horizon(scale: .month, start: day(2026, 2, 1), end: day(2026, 3, 1)))
    #expect(
      try period("type: focus\nperiod: 2026-Q4")
        == Horizon(scale: .quarter, start: day(2026, 10, 1), end: day(2027, 1, 1)))
    #expect(
      try period("type: month_plan\nperiod: 2026\nmonth: nonsense")
        == Horizon(scale: .year, start: day(2026, 1, 1), end: day(2027, 1, 1)))
    #expect(
      try period("type: lifetime\nperiod: 2026..2030")
        == Horizon(scale: .years(5), start: day(2026, 1, 1), end: day(2031, 1, 1)))
    #expect(
      try period("type: lifetime\nperiod: 1900..2099\nscale: years")
        == Horizon(scale: .years(200), start: day(1900, 1, 1), end: day(2100, 1, 1)))
  }

  @Test func aListOfTargetYearsGivesNoScaleAndNoPeriod() throws {
    let read = try read("type: horizon_corridor\nperiod: \"2036, 2041,2051\"\nperiod_start: x")
    #expect(read.notes == [SourceNote(path: "n.md", title: "n", type: "horizon_corridor")])
    #expect(noteProblems(read).isEmpty)
  }

  @Test(arguments: [
    "2026-13", "2026-00", "2026-02-30", "2026-10-01", "2025-W53", "2026-W00", "2026-W54",
    "2026-Q5", "2026-Q0", "0000", "1899", "2200", "99999", "26", "202６", "２０２６",
    "2026..2025", "1900..2100", "2026..", "2026...2030", "2026..2030..2040", "2026,", "2026,x",
    "2026,1899", "October", "[2026]", " 2026 ", "2026-w10", "2026-q1", "2026-1", "+2026",
  ])
  func aPeriodInAnotherShapeIsInvalid(text: String) throws {
    try expectSkipped("type: lifetime\nperiod: \"\(text)\"", "3:invalidValue (notes.period)")
  }

  @Test func theLastISOWeekMustExistInItsYear() throws {
    #expect(try period("type: focus\nperiod: 2026-W53")?.start == day(2026, 12, 28))
    #expect(try period("type: focus\nperiod: 2024-W52")?.end == day(2024, 12, 30))
    #expect(WrittenDate.parse("2025-W53", calendar: calendar) == nil)
    #expect(WrittenDate.parse("2024-02-29", calendar: calendar)?.end == day(2024, 3, 1))
    #expect(WrittenDate.parse("2026-02-29", calendar: calendar) == nil)
  }

  @Test func aMonthPlanTakesItsMonthThenItsPeriodStart() throws {
    let october = Horizon(scale: .month, start: day(2026, 10, 1), end: day(2026, 11, 1))
    #expect(try period("type: month_plan\nmonth: 2026-10\nperiod_start: nonsense") == october)
    #expect(try period("type: month_plan\nmonth:\nperiod_start: 2026-10-17") == october)
    #expect(try period("type: month_plan\nperiod_start: 2026-10") == october)
    try expectSkipped("type: month_plan\nmonth: 2026-10-01", "3:invalidValue (notes.month)")
    try expectSkipped("type: month_plan\nmonth: October", "3:invalidValue (notes.month)")
    try expectSkipped(
      "type: month_plan\nperiod_start: 2026", "3:invalidValue (notes.period_start)")
    try expectSkipped("type: month_plan\nyear: 2026", "2:missingKey (notes.period)")
  }

  @Test func aQuarterFocusTakesItsQuarterThenItsPeriodStart() throws {
    let fourth = Horizon(scale: .quarter, start: day(2026, 10, 1), end: day(2027, 1, 1))
    #expect(try period("type: quarter_focus\nquarter: 2026-Q4\nperiod_start: x") == fourth)
    #expect(try period("type: quarter_focus\nperiod_start: 2026-11-30") == fourth)
    #expect(try period("type: quarter_focus\nperiod_start: 2026-12") == fourth)
    try expectSkipped("type: quarter_focus\nquarter: Q4 2026", "3:invalidValue (notes.quarter)")
    try expectSkipped("type: quarter_focus\nquarter: 4", "3:invalidValue (notes.quarter)")
    try expectSkipped(
      "type: quarter_focus\nperiod_start: 2026-Q4", "3:invalidValue (notes.period_start)")
    try expectSkipped("type: quarter_focus", "2:missingKey (notes.period)")
  }

  @Test func aYearNoteTakesItsYear() throws {
    #expect(
      try period("type: year_artifacts\nyear: 2026")
        == Horizon(scale: .year, start: day(2026, 1, 1), end: day(2027, 1, 1)))
    try expectSkipped("type: year_artifacts\nyear: 2026-01", "3:invalidValue (notes.year)")
    try expectSkipped("type: year_artifacts\nyear: [2026]", "3:invalidValue (notes.year)")
    try expectSkipped("type: year_artifacts", "2:missingKey (notes.period)", at: "2026.md")
  }

  @Test(arguments: ["yearly-goals", "focus"])
  func aLegacyNoteTakesItsYearThenTheYearInItsFileName(type: String) throws {
    let year = Horizon(scale: .year, start: day(2025, 1, 1), end: day(2026, 1, 1))
    #expect(try period("type: \(type)\nyear: 2025", at: "Goals 2031.md") == year)
    #expect(try period("type: \(type)", at: "J/12345 0007 20251 Goals-2025 2031.md") == year)
    try expectSkipped("type: \(type)\nyear: 25", "3:invalidValue (notes.year)", at: "2025.md")
    // Neither: read with the scale alone. A `focus` note without a year is the current one,
    // by design; only a `yearly-goals` note reports the missing year.
    let read = try read("type: \(type)", at: "2025 12/Goals 20251.md")
    #expect(
      read.notes == [
        SourceNote(path: "2025 12/Goals 20251.md", title: "Goals 20251", type: type, scale: .year)
      ])
    #expect(
      noteProblems(read)
        == (type == "focus" ? [] : ["2025 12/Goals 20251.md:2:missingKey (notes.period)"]))
    #expect(read.unread == .nothing)
  }

  @Test func aCorridorRunsFromItsStartToTheDayAfterItsEnd() throws {
    #expect(
      try period("type: horizon_corridor\nperiod_start: 2026\nperiod_end: 2026")
        == Horizon(scale: .years(1), start: day(2026, 1, 1), end: day(2027, 1, 1)))
    #expect(
      try period("type: horizon_corridor\nperiod_start: 2026-09-15\nperiod_end: 2030-06-30")
        == Horizon(scale: .years(5), start: day(2026, 9, 15), end: day(2030, 7, 1)))
    #expect(
      try period("type: horizon_corridor\nperiod_start: 2026-09\nperiod_end: 2030-02")
        == Horizon(scale: .years(5), start: day(2026, 9, 1), end: day(2030, 3, 1)))
    #expect(try period("type: horizon_corridor\nperiod_start: 1900\nperiod_end: 2099") != nil)
  }

  @Test(arguments: [
    ("period_start: 2026-W01\nperiod_end: 2030", "3:invalidValue (notes.period_start)"),
    ("period_start: 2026\nperiod_end: 2030-Q1", "4:invalidValue (notes.period_end)"),
    ("period_start: 2030\nperiod_end: 2026", "4:invalidValue (notes.period_end)"),
    ("period_start: 2026-06-01\nperiod_end: 2026-03", "4:invalidValue (notes.period_end)"),
    ("period_start: 1900\nperiod_end: 2100", "4:invalidValue (notes.period_end)"),
  ])
  func aCorridorWithAnInvalidPeriodKeyIsSkipped(yaml: String, problem: String) throws {
    try expectSkipped("type: horizon_corridor\n\(yaml)", problem)
  }

  @Test func aCorridorWithOneInvalidPeriodKeyIsSkippedAndTheOtherKeyIsNamedToo() throws {
    let read = try read("type: horizon_corridor\nhorizons: [2036]\nperiod_end: 2030-02-30")
    #expect(read.notes.isEmpty)
    #expect(
      noteProblems(read) == [
        "n.md:4:invalidValue (notes.period_end)", "n.md:2:missingKey (notes.period_start)",
      ])
    #expect(read.unread.paths == ["n.md"])
  }

  @Test(arguments: [
    ("horizons: [2036, 2041]", [String]()),
    ("title: x", ["n.md:2:missingKey (notes.period)"]),
    ("horizons:", ["n.md:2:missingKey (notes.period)"]),
    ("period_start: 2026", ["n.md:2:missingKey (notes.period_end)"]),
    ("period_end: 2030\nhorizons: [2036]", ["n.md:2:missingKey (notes.period_start)"]),
  ])
  func aCorridorWithoutBothPeriodKeysIsReadWithoutAPeriod(
    yaml: String, problems: [String]
  ) throws {
    let read = try read("type: horizon_corridor\n\(yaml)")
    #expect(read.notes.map(\.scale) == [nil])
    #expect(read.notes.map(\.period) == [nil])
    #expect(noteProblems(read) == problems)
    #expect(read.unread == .nothing)
  }

  @Test func anExplicitScaleMustAgreeWithThePeriod() throws {
    #expect(try period("type: month_plan\nmonth: 2026-10\nscale: month")?.scale == .month)
    #expect(try period("type: horizon_corridor\nperiod: 2026..2030\nscale: years") != nil)
    try expectSkipped(
      "type: month_plan\nmonth: 2026-10\nscale: quarter", "4:invalidValue (notes.scale)")
    try expectSkipped("type: focus\nperiod: 2026-Q1\nscale: year", "4:invalidValue (notes.scale)")
    try expectSkipped("type: lifetime\nscale: year", "3:invalidValue (notes.scale)")
    // No scale of the reader's own to check against: the word is valid and nothing is stored.
    let read = try read("type: horizon_corridor\nhorizons: [2036]\nscale: years")
    #expect(read.notes.map(\.scale) == [nil])
    #expect(noteProblems(read).isEmpty)
  }

  @Test func aPeriodStartsAtMidnightInTheVaultsTimeZone() throws {
    let vault = try TemporaryVault()
    try vault.write("n.md", note("type: year_artifacts\nyear: 2026"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let inTokyo = try ObsidianVault(root: vault.root, timeZone: tokyo).read().notes.first
    let inMoscow = try ObsidianVault(root: vault.root, timeZone: moscow).read().notes.first
    #expect(inMoscow?.period?.start == day(2026, 1, 1))
    #expect(inTokyo?.period?.start == day(2026, 1, 1).addingTimeInterval(-6 * 3600))
  }

  // MARK: Live check

  @Test func theReportCountsNotesByTypeAndProblemsByKindAndKey() throws {
    let vault = try TemporaryVault()
    try vault.write("Secret/a.md", note("type: month_plan\nmonth: 2026-10"))
    try vault.write("Secret/b.md", note("type: quarter_focus\nquarter: Q4"))
    try vault.write("Secret/c.md", note("type: yearly-goals\ntitle: \"\""))
    try vault.write("Secret/d.md", note("moonshine: budget\ntype: month_plan\nmonth: 2026-10"))
    try vault.write("Secret/e.md", note("type: private-type"))
    try vault.write("Secret/f.md", "no frontmatter")
    let report = try ObsidianVault(root: vault.root, timeZone: moscow).read().report
    #expect(
      Array(report[5...9]) == [
        "notes: 2 read (month_plan 1 · quarter_focus 0 · year_artifacts 0 · horizon_corridor 0"
          + " · yearly-goals 0 · focus 0 · lifetime 0 · budget note 1)",
        "notes without a period: 0",
        "note problems: missingKey 1 · invalidValue 2",
        "note problems by key: title 1 · type 0 · parent 0 · line 0 · status 0 · scale 0"
          + " · period 1 · month 0 · quarter 1 · year 0 · period_start 0 · period_end 0",
        "kept as unread: 2 paths · not recognised: 2 files",
      ])
    #expect(!report.joined().contains("Secret"))
    #expect(!report.joined().contains("private-type"))
  }

  @Test func theFixtureReportCountsItsNotes() throws {
    let report = try ObsidianVault(root: fixtureVault, timeZone: moscow).read().report
    #expect(
      Array(report[5...6]) == [
        "notes: 6 read (month_plan 1 · quarter_focus 1 · year_artifacts 1 · horizon_corridor 2"
          + " · yearly-goals 0 · focus 0 · lifetime 0 · budget note 1)",
        "notes without a period: 2",
      ])
  }
}
