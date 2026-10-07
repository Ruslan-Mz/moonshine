import Foundation
import MoonShineCore
import Testing

@testable import ObsidianAdapter

@Suite struct ObsidianVaultTests {
  @Test func findsTheFixtureBudgetNoteByItsMarker() throws {
    let read = try ObsidianVault(root: fixtureVault).read()
    #expect(read.budget == .found)
    #expect(read.notesFound == 6)
    #expect(read.frontmatterRead == 6)
    #expect(read.issues.isEmpty)
  }

  @Test func linesStayUnavailableUntilTheReaderParsesThem() throws {
    #expect(try ObsidianVault(root: fixtureVault).read().lines == .unavailable)
  }

  @Test func onlyTheTopLevelMarkerWithTheExactValueMarksTheBudgetNote() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: Budget"))
    try vault.write("b.md", note("moonshine: [budget]"))
    try vault.write("c.md", note("meta:\n  moonshine: budget"))
    try vault.write("d.md", note("title: Hours budget by line"))
    try vault.write("Hours_budget_by_line.md", note("type: strategic"))
    let read = try ObsidianVault(root: vault.root).read()
    #expect(read.budget == .missing)
    #expect(read.issues == [.vaultWide(VaultProblem(.budgetNoteMissing))])
  }

  @Test func twoMarkedNotesAreAmbiguousAndEachGetsAnIssue() throws {
    let vault = try TemporaryVault()
    try vault.write("B/budget.md", note("type: x\nmoonshine: budget"))
    try vault.write("A/budget.md", note("moonshine: budget"))
    let read = try ObsidianVault(root: vault.root).read()
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
    let read = try ObsidianVault(root: vault.root).read()
    #expect(read.budget == .rejected(kind))
    #expect(read.lines == .unavailable)
    #expect(problems(read.issues).contains("budget.md:2:budgetNoteRejected (moonshine)"))
    #expect(!read.issues.contains(.vaultWide(VaultProblem(.budgetNoteMissing))))
  }

  @Test func aParsedAndARejectedMarkedNoteAreAmbiguousAndNeitherWins() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("moonshine: budget"))
    try vault.write("b.md", note("x: 1\n'moonshine': \"budget\" # copy\nc: [unclosed"))
    let read = try ObsidianVault(root: vault.root).read()
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
    #expect(try ObsidianVault(root: vault.root).read().budget == .ambiguous(marked: 2))
  }

  @Test func aRejectedNoteWithoutTheMarkerLeavesTheBudgetNoteMissing() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("meta:\n  moonshine: budget\na: [unclosed"))
    let read = try ObsidianVault(root: vault.root).read()
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
    let read = try ObsidianVault(root: try troubledVault(budget: false).root).read()
    #expect(
      read.report == [
        "vault: 6 notes found · 2 frontmatter read",
        "rejected notes: 3 (unreadable 0 · notUTF8 0 · frontmatterTooLarge 0 · malformedYAML 1"
          + " · yamlTooComplex 0 · yamlAnchor 1 · yamlDirective 1)",
        "notes rejected for an anchor: 1",
        "notes with anchor-like text and no alias, accepted: 1",
        "skipped: symlinks 1 · outside vault 0 · unreadable entries 0",
        "budget note: missing",
      ])
  }

  @Test func theReportNamesTheBudgetNoteStatus() throws {
    let found = try ObsidianVault(root: try troubledVault(budget: true).root).read()
    #expect(found.report.last == "budget note: found")
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    #expect(try ObsidianVault(root: vault.root).read().report.last == "budget note: missing")
    try vault.write("b.md", note("moonshine: budget\na: [unclosed"))
    #expect(
      try ObsidianVault(root: vault.root).read().report.last
        == "budget note: rejected (malformedYAML)")
  }

  @Test func theReportNamesDuplicateBudgetNotesWithoutTheirPaths() throws {
    let vault = try TemporaryVault()
    try vault.write("Secret A.md", note("moonshine: budget"))
    try vault.write("Secret B.md", note("moonshine: budget"))
    let report = try ObsidianVault(root: vault.root).read().report
    #expect(report.last == "budget note: 2 marked notes")
    #expect(!report.joined().contains("Secret"))
  }

  @Test func problemLocationsGiveKindPathAndLineAndNothingFromTheNote() throws {
    let vault = try TemporaryVault()
    let secret = "planted-secret-title"
    try vault.write("Notes/b.md", note("title: \(secret)\na: [unclosed"))
    try vault.write("a.md", note("title: \(secret)\na: &x 1\nb: *x"))
    try vault.write("c.md", "---\ntitle: \(secret)\n")
    let locations = try ObsidianVault(root: vault.root).read().problemLocations
    #expect(
      locations == [
        "malformedYAML Notes/b.md:4", "yamlAnchor a.md", "malformedYAML c.md:1",
        "budgetNoteMissing",
      ])
    #expect(!locations.joined().contains(secret))
  }

  @Test func theCountsReportCarriesNoPath() throws {
    let report = try ObsidianVault(root: try troubledVault(budget: false).root).read().report
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
    let before = try tree(folder.root)
    _ = try ObsidianVault(root: vault).read().report
    #expect(try tree(folder.root) == before)
  }
}
