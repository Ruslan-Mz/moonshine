import Foundation
import MoonShineCore
import Testing

@testable import ObsidianAdapter

@Suite struct ObsidianVaultTests {
  @Test func findsTheFixtureBudgetNoteByItsMarker() throws {
    let read = try ObsidianVault(root: fixtureVault).read()
    #expect(read.budgetNotes == 1)
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
    #expect(read.budgetNotes == 0)
    #expect(read.issues == [.vaultWide(VaultProblem(.budgetNoteMissing))])
  }

  @Test func aSecondBudgetNoteIsAnIssueOnItsPathAndTheFirstByPathWins() throws {
    let vault = try TemporaryVault()
    try vault.write("B/budget.md", note("type: x\nmoonshine: budget"))
    try vault.write("A/budget.md", note("moonshine: budget"))
    let read = try ObsidianVault(root: vault.root).read()
    #expect(read.budgetNotes == 2)
    #expect(problems(read.issues) == ["B/budget.md:3:budgetNoteDuplicate (moonshine)"])
  }

  /// A vault with one good note, a note rejected for an anchor, a malformed one and a link.
  func troubledVault(budget: Bool) throws -> TemporaryVault {
    let vault = try TemporaryVault()
    let outside = try TemporaryVault()
    try vault.write("good.md", note(budget ? "moonshine: budget" : "type: x"))
    try vault.write("plain.md", "# No frontmatter\n")
    try vault.write("anchor.md", note("a: &x 1"))
    try vault.write("broken.md", note("a: [unclosed"))
    try vault.link("linked.md", to: try outside.write("other.md", note("type: x")))
    return vault
  }

  @Test func theReportCountsEveryKindAndNamesTheAnchorRejections() throws {
    let read = try ObsidianVault(root: try troubledVault(budget: false).root).read()
    #expect(
      read.report == [
        "vault: 4 notes found · 1 frontmatter read",
        "rejected notes: 2 (unreadable 0 · notUTF8 0 · frontmatterTooLarge 0 · malformedYAML 1"
          + " · yamlTooComplex 0 · yamlAnchor 1)",
        "notes rejected for an anchor: 1",
        "skipped: symlinks 1 · outside vault 0 · unreadable entries 0",
        "budget note: missing",
        "the budget note may be among the rejected notes",
      ])
  }

  @Test func theRejectedNotesHintAppearsOnlyWhenTheBudgetNoteIsMissing() throws {
    let found = try ObsidianVault(root: try troubledVault(budget: true).root).read()
    #expect(found.report.last == "budget note: found")
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    let missing = try ObsidianVault(root: vault.root).read()
    #expect(missing.report.last == "budget note: missing")
  }

  @Test func theReportNamesDuplicateBudgetNotesWithoutTheirPaths() throws {
    let vault = try TemporaryVault()
    try vault.write("Secret A.md", note("moonshine: budget"))
    try vault.write("Secret B.md", note("moonshine: budget"))
    let report = try ObsidianVault(root: vault.root).read().report
    #expect(report.last == "budget note: 2 found, first by path used")
    #expect(!report.joined().contains("Secret"))
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
