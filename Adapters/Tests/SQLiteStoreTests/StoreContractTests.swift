import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

/// The `Store` contract: every test runs against `InMemoryStore` and `SQLiteStore`.
@Suite struct StoreContractTests {
  let first = Date(timeIntervalSince1970: 1_790_000_000)
  let second = Date(timeIntervalSince1970: 1_790_604_800)
  let third = Date(timeIntervalSince1970: 1_791_209_600)

  func importer(_ source: TaskSourceSnapshot, into store: any Store) -> ImportService {
    ImportService(tasks: FixedTaskProvider(source: source), notes: DemoVault(), store: store)
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
    #expect(try await store.identityMap().entries.isEmpty)
    #expect(try await store.stored() == StoredWorkspace(timeZone: tokyo))
  }

  @Test(arguments: StoreKind.allCases)
  func committedWorkspaceAndIdentitiesReadBackExactly(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    var identities = IdentityMap()
    let workspace = Importer().makeWorkspace(
      tasks: source, vault: try await DemoVault().vault(), identities: &identities, now: first)
    try await store.commit(workspace, identities: identities, at: first)

    expectSame(try await store.workspace(), workspace)
    #expect(try await store.identityMap().entries == identities.entries)
    #expect(
      try await store.stored() == StoredWorkspace(timeZone: .gmt).merging(workspace, at: first))
  }

  @Test(arguments: StoreKind.allCases)
  func reimportKeepsEveryIDAndAddsNothing(kind: StoreKind) async throws {
    let store = try kind.make()
    let service = importer(try fixtureSnapshot(), into: store)
    let one = try await service.run(now: first)
    let two = try await service.run(now: second)
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
    let before = try await importer(source, into: store).run(now: first)
    try await importer(source.dropping(done.externalId), into: store).run(now: second)

    let kept = try #require(task(done.externalId, in: try await store.workspace()))
    #expect(kept == task(done.externalId, in: before))
    #expect(try await store.stored().tasks.first { $0.entity.id == kept.id }?.removedAt == nil)
  }

  @Test(arguments: StoreKind.allCases)
  func openTaskMissingFromTheNextImportIsExcludedButKept(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    try await importer(source, into: store).run(now: first)
    try await importer(source.dropping(open.externalId), into: store).run(now: second)

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
    let before = try await importer(source, into: store).run(now: first)
    try await importer(source.dropping(open.externalId), into: store).run(now: second)
    try await importer(source, into: store).run(now: third)

    let back = try #require(task(open.externalId, in: try await store.workspace()))
    #expect(back.id == task(open.externalId, in: before)?.id)
    #expect(try await store.stored().tasks.first { $0.entity.id == back.id }?.removedAt == nil)
  }

  @Test(arguments: StoreKind.allCases)
  func changedFieldsReplaceStoredOnes(kind: StoreKind) async throws {
    let store = try kind.make()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    try await importer(source, into: store).run(now: first)
    try await importer(source.renaming(open.externalId, to: "Renamed"), into: store)
      .run(now: second)

    #expect(task(open.externalId, in: try await store.workspace())?.title == "Renamed")
  }

  @Test(arguments: StoreKind.allCases)
  func timeZoneIsDataAndInstantsDoNotMove(kind: StoreKind) async throws {
    let store = try kind.make()
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let source = try fixtureSnapshot()
    let moscow = try await importer(source, into: store).run(now: first)
    let tokyoRun = try await importer(source.with(timeZone: tokyo), into: store).run(now: second)

    let workspace = try await store.workspace()
    #expect(workspace.timeZone == tokyo)
    #expect(workspace.tasks.map(\.completedAt) == moscow.tasks.map(\.completedAt))
    #expect(workspace.tasks.map(\.plannedAt) == tokyoRun.tasks.map(\.plannedAt))
  }
}
