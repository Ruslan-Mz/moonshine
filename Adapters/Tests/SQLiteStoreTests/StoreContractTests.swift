import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

/// The `Store` contract: every test runs against `InMemoryStore` and `SQLiteStore`.
@Suite struct StoreContractTests {
  let first = Date(timeIntervalSince1970: 1_790_000_000)
  let second = Date(timeIntervalSince1970: 1_790_604_800)
  let third = Date(timeIntervalSince1970: 1_791_209_600)

  let manual = ImportRequest(trigger: .manual)

  func importer(
    _ source: TaskSourceSnapshot, into store: any Store, clock: ImportClock
  ) -> ImportService {
    ImportService(
      tasks: FixedTaskProvider(source: source), notes: DemoVault(), store: store, clock: clock)
  }

  func importer(_ source: TaskSourceSnapshot, into store: any Store, at now: Date) -> ImportService
  {
    importer(source, into: store, clock: .frozen(at: now))
  }

  func completedTask(in source: TaskSourceSnapshot) throws -> SourceTask {
    try #require(source.tasks.first { $0.status == .completed })
  }

  func task(_ externalId: String, in workspace: Workspace) -> TaskItem? {
    workspace.tasks.first { $0.refs.contains { $0.externalId == externalId } }
  }

  @Test(arguments: StoreKind.allCases)
  func emptyStoreHasNoDataAndItsTimeZone(kind: StoreKind) async throws {
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let store = try kind.make(timeZone: tokyo)
    expectSame(try await store.workspace(), Workspace(timeZone: tokyo))
    #expect(try await store.identityMap().map.entries.isEmpty)
    #expect(try await store.stored() == StoredWorkspace(timeZone: tokyo))
  }

  @Test(arguments: StoreKind.allCases)
  func committedWorkspaceAndIdentitiesReadBackExactly(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    var identities = IdentityMap()
    let workspace = Importer().makeWorkspace(
      tasks: source, vault: try await DemoVault().vault(), stored: Workspace(timeZone: .gmt),
      identities: &identities,
      now: first)
    try await store.commit(
      workspace, identities: identities, expectedVersion: 0, at: first, run: nil)

    expectSame(try await store.workspace(), workspace)
    #expect(try await store.identityMap().map.entries == identities.entries)
    #expect(
      try await store.stored() == StoredWorkspace(timeZone: .gmt).merging(workspace, at: first))
  }

  @Test(arguments: StoreKind.allCases)
  func defaultTimesAndTheirIssueReadBackInTheWorkspaceZone(kind: StoreKind) async throws {
    let store = try kind.make()
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let times = DefaultTimeSettings(
      due: TimeOfDay(hour: 23, minute: 59), defer: TimeOfDay(hour: 0, minute: 0))
    let workspace = Workspace(
      timeZone: tokyo, defaultTimeSettings: times, issues: [.defaultTimesNotRead])
    try await store.commit(
      workspace, identities: IdentityMap(), expectedVersion: 0, at: first, run: nil)
    let read = try await store.workspace()
    expectSame(read, workspace)
    #expect(read.defaultTimes == DefaultTimes(timeZone: tokyo, times))
  }

  @Test(arguments: StoreKind.allCases)
  func versionPointTwoLineKeysReadBackExactly(kind: StoreKind) async throws {
    let store = try kind.make()
    let lines: VaultLines = .read(
      [
        SourceLine(
          key: "core", name: "Core", block: "Foundation", state: .active, budgetHoursPerWeek: 3,
          foundation: true, floorHoursPerDay: 0.75, language: "zh-Hant"),
        SourceLine(key: "plain", name: "Plain", block: "Life", state: .paused),
      ], complete: true)
    var identities = IdentityMap()
    let workspace = Importer().makeWorkspace(
      tasks: try fixtureSnapshot(),
      vault: VaultSnapshot(lines: lines, artifacts: [], notes: [], unread: .nothing),
      stored: Workspace(timeZone: .gmt), identities: &identities, now: first)
    try await store.commit(
      workspace, identities: identities, expectedVersion: 0, at: first, run: nil)

    let read = try await store.workspace().lines
    #expect(read == workspace.lines)
    #expect(read.map(\.foundation) == [true, false])
    #expect(read.map(\.floorHoursPerDay) == [0.75, nil])
    #expect(read.map(\.language) == ["zh-Hant", nil])
  }

  @Test(arguments: StoreKind.allCases)
  func reimportKeepsEveryIDAndAddsNothing(kind: StoreKind) async throws {
    let store = try kind.make()
    let time = SettableClock(first)
    let service = importer(try fixtureSnapshot(), into: store, clock: time.clock)
    let one = try await service.run(manual)
    time.set(second)
    let two = try await service.run(manual)
    let stored = try await store.stored()

    #expect(one.tasks.map(\.id) == two.tasks.map(\.id))
    #expect(one.projects.map(\.id) == two.projects.map(\.id))
    #expect(one.tags.map(\.id) == two.tags.map(\.id))
    #expect(one.lines.map(\.id) == two.lines.map(\.id))
    #expect(one.notes.map(\.id) == two.notes.map(\.id))
    #expect(one.artifacts.map(\.id) == two.artifacts.map(\.id))
    #expect(stored.tasks.count == one.tasks.count)
    #expect(stored.tasks.allSatisfy { !$0.isRemoved })
    expectSame(try await store.workspace(), two)
  }

  @Test(arguments: StoreKind.allCases)
  func completedTaskOutsideTheWindowSurvivesAReimportWithoutIt(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let done = try completedTask(in: source)
    let before = try await importer(source, into: store, at: first).run(manual)
    try await importer(source.dropping(done.externalId), into: store, at: second).run(manual)

    let kept = try #require(task(done.externalId, in: try await store.workspace()))
    #expect(kept == task(done.externalId, in: before))
    #expect(try await store.stored().tasks.first { $0.entity.id == kept.id }?.removedAt == nil)
  }

  @Test(arguments: StoreKind.allCases)
  func openTaskMissingFromTheNextImportIsExcludedButKept(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    try await importer(source, into: store, at: first).run(manual)
    try await importer(source.dropping(open.externalId), into: store, at: second).run(manual)

    #expect(task(open.externalId, in: try await store.workspace()) == nil)
    let kept = try await store.stored().tasks.first {
      $0.entity.refs.contains { $0.externalId == open.externalId }
    }
    #expect(kept?.removedAt == second)
  }

  @Test(arguments: StoreKind.allCases)
  func removedTaskThatReappearsComesBackWithTheSameID(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    let before = try await importer(source, into: store, at: first).run(manual)
    try await importer(source.dropping(open.externalId), into: store, at: second).run(manual)
    try await importer(source, into: store, at: third).run(manual)

    let back = try #require(task(open.externalId, in: try await store.workspace()))
    #expect(back.id == task(open.externalId, in: before)?.id)
    #expect(try await store.stored().tasks.first { $0.entity.id == back.id }?.removedAt == nil)
  }

  @Test(arguments: StoreKind.allCases)
  func changedFieldsReplaceStoredOnes(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    try await importer(source, into: store, at: first).run(manual)
    try await importer(source.renaming(open.externalId, to: "Renamed"), into: store, at: second)
      .run(manual)

    #expect(task(open.externalId, in: try await store.workspace())?.title == "Renamed")
  }

  @Test(arguments: StoreKind.allCases)
  func timeZoneIsDataAndInstantsDoNotMove(kind: StoreKind) async throws {
    let store = try kind.make()
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let source = try fixtureSnapshot()
    let moscow = try await importer(source, into: store, at: first).run(manual)
    let tokyoRun = try await importer(source.with(timeZone: tokyo), into: store, at: second).run(
      manual)

    let workspace = try await store.workspace()
    #expect(workspace.timeZone == tokyo)
    #expect(workspace.tasks.map(\.completedAt) == moscow.tasks.map(\.completedAt))
    #expect(workspace.tasks.map(\.plannedAt) == tokyoRun.tasks.map(\.plannedAt))
  }

  @Test(arguments: StoreKind.allCases)
  func versionStartsAtZeroAndEveryCommitBumpsIt(kind: StoreKind) async throws {
    let store = try kind.make()
    #expect(try await store.identityMap().version == 0)
    let time = SettableClock(first)
    let service = importer(try fixtureSnapshot(), into: store, clock: time.clock)
    try await service.run(manual)
    #expect(try await store.identityMap().version == 1)
    time.set(second)
    try await service.run(manual)
    #expect(try await store.identityMap().version == 2)
  }

  @Test(arguments: StoreKind.allCases)
  func staleVersionCommitThrowsIdentityConflictAndChangesNothing(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let vault = try await DemoVault().vault()
    let stale = try await store.identityMap()
    var mine = stale.map
    let workspace = Importer().makeWorkspace(
      tasks: source, vault: vault, stored: Workspace(timeZone: .gmt), identities: &mine, now: first)
    try await importer(source, into: store, at: first).run(manual)
    let before = try await store.stored()

    await #expect(throws: IdentityConflict(expectedVersion: 0, actualVersion: 1)) {
      try await store.commit(
        workspace, identities: mine, expectedVersion: stale.version, at: second, run: nil)
    }
    #expect(try await store.stored() == before)
    #expect(try await store.identityMap().version == 1)
  }

  /// Timer and ⌘R overlapping on one service: one id per ref, no duplicate history,
  /// nothing soft-deleted.
  @Test(arguments: StoreKind.allCases)
  func overlappingImportsOfTheSameSnapshotAgree(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let service = importer(source, into: store, at: first)
    async let one = service.run(manual)
    async let two = service.run(manual)
    let (a, b) = try await (one, two)

    #expect(a.tasks.map(\.id) == b.tasks.map(\.id))
    try await expectOneRowPerRef(in: store, tasks: source.tasks.count)
  }

  /// Two services on one store (no shared single-flight): the store itself rejects the
  /// stale commit, so whatever wins, history never duplicates.
  @Test(arguments: StoreKind.allCases)
  func overlappingImportsFromTwoServicesNeverDuplicate(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let one = importer(source, into: store, at: first)
    let two = importer(source, into: store, at: first)
    let runs = [Task { try await one.run(manual) }, Task { try await two.run(manual) }]
    var outcomes: [Result<Workspace, any Error>] = []
    for run in runs { outcomes.append(await run.result) }

    #expect(outcomes.contains { if case .success = $0 { true } else { false } })
    for case .failure(let error) in outcomes { #expect(error is IdentityConflict) }
    try await expectOneRowPerRef(in: store, tasks: source.tasks.count)
  }

  func expectOneRowPerRef(in store: any Store, tasks: Int) async throws {
    let stored = try await store.stored()
    #expect(stored.tasks.count == tasks)
    #expect(stored.tasks.allSatisfy { !$0.isRemoved })
    #expect(stored.projects.allSatisfy { !$0.isRemoved })
    #expect(stored.lines.allSatisfy { !$0.isRemoved })
    let refs = stored.tasks.flatMap(\.entity.refs).map(\.externalId)
    #expect(Set(refs).count == refs.count)
  }

  // MARK: - Recorded imports

  /// A run that started at `first` and is finished `took` later by the store.
  func pending(
    _ trigger: ImportTrigger, held: Duration?, took: Duration = .milliseconds(1_500)
  ) -> (PendingImportRun, SettableClock) {
    let time = SettableClock(first)
    time.advance(by: .seconds(1))
    let run = PendingImportRun(
      request: ImportRequest(trigger: trigger, signalledAt: .milliseconds(600)),
      startedAt: first, started: .seconds(1), providerHeld: held,
      counts: ImportCounts(lines: 3, notes: 2, artifacts: 4, projects: 5, tasks: 6, tags: 1),
      clock: time.clock)
    time.advance(by: took)
    return (run, time)
  }

  @Test(arguments: StoreKind.allCases)
  func aCommittedRunReadsBackExactly(kind: StoreKind) async throws {
    let store = try kind.make()
    for (version, held) in [Duration.milliseconds(2_700), nil].enumerated() {
      let (run, _) = pending(.resignActive, held: held)
      try await store.commit(
        Workspace(timeZone: .gmt), identities: IdentityMap(), expectedVersion: version,
        at: first, run: run)
      #expect(
        try await store.lastCommittedImport()
          == ImportRun(
            trigger: .resignActive, startedAt: first,
            finishedAt: first.addingTimeInterval(2.5), waited: .milliseconds(400),
            duration: .milliseconds(1_500), providerHeld: held,
            outcome: .committed(
              ImportCounts(lines: 3, notes: 2, artifacts: 4, projects: 5, tasks: 6, tags: 1))))
    }
  }

  @Test(arguments: StoreKind.allCases)
  func anEmptyStoreHasNoImport(kind: StoreKind) async throws {
    #expect(try await kind.make().lastCommittedImport() == nil)
  }

  @Test(arguments: StoreKind.allCases)
  func theNewestCommittedRunIsTheLastImport(kind: StoreKind) async throws {
    let store = try kind.make()
    for (version, trigger) in [ImportTrigger.launch, .timer].enumerated() {
      try await store.commit(
        Workspace(timeZone: .gmt), identities: IdentityMap(), expectedVersion: version,
        at: first, run: pending(trigger, held: nil).0)
    }
    #expect(try await store.lastCommittedImport()?.trigger == .timer)
  }

  @Test(arguments: StoreKind.allCases)
  func aRejectedCommitRecordsNoRun(kind: StoreKind) async throws {
    let store = try kind.make()
    await #expect(throws: IdentityConflict(expectedVersion: 1, actualVersion: 0)) {
      try await store.commit(
        Workspace(timeZone: .gmt), identities: IdentityMap(), expectedVersion: 1, at: first,
        run: pending(.manual, held: nil).0)
    }
    #expect(try await store.lastCommittedImport() == nil)
  }
}
