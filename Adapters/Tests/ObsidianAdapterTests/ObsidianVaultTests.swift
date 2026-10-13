import Foundation
import MoonShineCore
import Testing

@testable import ObsidianAdapter

@Suite struct ObsidianVaultTests {
  @Test func findsTheFixtureBudgetNoteByItsMarker() throws {
    let read = try ObsidianVault(root: fixtureVault, timeZone: moscow).read()
    #expect(read.budget == .found)
    #expect(read.notesFound == 6)
    #expect(read.frontmatterRead == 6)
    #expect(read.issues.isEmpty)
  }

  @Test func onlyTheTopLevelMarkerWithTheExactValueMarksTheBudgetNote() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: Budget"))
    try vault.write("b.md", note("moonshine: [budget]"))
    try vault.write("c.md", note("meta:\n  moonshine: budget"))
    try vault.write("d.md", note("title: Hours budget by line"))
    try vault.write("Hours_budget_by_line.md", note("type: strategic"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .missing)
    #expect(read.issues == [.vaultWide(VaultProblem(.budgetNoteMissing))])
  }

  @Test func twoMarkedNotesAreAmbiguousAndEachGetsAnIssue() throws {
    let vault = try TemporaryVault()
    try vault.write("B/budget.md", note("type: x\nmoonshine: budget"))
    try vault.write("A/budget.md", note("moonshine: budget"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .ambiguous(marked: 2))
    #expect(
      problems(read.issues) == [
        "A/budget.md:2:budgetNoteDuplicate (moonshine)",
        "B/budget.md:3:budgetNoteDuplicate (moonshine)",
      ])
  }

  @Test(arguments: [
    ("moonshine: budget\na: [unclosed", VaultProblem.Kind.malformedYAML),
    ("moonshine: budget\na: &x 1\nb: *x", .yamlAnchor),
    ("moonshine: budget\n%TAG !e! tag:x,2026:", .yamlDirective),
    ("moonshine: budget\na: " + String(repeating: "[", count: 40), .yamlTooComplex),
  ])
  func theOneMarkedNoteRejectedIsTheBudgetNoteAndItsKindIsNamed(
    yaml: String, kind: VaultProblem.Kind
  ) throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    try vault.write("budget.md", note(yaml))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .rejected(kind))
    #expect(read.lines == .unavailable)
    #expect(problems(read.issues).contains("budget.md:2:budgetNoteRejected (moonshine)"))
    #expect(!read.issues.contains(.vaultWide(VaultProblem(.budgetNoteMissing))))
  }

  @Test func aParsedAndARejectedMarkedNoteAreAmbiguousAndNeitherWins() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: budget"))
    try vault.write("b.md", note("x: 1\n'moonshine': \"budget\" # copy\nc: [unclosed"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .ambiguous(marked: 2))
    #expect(
      problems(read.issues).filter { $0.contains("budgetNote") } == [
        "a.md:2:budgetNoteDuplicate (moonshine)", "b.md:3:budgetNoteDuplicate (moonshine)",
      ])
  }

  @Test func twoRejectedMarkedNotesAreAmbiguous() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: budget\na: [unclosed"))
    try vault.write("b.md", note("moonshine: budget\na: [unclosed"))
    #expect(
      try ObsidianVault(root: vault.root, timeZone: moscow).read().budget == .ambiguous(marked: 2))
  }

  @Test func aRejectedNoteWithoutTheMarkerLeavesTheBudgetNoteMissing() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("meta:\n  moonshine: budget\na: [unclosed"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.budget == .missing)
    #expect(read.issues.contains(.vaultWide(VaultProblem(.budgetNoteMissing))))
  }

  @Test(arguments: [
    "moonshine: budget", "\"moonshine\": budget", "'moonshine': 'budget'",
    "moonshine: \"budget\"", "moonshine: budget # the plan", "moonshine :   budget \t\r",
  ])
  func theLexicalMarkerAllowsQuotesAndATrailingComment(line: String) {
    #expect(BudgetNote.markerLine(in: "a: 1\n\(line)\nb: 2") == 3)
    #expect(BudgetNote.markerLine(in: "a: 1\r\n\(line)\r\nb: 2") == 3)
  }

  @Test(arguments: [
    "  moonshine: budget", "moonshine: budgets", "moonshine: budget#x", "moonshine: Budget",
    "# moonshine: budget", "moonshine:budget", "\"moonshine': budget", "moonshine: 'budget\"",
    "xmoonshine: budget",
  ])
  func theLexicalMarkerIsOnlyATopLevelLineWithTheExactValue(line: String) {
    #expect(BudgetNote.markerLine(in: "a: 1\n\(line)") == nil)
  }

  /// A vault with one good note, a note with anchor-like text, a note rejected for an anchor
  /// and an alias, one rejected for a directive, a malformed one and a link.
  func troubledVault(budget: Bool) throws -> TemporaryVault {
    let vault = try TemporaryVault()
    let outside = try TemporaryVault()
    try vault.write("good.md", note(budget ? "moonshine: budget" : "type: x"))
    try vault.write("plain.md", "# No frontmatter\n")
    try vault.write("anchor-like.md", note("tags:\n  - \"&x and y\""))
    try vault.write("anchor.md", note("a: &x 1\nb: *x"))
    try vault.write("directive.md", note("%TAG !e! tag:x,2026:\n--- {a: !e!b 1}"))
    try vault.write("broken.md", note("a: [unclosed"))
    try vault.link("linked.md", to: try outside.write("other.md", note("type: x")))
    return vault
  }

  @Test func theReportCountsEveryKindAndNamesTheAnchorRejections() throws {
    let read = try ObsidianVault(root: try troubledVault(budget: false).root, timeZone: moscow)
      .read()
    #expect(
      read.report == [
        "vault: 6 notes found · 2 frontmatter read",
        "rejected notes: 3 (unreadable 0 · notUTF8 0 · frontmatterTooLarge 0 · malformedYAML 1"
          + " · yamlTooComplex 0 · yamlAnchor 1 · yamlDirective 1)",
        "notes rejected for an anchor: 1",
        "notes with anchor-like text and no alias, accepted: 1",
        "skipped: symlinks 1 · outside vault 0 · unreadable entries 0",
        "notes: 0 read (month_plan 0 · quarter_focus 0 · year_artifacts 0 · horizon_corridor 0"
          + " · yearly-goals 0 · focus 0 · lifetime 0 · budget note 0)",
        "notes without a period: 0",
        "note problems: missingKey 0 · invalidValue 0",
        "note problems by key: title 0 · type 0 · parent 0 · line 0 · status 0 · scale 0"
          + " · period 0 · month 0 · quarter 0 · year 0 · period_start 0 · period_end 0"
          + " · horizons 0",
        "kept as unread: 4 paths · not recognised: 3 files",
        "budget note: missing",
        "lines: unavailable",
        "line problems: missingKey 0 · invalidValue 0 · duplicateLineId 0",
        "foundation lines: 0 · with a floor: 0 · with a language: 0",
      ])
  }

  @Test func theReportNamesTheBudgetNoteStatus() throws {
    let found = try ObsidianVault(root: try troubledVault(budget: true).root, timeZone: moscow)
      .read()
    #expect(found.report.contains("budget note: found"))
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    #expect(
      try ObsidianVault(root: vault.root, timeZone: moscow).read().report.contains(
        "budget note: missing"))
    try vault.write("b.md", note("moonshine: budget\na: [unclosed"))
    #expect(
      try ObsidianVault(root: vault.root, timeZone: moscow).read().report.contains(
        "budget note: rejected (malformedYAML)"))
  }

  @Test func theReportNamesDuplicateBudgetNotesWithoutTheirPaths() throws {
    let vault = try TemporaryVault()
    try vault.write("Secret A.md", note("moonshine: budget"))
    try vault.write("Secret B.md", note("moonshine: budget"))
    let report = try ObsidianVault(root: vault.root, timeZone: moscow).read().report
    #expect(report.contains("budget note: 2 marked notes"))
    #expect(!report.joined().contains("Secret"))
  }

  @Test func problemLocationsGiveKindPathAndLineAndNothingFromTheNote() throws {
    let vault = try TemporaryVault()
    let secret = "planted-secret-title"
    try vault.write("Notes/b.md", note("title: \(secret)\na: [unclosed"))
    try vault.write("a.md", note("title: \(secret)\na: &x 1\nb: *x"))
    try vault.write("c.md", "---\ntitle: \(secret)\n")
    let locations = try ObsidianVault(root: vault.root, timeZone: moscow).read().problemLocations
    #expect(
      locations == [
        "malformedYAML Notes/b.md:4", "yamlAnchor a.md", "malformedYAML c.md:1",
        "budgetNoteMissing",
      ])
    #expect(!locations.joined().contains(secret))
  }

  @Test func problemLocationsShowControlAndFormatCharactersInAPathAsEscapes() throws {
    let vault = try TemporaryVault()
    try vault.write("a\nb\u{1B}[2K\u{202E}c\\d.md", note("a: [unclosed"))
    let locations = try ObsidianVault(root: vault.root, timeZone: moscow).read().problemLocations
    #expect(locations.first == "malformedYAML a\\u{A}b\\u{1B}[2K\\u{202E}c\\\\d.md:3")
    #expect(!locations.joined().unicodeScalars.contains { $0.value < 0x20 || $0 == "\u{202E}" })
  }

  @Test func theCountsReportCarriesNoPath() throws {
    let report = try ObsidianVault(root: try troubledVault(budget: false).root, timeZone: moscow)
      .read().report
    #expect(!report.joined().contains(".md"))
  }

  /// Every entry under `folder`: relative path, size, modification date and contents.
  func tree(_ folder: URL) throws -> [String] {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    let walker = try #require(
      FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys))
    return try walker.compactMap { $0 as? URL }.map { url in
      let values = try url.resourceValues(forKeys: Set(keys))
      let data = (try? Data(contentsOf: url)) ?? Data()
      return
        "\(url.path) \(values.fileSize ?? -1) \(values.contentModificationDate ?? .distantPast)"
        + " \(data.base64EncodedString())"
    }.sorted()
  }

  @Test func readingTheVaultAndItsReportWritesNothing() throws {
    let folder = try TemporaryVault()
    let vault = folder.root.appending(path: "vault", directoryHint: .isDirectory)
    try folder.write("vault/a.md", note("moonshine: budget"))
    try folder.write("vault/b.md", note("a: &x 1"))
    try folder.write("vault/c.md", note("type: month_plan\nmonth: 2026-10"))
    try folder.write("vault/d.md", note("type: focus\ntitle: \"\""))
    try folder.write("vault/e.md", "no frontmatter")
    let before = try tree(folder.root)
    _ = try ObsidianVault(root: vault, timeZone: moscow).read().report
    #expect(try tree(folder.root) == before)
  }
}
