import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// The `imports` record: what asked, when, how long, how long OmniFocus was held, how many rows
/// (`docs/specs/phase-1-see.md`, S4; ADR-0011). Invented data.
@Suite struct ImportRunTests {
  static let start = Date(timeIntervalSince1970: 1_790_000_000)

  struct HeldTaskProvider: TaskProvider {
    let heldFor: Duration?
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: ImportRunTests.start, timeZone: TestWorld.timeZone,
        defaultTimes: DefaultTimeSettings(), tags: [], projects: [],
        tasks: [SourceTask(externalId: "x", name: "Scales")], heldFor: heldFor)
    }
  }

  /// Succeeds once, then fails.
  actor OnceTaskProvider: TaskProvider {
    struct Unavailable: Error {}
    private var calls = 0
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      calls += 1
      guard calls == 1 else { throw Unavailable() }
      return try await HeldTaskProvider(heldFor: .seconds(1)).snapshot(modifiedSince: nil)
    }
  }

  /// Takes `readTime` on the test clock to read its source.
  struct SlowTaskProvider: TaskProvider {
    let time: SettableClock
    let readTime: Duration
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      time.advance(by: readTime)
      return try await HeldTaskProvider(heldFor: nil).snapshot(modifiedSince: nil)
    }
  }

  /// A store whose write takes `writeTime` on the test clock.
  struct SlowStore: Store {
    let inner = InMemoryStore()
    let time: SettableClock
    let writeTime: Duration

    func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
    func commit(
      _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
      run: PendingImportRun?
    ) async throws {
      time.advance(by: writeTime)
      try await inner.commit(
        workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
    }
    func lastCommittedImport() async throws -> ImportRun? {
      try await inner.lastCommittedImport()
    }
    func workspace() async throws -> Workspace { try await inner.workspace() }
    func stored() async throws -> StoredWorkspace { try await inner.stored() }
  }

  @Test func aCommittedImportRecordsTriggerTimesHeldTimeAndCounts() async throws {
    let time = SettableClock(Self.start)
    time.advance(by: .seconds(1))
    let store = InMemoryStore()
    let service = ImportService(
      tasks: HeldTaskProvider(heldFor: .milliseconds(2_700)), notes: DemoVault(), store: store,
      clock: time.clock)
    let workspace = try await service.run(
      ImportRequest(trigger: .resignActive, signalledAt: .milliseconds(400)))

    let started = Self.start.addingTimeInterval(1)
    #expect(
      try await store.lastCommittedImport()
        == ImportRun(
          trigger: .resignActive, startedAt: started, finishedAt: started,
          waited: .milliseconds(600), duration: .zero, providerHeld: .milliseconds(2_700),
          outcome: .committed(ImportCounts(workspace))))
    #expect(ImportCounts(workspace).tasks == 1)
  }

  @Test func aProviderThatDoesNotReportItsHeldTimeRecordsNoHeldTime() async throws {
    let store = InMemoryStore()
    try await ImportService(
      tasks: HeldTaskProvider(heldFor: nil), notes: DemoVault(), store: store,
      clock: .frozen(at: Self.start)
    ).run(ImportRequest(trigger: .manual))
    let run = try #require(try await store.lastCommittedImport())
    #expect(run.providerHeld == nil)
    // No signal time: the wait counts from the request reaching the service.
    #expect(run.waited != nil)
  }

  @Test func aFailedImportKeepsTheLastCommittedRun() async throws {
    let time = SettableClock(Self.start)
    let store = InMemoryStore()
    let service = ImportService(
      tasks: OnceTaskProvider(), notes: DemoVault(), store: store, clock: time.clock)
    try await service.run(ImportRequest(trigger: .launch))
    time.advance(by: .seconds(60))
    await #expect(throws: OnceTaskProvider.Unavailable.self) {
      try await service.run(ImportRequest(trigger: .timer))
    }
    let run = try #require(try await store.lastCommittedImport())
    #expect(run.trigger == .launch)
    #expect(run.startedAt == Self.start)
  }

  @Test func aSignalAfterTheStartIsNotMeasurableNotZero() {
    let pending = PendingImportRun(
      request: ImportRequest(trigger: .timer, signalledAt: .seconds(5)), startedAt: Self.start,
      started: .seconds(2), providerHeld: nil,
      counts: ImportCounts(lines: 0, notes: 0, artifacts: 0, projects: 0, tasks: 0, tags: 0),
      clock: .frozen(at: Self.start))
    #expect(pending.waited == nil)
    #expect(pending.finished().waited == nil)

    let atTheStart = PendingImportRun(
      request: ImportRequest(trigger: .timer, signalledAt: .seconds(2)), startedAt: Self.start,
      started: .seconds(2), providerHeld: nil, counts: pending.counts,
      clock: .frozen(at: Self.start))
    #expect(atTheStart.waited == .zero)

    let negative = ImportRun(
      trigger: .manual, startedAt: Self.start, finishedAt: Self.start, waited: .seconds(-1),
      duration: .milliseconds(-5), providerHeld: .seconds(-2),
      outcome: .committed(pending.counts))
    #expect(negative.waited == nil)
    #expect(negative.duration == nil)
    #expect(negative.providerHeld == nil)
  }

  /// The start is read before the providers, so the OmniFocus read counts in the duration.
  @Test func theDurationIncludesTheProvidersRead() async throws {
    let time = SettableClock(Self.start)
    let store = InMemoryStore()
    try await ImportService(
      tasks: SlowTaskProvider(time: time, readTime: .seconds(3)), notes: DemoVault(), store: store,
      clock: time.clock
    ).run(ImportRequest(trigger: .manual))
    let run = try #require(try await store.lastCommittedImport())
    #expect(run.startedAt == Self.start)
    #expect(run.duration == .seconds(3))
  }

  /// The store, not the service, reads the end: the time spent in `commit` counts. Where in its
  /// write a store reads it is the store's own test (`SQLiteStoreTests`).
  @Test func theDurationIncludesTheStoresCommit() async throws {
    let time = SettableClock(Self.start)
    let store = SlowStore(time: time, writeTime: .milliseconds(250))
    try await ImportService(
      tasks: HeldTaskProvider(heldFor: nil), notes: DemoVault(), store: store, clock: time.clock
    ).run(ImportRequest(trigger: .manual))
    let run = try #require(try await store.lastCommittedImport())
    #expect(run.duration == .milliseconds(250))
    #expect(run.finishedAt == Self.start.addingTimeInterval(0.25))
  }
}
