import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// "Could not read the lines" is not "there are no lines": only a clean read soft-deletes.
@Suite struct VaultLinesImportTests {
  let earlier = Date(timeIntervalSince1970: 1_790_000_000)
  let now = Date(timeIntervalSince1970: 1_790_086_400)

  let violin = SourceLine(
    key: "violin", name: "Violin", block: "Creative", state: .active, tags: ["violin"])
  let piano = SourceLine(
    key: "piano", name: "Piano", block: "Creative", state: .maintenance, tags: ["piano"])

  var source: TaskSourceSnapshot {
    TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: now, timeZone: TestWorld.timeZone,
      tags: [SourceTag(externalId: "t-piano", name: "piano")], projects: [],
      tasks: [SourceTask(externalId: "x", name: "Scales", tagExternalIds: ["t-piano"])])
  }

  func vault(_ lines: VaultLines) -> VaultSnapshot {
    VaultSnapshot(lines: lines, artifacts: [], notes: [])
  }

  /// A store that already holds violin and piano from a clean read, and its identities.
  func storedAfterACleanRead() -> (StoredWorkspace, IdentityMap) {
    var identities = IdentityMap()
    let first = Importer().makeWorkspace(
      tasks: source, vault: vault(.read([violin, piano], complete: true)), storedLines: [],
      identities: &identities, now: earlier)
    return (StoredWorkspace(timeZone: TestWorld.timeZone).merging(first, at: earlier), identities)
  }

  /// The second import; also returns the lines stored before it.
  func reimport(_ lines: VaultLines) -> (Workspace, StoredWorkspace, before: [Line]) {
    var (stored, identities) = storedAfterACleanRead()
    let before = stored.workspace.lines
    let workspace = Importer().makeWorkspace(
      tasks: source, vault: vault(lines), storedLines: before, identities: &identities, now: now)
    stored = stored.merging(workspace, at: now)
    return (workspace, stored, before)
  }

  @Test func unavailableLinesLeaveTheStoredLinesUntouchedAndStillMapTasks() throws {
    let (workspace, stored, before) = reimport(.unavailable)
    #expect(workspace.lines == before)
    #expect(stored.lines.allSatisfy { !$0.isRemoved })
    let piano = try #require(stored.workspace.lines.first { $0.key == "piano" })
    #expect(workspace.tasks.first?.line == .line(piano.id))
  }

  @Test func aPartialReadUpsertsWhatWasReadAndSoftDeletesNothing() throws {
    let renamed = SourceLine(
      key: "violin", name: "Fiddle", block: "Creative", state: .active, tags: ["violin"])
    let (workspace, stored, _) = reimport(.read([renamed], complete: false))
    #expect(workspace.lines.map(\.name) == ["Fiddle", "Piano"])
    #expect(stored.lines.allSatisfy { !$0.isRemoved })
    let piano = try #require(stored.workspace.lines.first { $0.key == "piano" })
    #expect(workspace.tasks.first?.line == .line(piano.id))
  }

  @Test func aCleanReadSoftDeletesALineNoLongerInTheVault() {
    let (workspace, stored, _) = reimport(.read([violin], complete: true))
    #expect(workspace.lines.map(\.key) == ["violin"])
    #expect(stored.lines.filter(\.isRemoved).map(\.entity.key) == ["piano"])
    #expect(workspace.tasks.first?.line == .lifeOps)
  }

  func line(_ key: String, _ name: String) -> SourceLine {
    SourceLine(key: LineKey(key), name: name, block: "Creative", state: .active)
  }

  @Test func aCleanReadTakesTheOrderFromTheNote() {
    let (workspace, _, _) = reimport(.read([piano, violin], complete: true))
    #expect(workspace.lines.map(\.key) == ["piano", "violin"])
  }

  @Test func aPartialReadKeepsStoredPositionsAndAppendsNewLinesInNoteOrder() {
    let (workspace, _, _) = reimport(
      .read([line("drum", "Drum"), piano, line("cello", "Cello")], complete: false))
    #expect(workspace.lines.map(\.key) == ["violin", "piano", "drum", "cello"])
  }

  @Test func unavailableLinesKeepTheStoredOrder() {
    let (workspace, _, before) = reimport(.unavailable)
    #expect(workspace.lines.map(\.key) == before.map(\.key))
  }

  /// Serves a clean read first, then unavailable lines.
  actor FlakyVault: NoteProvider {
    let lines: SourceLine
    private var reads = 0

    init(_ lines: SourceLine) { self.lines = lines }

    func vault() async throws -> VaultSnapshot {
      reads += 1
      return VaultSnapshot(
        lines: reads == 1 ? .read([lines], complete: true) : .unavailable, artifacts: [],
        notes: [])
    }
  }

  struct OneTask: TaskProvider {
    let source: TaskSourceSnapshot
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot { source }
  }

  @Test func theServiceKeepsTheStoredLinesWhenTheVaultCannotReadThem() async throws {
    let store = InMemoryStore(timeZone: TestWorld.timeZone)
    let service = ImportService(
      tasks: OneTask(source: source), notes: FlakyVault(piano), store: store)
    try await service.run(now: earlier)
    try await service.run(now: now)
    let workspace = try await store.workspace()
    #expect(workspace.lines.map(\.key) == ["piano"])
    #expect(workspace.tasks.first?.line == .line(try #require(workspace.lines.first).id))
  }
}
