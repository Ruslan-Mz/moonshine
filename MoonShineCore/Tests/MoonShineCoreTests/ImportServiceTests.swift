import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

@Suite struct ImportServiceTests {
  /// Serves one task; the first snapshot waits until the test opens the gate.
  actor GatedTaskProvider: TaskProvider {
    private(set) var calls = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      calls += 1
      if !isOpen { await withCheckedContinuation { waiting.append($0) } }
      return TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 0),
        timeZone: TestWorld.timeZone, defaultTimes: DefaultTimeSettings(), tags: [], projects: [],
        tasks: [SourceTask(externalId: "x", name: "Scales")])
    }

    func open() {
      isOpen = true
      for continuation in waiting { continuation.resume() }
      waiting = []
    }
  }

  /// Yields until `condition` holds, bounded so a broken implementation fails instead of hanging.
  func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<10_000 where !(await condition()) { await Task.yield() }
  }

  @Test func requestsDuringAnImportCoalesceIntoOneFollowUpRun() async throws {
    let provider = GatedTaskProvider()
    let service = ImportService(tasks: provider, notes: DemoVault(), store: InMemoryStore())
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    let running = Task { try await service.run(now: now) }
    await eventually { await provider.calls == 1 }
    let requests = (0..<3).map { _ in Task { try await service.run(now: now) } }
    await eventually { await service.followUpRequests == 3 }
    await provider.open()

    var results = [try await running.value]
    for request in requests { results.append(try await request.value) }
    #expect(await provider.calls == 2)
    #expect(Set(results.map { $0.tasks.map(\.id) }).count == 1)
  }

  @Test func aRequestAfterTheFollowUpFinishedRunsAgain() async throws {
    let provider = GatedTaskProvider()
    await provider.open()
    let service = ImportService(tasks: provider, notes: DemoVault(), store: InMemoryStore())
    try await service.run()
    try await service.run()
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
    let service = ImportService(tasks: provider, notes: DemoVault(), store: store)
    await #expect(throws: PartialSnapshotError(modifiedSince: provider.since)) {
      try await service.run()
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
      tasks: TimedTaskProvider(defaultTimes: times), notes: DemoVault(), store: store
    ).run(now: now)
    #expect(try await store.workspace().defaultTimeSettings == times)

    try await ImportService(
      tasks: TimedTaskProvider(defaultTimes: nil), notes: DemoVault(), store: store
    ).run(now: now.addingTimeInterval(60))
    let after = try await store.workspace()
    #expect(after.defaultTimeSettings == times)
    #expect(after.issues.contains(.defaultTimesNotRead))
  }
}
