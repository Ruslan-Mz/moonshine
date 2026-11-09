import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import ObsidianAdapter

/// `ObsidianVault` as the `NoteProvider`, and imports through it. Invented notes.
@Suite struct ObsidianProviderTests {
  /// Serves one task, so an import has something to map.
  struct OneTask: TaskProvider {
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 0), timeZone: moscow,
        defaultTimes: DefaultTimeSettings(),
        tags: [], projects: [], tasks: [SourceTask(externalId: "x", name: "Scales")])
    }
  }

  static let budget =
    "moonshine: budget\nlines:\n"
    + "  - {id: violin, name: Violin, block: Creative, state: active}"

  /// A year note with these `artifacts:` items (YAML lines, indented by two).
  static func year(_ year: Int, _ items: String...) -> String {
    "type: year_artifacts\nyear: \(year)\nartifacts:\n" + items.joined(separator: "\n")
  }

  /// A vault with the budget note, imported once per state of the vault (path → frontmatter,
  /// or raw text for a note given with `raw:`); returns each import's workspace and the store.
  func importing(_ states: [String: String]...) async throws -> (
    runs: [Workspace], stored: StoredWorkspace
  ) {
    let vault = try TemporaryVault()
    let store = InMemoryStore(timeZone: moscow)
    let time = SettableClock(Date(timeIntervalSince1970: 1_790_000_000))
    let service = ImportService(
      tasks: OneTask(), notes: ObsidianVault(root: vault.root, timeZone: moscow), store: store,
      importer: Importer(metaTagGroups: DemoMapping.metaTagGroups), clock: time.clock)
    var runs: [Workspace] = []
    for (index, state) in states.enumerated() {
      time.set(Date(timeIntervalSince1970: 1_790_000_000 + 86_400 * Double(index)))
      try vault.write("budget.md", note(Self.budget))
      for (path, text) in state {
        try vault.write(path, text.hasPrefix("raw:") ? String(text.dropFirst(4)) : note(text))
      }
      runs.append(try await service.run(ImportRequest(trigger: .manual)))
    }
    return (runs, await store.stored())
  }

  @Test func theFixtureVaultEqualsTheDemoVault() async throws {
    let snapshot = try await ObsidianVault(root: fixtureVault, timeZone: moscow).vault()
    #expect(snapshot == DemoVault.snapshot)
  }

  @Test func theSnapshotCarriesWhatTheReadSawAndCouldNotUse() async throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: year_artifacts\nyear: 2026\nartifacts: [{id: A}]"))
    try vault.write("b.md", note("type: month_plan"))
    try vault.write("c.md", "no frontmatter")
    let provider = ObsidianVault(root: vault.root, timeZone: moscow)
    let read = try provider.read()
    let snapshot = try await provider.vault()
    #expect(snapshot.isRead)
    #expect(snapshot.issues == read.issues && !snapshot.issues.isEmpty)
    #expect(
      snapshot.unread
        == VaultUnread(paths: ["b.md"], artifactLists: ["a.md"], notRecognised: ["c.md"]))
    #expect(snapshot.notes == read.notes && snapshot.artifacts.isEmpty)
    #expect(snapshot.lines == .unavailable)
  }

  @Test func theReportCountsLineParentsThatResolveToNoNoteRead() throws {
    let vault = try TemporaryVault()
    let line = { (id: String, parent: String) in
      "  - {id: \(id), name: N, block: B, state: active, parent: \"\(parent)\"}"
    }
    try vault.write(
      "budget.md",
      note(
        "moonshine: budget\nlines:\n"
          + [
            line("a", "[[Years/Artifacts_2026]]"), line("b", "[[Artifacts_2026|This year]]"),
            line("c", "[[Missing]]"), line("d", "[[Other/Artifacts_2026]]"),
            line("e", "[[Not a note]]"), line("g", "[[plan]]"),
          ].joined(separator: "\n")
          + "\n  - {id: f, name: N, block: B, state: active}"))
    try vault.write("Years/Artifacts_2026.md", note(Self.year(2026)))
    try vault.write("Not a note.md", note("type: journal"))
    try vault.write("Plan.md", note("type: quarter_focus\nquarter: 2026-Q3"))
    try vault.write("Old/Plan.md", note("type: quarter_focus\nquarter: 2026-Q4"))
    let read = try ObsidianVault(root: vault.root, timeZone: moscow).read()
    #expect(read.report.last == "line parents: 6 · resolved to no note read: 3 · ambiguous: 1")
    // Resolved to the shortest path, and reported; the line itself is read.
    #expect(problems(read.issues) == ["budget.md:9:ambiguousLink (lines.parent)"])
    #expect(read.lines.read.count == 7)
  }

  // MARK: Through ImportService

  @Test func anItemThatTurnsInvalidKeepsItsStoredArtifactAndPosition() async throws {
    let items = ["  - {id: a, title: A, line: violin}", "  - {id: c, title: C}"]
    let (runs, stored) = try await importing(
      ["y.md": Self.year(2026, items[0], "  - {id: b, title: B}", items[1])],
      ["y.md": Self.year(2026, items[0], "  - {id: b, title: B, status: started}", items[1])])
    #expect(runs[1].artifacts.map(\.key) == ["a", "b", "c"])
    #expect(runs[1].artifacts.map(\.id) == runs[0].artifacts.map(\.id))
    // `b` was not read: it is the stored artifact, unchanged.
    try #require(runs[0].artifacts.count == 3 && runs[1].artifacts.count == 3)
    #expect(runs[1].artifacts[1] == runs[0].artifacts[1])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  @Test func aYearNoteThatTurnsMalformedKeepsAllItsArtifacts() async throws {
    let (runs, stored) = try await importing(
      ["y.md": Self.year(2026, "  - {id: a, title: A}", "  - {id: b, title: B}")],
      ["y.md": "raw:---\ntype: year_artifacts\nyear: [unclosed\n---\n"])
    #expect(runs[1].artifacts == runs[0].artifacts)
    // The year note is kept as stored; the budget note is read again.
    #expect(
      runs[1].notes.filter { $0.path == "y.md" } == runs[0].notes.filter { $0.path == "y.md" })
    #expect(runs[1].notes.map(\.path) == ["budget.md", "y.md"])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
  }

  @Test func anItemRemovedFromACleanlyReadListIsSoftDeleted() async throws {
    let (runs, stored) = try await importing(
      ["y.md": Self.year(2026, "  - {id: a, title: A}", "  - {id: b, title: B}")],
      ["y.md": Self.year(2026, "  - {id: a, title: A}")])
    #expect(runs[1].artifacts.map(\.key) == ["a"])
    #expect(stored.artifacts.filter(\.isRemoved).map(\.entity.key) == ["b"])
  }

  @Test func aCarriedAppearanceKeepsItsOwnIdAcrossImports() async throws {
    let (runs, stored) = try await importing(
      [
        "a.md": Self.year(2026, "  - {id: x, title: Certificate}"),
        "b.md": Self.year(2027, "  - {id: x, title: Certificate}"),
      ],
      ["b.md": Self.year(2027, "  - {id: x, title: \"Certificate, oral part\"}")])
    let ids = runs[0].artifacts.map(\.id)
    #expect(Set(ids).count == 2)
    #expect(runs[1].artifacts.map(\.id) == ids)
    #expect(runs[1].artifacts.map(\.title) == ["Certificate", "Certificate, oral part"])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }
}
