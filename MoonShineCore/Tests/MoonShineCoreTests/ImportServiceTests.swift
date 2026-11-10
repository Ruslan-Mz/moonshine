import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

@Suite struct ImportServiceTests {
  @Test func requestsDuringAnImportCoalesceIntoOneFollowUpRun() async throws {
    let provider = GatedTaskProvider()
    let service = ImportService(
      tasks: provider, notes: DemoVault(), store: InMemoryStore(),
      importer: Importer(metaTagGroups: []), vaultTimeZone: { TestWorld.timeZone },
      clock: .frozen(at: Date(timeIntervalSince1970: 1_790_000_000)))

    let running = Task { try await service.run(ImportRequest(trigger: .launch)) }
    await eventually { await provider.calls == 1 }
    let requests = (0..<3).map { _ in
      Task { try await service.run(ImportRequest(trigger: .resignActive)) }
    }
    await eventually { await service.followUpRequests == 3 }
    await provider.open()

    var results = [try await running.value]
    for request in requests { results.append(try await request.value) }
    #expect(await provider.calls == 2)
    #expect(Set(results.map { $0.tasks.map(\.id) }).count == 1)
  }

  @Test func theFollowUpKeepsTheRequestThatQueuedItAndStartsAtItsOwnTime() async throws {
    let provider = GatedTaskProvider()
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let time = SettableClock(start)
    let store = InMemoryStore()
    let service = ImportService(
      tasks: provider, notes: DemoVault(), store: store, importer: Importer(metaTagGroups: []),
      vaultTimeZone: { TestWorld.timeZone }, clock: time.clock)

    let running = Task { try await service.run(ImportRequest(trigger: .launch)) }
    await eventually { await provider.calls == 1 }
    let queued = Task { try await service.run(ImportRequest(trigger: .resignActive)) }
    await eventually { await service.followUpRequests == 1 }
    let joined = Task { try await service.run(ImportRequest(trigger: .timer)) }
    await eventually { await service.followUpRequests == 2 }
    time.set(start.addingTimeInterval(90))
    await provider.open()
    for task in [running, queued, joined] { _ = try await task.value }

    let run = try #require(try await store.lastCommittedImport())
    #expect(run.trigger == .resignActive)
    #expect(run.startedAt == start.addingTimeInterval(90))
    // A request without a signal time waits from when it reached the service.
    #expect(run.waited == .seconds(90))
  }

  /// ADR-0011 (2026-11-04): resign-active outranks the request that queued the follow-up, so
  /// the target's median keeps every resign-active signal.
  @Test func aResignActiveRequestJoiningAQueuedImportIsRecordedWithItsOwnWait() async throws {
    let provider = GatedTaskProvider()
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let time = SettableClock(start)
    let store = InMemoryStore()
    let service = ImportService(
      tasks: provider, notes: DemoVault(), store: store, importer: Importer(metaTagGroups: []),
      vaultTimeZone: { TestWorld.timeZone }, clock: time.clock)

    let running = Task { try await service.run(ImportRequest(trigger: .launch)) }
    await eventually { await provider.calls == 1 }
    let queued = Task { try await service.run(ImportRequest(trigger: .manual)) }
    await eventually { await service.followUpRequests == 1 }
    time.advance(by: .seconds(10))
    let joined = Task { try await service.run(ImportRequest(trigger: .resignActive)) }
    await eventually { await service.followUpRequests == 2 }
    time.advance(by: .seconds(80))
    await provider.open()
    for task in [running, queued, joined] { _ = try await task.value }

    let run = try #require(try await store.lastCommittedImport())
    #expect(run.trigger == .resignActive)
    #expect(run.waited == .seconds(80))
  }

  @Test func aRequestAfterTheFollowUpFinishedRunsAgain() async throws {
    let provider = GatedTaskProvider()
    await provider.open()
    let service = ImportService(
      tasks: provider, notes: DemoVault(), store: InMemoryStore(),
      importer: Importer(metaTagGroups: []), vaultTimeZone: { TestWorld.timeZone })
    try await service.run(ImportRequest(trigger: .manual))
    try await service.run(ImportRequest(trigger: .manual))
    #expect(await provider.calls == 2)
  }

  struct PartialTaskProvider: TaskProvider {
    let since = Date(timeIntervalSince1970: 1_790_000_000)

    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: since, timeZone: TestWorld.timeZone,
        defaultTimes: DefaultTimeSettings(),
        modifiedSince: since, tags: [], projects: [], tasks: [])
    }
  }

  @Test func aPartialSnapshotIsNeverCommittedAsAFullImport() async throws {
    let store = InMemoryStore()
    let provider = PartialTaskProvider()
    let service = ImportService(
      tasks: provider, notes: DemoVault(), store: store, importer: Importer(metaTagGroups: []),
      vaultTimeZone: { TestWorld.timeZone })
    await #expect(throws: PartialSnapshotError(modifiedSince: provider.since)) {
      try await service.run(ImportRequest(trigger: .manual))
    }
    #expect(try await store.identityMap().version == 0)
  }

  struct TimedTaskProvider: TaskProvider {
    let defaultTimes: DefaultTimeSettings?
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 0),
        timeZone: TestWorld.timeZone, defaultTimes: defaultTimes, tags: [], projects: [],
        tasks: [])
    }
  }

  @Test func anImportStoresTheDefaultTimesAndAnUnreadOneKeepsThem() async throws {
    let store = InMemoryStore(timeZone: TestWorld.timeZone)
    let times = DefaultTimeSettings(
      due: TimeOfDay(hour: 17, minute: 0), defer: TimeOfDay(hour: 6, minute: 0))
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    try await ImportService(
      tasks: TimedTaskProvider(defaultTimes: times), notes: DemoVault(), store: store,
      importer: Importer(metaTagGroups: []), vaultTimeZone: { TestWorld.timeZone },
      clock: .frozen(at: now)
    ).run(ImportRequest(trigger: .manual))
    #expect(try await store.workspace().defaultTimeSettings == times)

    try await ImportService(
      tasks: TimedTaskProvider(defaultTimes: nil), notes: DemoVault(), store: store,
      importer: Importer(metaTagGroups: []), vaultTimeZone: { TestWorld.timeZone },
      clock: .frozen(at: now.addingTimeInterval(60))
    ).run(ImportRequest(trigger: .manual))
    let after = try await store.workspace()
    #expect(after.defaultTimeSettings == times)
    #expect(after.issues.contains(.defaultTimesNotRead))
  }
}
