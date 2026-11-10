import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// More than three lines leaving the budget note in one clean read wait for the owner's
/// approval of exactly that set (S4-4e; `docs/specs/phase-1-see.md`). Invented data.
@Suite struct LineRemovalHoldTests {
  static let earlier = Date(timeIntervalSince1970: 1_790_000_000)
  static let now = Date(timeIntervalSince1970: 1_790_086_400)

  static func line(_ key: String, name: String? = nil, tags: [String]? = nil) -> SourceLine {
    SourceLine(
      key: LineKey(key), name: name ?? key.capitalized, block: "Creative", state: .active,
      tags: tags ?? [key])
  }

  static let all = ["violin", "piano", "italian", "japanese", "cello", "drum"].map { line($0) }
  static func lines(_ keys: [String]) -> [SourceLine] {
    keys.map { key in all.first { $0.key.rawValue == key } ?? line(key) }
  }

  static var source: TaskSourceSnapshot {
    TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: now, timeZone: TestWorld.timeZone,
      defaultTimes: DefaultTimeSettings(), tags: [SourceTag(externalId: "t-piano", name: "piano")],
      projects: [],
      tasks: [SourceTask(externalId: "x", name: "Scales", tagExternalIds: ["t-piano"])])
  }

  static func vault(_ lines: VaultLines) -> VaultSnapshot {
    VaultSnapshot(lines: lines, artifacts: [], notes: [], unread: .nothing)
  }

  /// A store that starts with all six lines from a clean read.
  struct World {
    var stored = StoredWorkspace(timeZone: TestWorld.timeZone)
    var identities = IdentityMap()

    init() {
      read(.read(LineRemovalHoldTests.all, complete: true), at: LineRemovalHoldTests.earlier)
    }

    @discardableResult
    mutating func read(
      _ lines: VaultLines, approved: Set<LineKey> = [], at now: Date = LineRemovalHoldTests.now
    ) -> Workspace {
      let workspace = Importer(metaTagGroups: []).makeWorkspace(
        tasks: LineRemovalHoldTests.source, vault: LineRemovalHoldTests.vault(lines),
        stored: stored.workspace, approvedLineRemovals: approved, identities: &identities,
        now: now)
      stored = stored.merging(workspace, at: now)
      return workspace
    }

    var removed: [LineKey] { stored.lines.filter(\.isRemoved).map(\.entity.key) }
  }

  static func held(_ workspace: Workspace) -> [LineKey]? {
    workspace.issues.lazy.compactMap { issue -> [LineKey]? in
      if case .lineRemovalHeld(let keys) = issue { keys } else { nil }
    }.first
  }

  static let four: [LineKey] = ["piano", "italian", "japanese", "cello"]

  @Test func aCleanReadThatDropsFourLinesKeepsThemAndReportsTheHoldInStoredOrder() {
    var world = World()
    let workspace = world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    #expect(Self.held(workspace) == Self.four)
    #expect(world.removed.isEmpty)
    #expect(workspace.heldLineRemoval.map(\.key) == Self.four)
    // Held: stored positions, not the note's order.
    #expect(
      workspace.lines.map(\.key) == ["violin", "piano", "italian", "japanese", "cello", "drum"])
  }

  @Test func aCleanReadThatDropsThreeLinesSoftDeletesThem() {
    var world = World()
    let workspace = world.read(.read(Self.lines(["violin", "piano", "drum"]), complete: true))
    #expect(Self.held(workspace) == nil)
    #expect(world.removed == ["italian", "japanese", "cello"])
  }

  @Test func anApprovalOfExactlyThatSetIsApplied() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(
      .read(Self.lines(["drum", "violin"]), complete: true), approved: Set(Self.four))
    #expect(Self.held(workspace) == nil)
    #expect(workspace.lines.map(\.key) == ["drum", "violin"])
    #expect(world.removed == Self.four)
  }

  @Test func anApprovalOfAnotherSetHoldsAgainWithTheNewSet() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(
      .read(Self.lines(["drum", "violin"]), complete: true), approved: ["piano", "italian"])
    #expect(Self.held(workspace) == Self.four)
    #expect(world.removed.isEmpty)
  }

  @Test func anIncompleteReadNeverHoldsOrRemovesEvenWithAMatchingApproval() {
    var world = World()
    let workspace = world.read(
      .read(Self.lines(["violin"]), complete: false), approved: Set(Self.four))
    #expect(Self.held(workspace) == nil)
    #expect(world.removed.isEmpty)
    #expect(workspace.lines.count == 6)
  }

  @Test func anIncompleteReadKeepsTheStoredHold() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(.unavailable, approved: Set(Self.four))
    #expect(Self.held(workspace) == Self.four)
    #expect(world.removed.isEmpty)
  }

  @Test func anIncompleteReadDropsAHeldLineTheNoteListsAgainFromTheHold() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(.read(Self.lines(["piano"]), complete: false))
    #expect(Self.held(workspace) == ["italian", "japanese", "cello"])
    let none = world.read(.read(Self.lines(["italian", "japanese", "cello"]), complete: false))
    #expect(Self.held(none) == nil)
  }

  @Test func whileHeldReadLinesUpdateNewLinesAppendAndHeldLinesKeepTheirTasksWithRuleClaimedTwice()
    throws
  {
    var world = World()
    let viola = Self.line("viola", tags: ["piano"])
    let fiddle = Self.line("violin", name: "Fiddle")
    let workspace = world.read(.read([viola, Self.line("drum"), fiddle], complete: true))
    #expect(Self.held(workspace) == Self.four)
    #expect(
      workspace.lines.map(\.key)
        == ["violin", "piano", "italian", "japanese", "cello", "drum", "viola"])
    #expect(workspace.lines.first?.name == "Fiddle")
    let piano = try #require(workspace.lines.first { $0.key == "piano" })
    #expect(workspace.tasks.first?.line == .line(piano.id))
    #expect(
      workspace.issues.contains(
        .ruleClaimedTwice(rule: "tag piano", kept: "piano", ignored: "viola")))
  }

  @Test func aLineAlreadySoftDeletedIsNotCounted() {
    var world = World()
    world.read(
      .read(Self.lines(["violin", "piano", "italian", "japanese", "drum"]), complete: true))
    #expect(world.removed == ["cello"])
    let workspace = world.read(.read(Self.lines(["violin", "drum"]), complete: true))
    #expect(Self.held(workspace) == nil)
    #expect(Set(world.removed) == Set(Self.four))
  }

  @Test func aSetHeldOnceStaysHeldWhenItShrinksToThree() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(.read(Self.lines(["violin", "cello", "drum"]), complete: true))
    #expect(Self.held(workspace) == ["piano", "italian", "japanese"])
    #expect(world.removed.isEmpty)
  }

  @Test func aHeldLineThatComesBackLeavesTheHold() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let back = world.read(.read(Self.all, complete: true))
    #expect(Self.held(back) == nil)
    #expect(back.lines.map(\.key) == Self.all.map(\.key))
  }

  @Test func aCleanReadWhereThreeLeaveAndTwoWereHeldRemovesTheThirdAndHoldsTheTwo() {
    var world = World()
    world.read(.read(Self.lines(["drum", "violin"]), complete: true))
    let workspace = world.read(.read(Self.lines(["violin", "japanese", "cello"]), complete: true))
    #expect(Self.held(workspace) == ["piano", "italian"])
    #expect(world.removed == ["drum"])
    #expect(workspace.lines.map(\.key) == ["violin", "piano", "italian", "japanese", "cello"])
  }

  // MARK: The service's approval

  /// Serves the lines it was last given.
  actor ScriptedVault: NoteProvider {
    private var lines: VaultLines = .read(LineRemovalHoldTests.all, complete: true)
    func set(_ lines: VaultLines) { self.lines = lines }
    func vault() async throws -> VaultSnapshot { LineRemovalHoldTests.vault(lines) }
  }

  struct Source: TaskProvider {
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      LineRemovalHoldTests.source
    }
  }

  /// A service whose store holds all six lines and then the hold of four.
  func heldService(
    tasks: any TaskProvider = Source()
  ) async throws -> (ImportService, ScriptedVault, InMemoryStore) {
    let vault = ScriptedVault()
    let store = InMemoryStore(timeZone: TestWorld.timeZone)
    let service = ImportService(
      tasks: tasks, notes: vault, store: store, importer: Importer(metaTagGroups: []),
      clock: .frozen(at: Self.now))
    try await service.run(ImportRequest(trigger: .launch))
    await vault.set(.read(Self.lines(["drum", "violin"]), complete: true))
    let held = try await service.run(ImportRequest(trigger: .manual))
    #expect(Self.held(held) == Self.four)
    return (service, vault, store)
  }

  @Test func anApprovalIsUsedByOneCommitOnly() async throws {
    let (service, vault, store) = try await heldService()
    await service.approveLineRemovals(Set(Self.four))
    let applied = try await service.run(ImportRequest(trigger: .manual))
    #expect(Self.held(applied) == nil)
    #expect(await service.approvedLineRemovals.isEmpty)
    #expect(try await store.workspace().lines.map(\.key) == ["drum", "violin"])

    await vault.set(.read(Self.all, complete: true))
    try await service.run(ImportRequest(trigger: .manual))
    await vault.set(.read(Self.lines(["drum", "violin"]), complete: true))
    #expect(Self.held(try await service.run(ImportRequest(trigger: .manual))) == Self.four)
  }

  @Test func aFailedImportKeepsTheApproval() async throws {
    let tasks = GatedTaskProvider(open: true)
    let (service, _, store) = try await heldService(tasks: tasks)
    await service.approveLineRemovals(Set(Self.four))
    await tasks.setFailing(true)
    await #expect(throws: GatedTaskProvider.Unreadable.self) {
      try await service.run(ImportRequest(trigger: .manual))
    }
    #expect(await service.approvedLineRemovals == Set(Self.four))
    await tasks.setFailing(false)
    try await service.run(ImportRequest(trigger: .manual))
    #expect(try await store.workspace().lines.map(\.key) == ["drum", "violin"])
  }

  @Test func anApprovalIsKeptByAnIncompleteReadAndByAChangedSet() async throws {
    let (service, vault, _) = try await heldService()
    await service.approveLineRemovals(Set(Self.four))
    await vault.set(.unavailable)
    #expect(Self.held(try await service.run(ImportRequest(trigger: .manual))) == Self.four)
    #expect(await service.approvedLineRemovals == Set(Self.four))

    await vault.set(.read(Self.lines(["violin", "cello", "drum"]), complete: true))
    let changed = try await service.run(ImportRequest(trigger: .manual))
    #expect(Self.held(changed) == ["piano", "italian", "japanese"])
    #expect(await service.approvedLineRemovals == Set(Self.four))
  }

  @Test func anApprovalGivenDuringAnImportAppliesToTheFollowUp() async throws {
    let tasks = GatedTaskProvider(open: true)
    let (service, _, store) = try await heldService(tasks: tasks)
    await tasks.close()
    let calls = await tasks.calls
    let running = Task { try await service.run(ImportRequest(trigger: .manual)) }
    await eventually { await tasks.calls == calls + 1 }
    await service.approveLineRemovals(Set(Self.four))
    let followUp = Task { try await service.run(ImportRequest(trigger: .manual)) }
    await eventually { await service.followUpRequests == 1 }
    await tasks.open()
    #expect(Self.held(try await running.value) == Self.four)
    #expect(Self.held(try await followUp.value) == nil)
    #expect(try await store.workspace().lines.map(\.key) == ["drum", "violin"])
    #expect(await service.approvedLineRemovals.isEmpty)
  }
}
