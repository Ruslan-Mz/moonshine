import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// A failed attempt is a row too: its kind, its wait and its duration, never a value (S4-4c-3;
/// ADR-0011). Invented data.
@Suite struct FailedImportTests {
  static let start = Date(timeIntervalSince1970: 1_790_000_000)

  struct TimedOut: ImportFailureKind {
    var importFailure: ImportFailure { .timedOut }
  }

  /// Takes `readTime` on the test clock, then throws `error`.
  struct FailingTaskProvider: TaskProvider {
    let time: SettableClock
    let readTime: Duration
    let error: any Error
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      time.advance(by: readTime)
      throw error
    }
  }

  /// A store whose failure record cannot be written.
  struct UnrecordableStore: Store {
    struct WriteFailed: Error {}
    let inner = InMemoryStore()

    func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
    func commit(
      _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
      run: PendingImportRun?
    ) async throws {
      try await inner.commit(
        workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
    }
    func recordFailure(_ run: PendingImportRun, _ kind: ImportFailure) async throws {
      throw WriteFailed()
    }
    func lastCommittedImport() async throws -> ImportRun? {
      try await inner.lastCommittedImport()
    }
    func lastImportAttempt() async throws -> ImportRun? { try await inner.lastImportAttempt() }
    func workspace() async throws -> Workspace { try await inner.workspace() }
    func stored() async throws -> StoredWorkspace { try await inner.stored() }
  }

  func service(
    _ provider: any TaskProvider, store: any Store, time: SettableClock
  ) -> ImportService {
    ImportService(
      tasks: provider, notes: DemoVault(), store: store, importer: Importer(metaTagGroups: []),
      clock: time.clock)
  }

  @Test func aFailedImportIsRecordedWithItsKindAndTheLastCommittedRunStays() async throws {
    let time = SettableClock(Self.start)
    let store = InMemoryStore()
    let provider = GatedTaskProvider(open: true)
    let service = service(provider, store: store, time: time)
    try await service.run(ImportRequest(trigger: .launch))
    let committed = try await store.lastCommittedImport()
    let version = await store.identityMap().version

    time.advance(by: .seconds(60))
    await provider.setFailure(TimedOut())
    await #expect(throws: TimedOut.self) {
      try await service.run(ImportRequest(trigger: .resignActive))
    }
    let attempt = try #require(try await store.lastImportAttempt())
    #expect(attempt.trigger == .resignActive)
    #expect(attempt.outcome == .failed(.timedOut))
    #expect(try await store.lastCommittedImport() == committed)
    #expect(await store.identityMap().version == version)
  }

  @Test func anUnclassifiedErrorIsOther() async throws {
    let time = SettableClock(Self.start)
    let store = InMemoryStore()
    let provider = GatedTaskProvider(open: true)
    await provider.setFailing(true)
    await #expect(throws: GatedTaskProvider.Unreadable.self) {
      try await service(provider, store: store, time: time).run(ImportRequest(trigger: .timer))
    }
    #expect(try await store.lastImportAttempt()?.outcome == .failed(.other))
    #expect(try await store.lastCommittedImport() == nil)
  }

  @Test func aFailedRecordDoesNotHideTheImportError() async throws {
    let time = SettableClock(Self.start)
    let provider = GatedTaskProvider(open: true)
    await provider.setFailure(TimedOut())
    await #expect(throws: TimedOut.self) {
      try await service(provider, store: UnrecordableStore(), time: time).run(
        ImportRequest(trigger: .manual))
    }
  }

  @Test func aFailedRunHasItsWaitAndDurationAndNoHeldTime() async throws {
    let time = SettableClock(Self.start)
    time.advance(by: .seconds(1))
    let store = InMemoryStore()
    let provider = FailingTaskProvider(time: time, readTime: .seconds(10), error: TimedOut())
    await #expect(throws: TimedOut.self) {
      try await service(provider, store: store, time: time).run(
        ImportRequest(trigger: .resignActive, signalledAt: .milliseconds(400)))
    }
    #expect(
      try await store.lastImportAttempt()
        == ImportRun(
          trigger: .resignActive, startedAt: Self.start.addingTimeInterval(1),
          finishedAt: Self.start.addingTimeInterval(11), waited: .milliseconds(600),
          duration: .seconds(10), providerHeld: nil, outcome: .failed(.timedOut)))
  }

  @Test func aPartialSnapshotIsRecordedAsSuch() async throws {
    let time = SettableClock(Self.start)
    let store = InMemoryStore()
    let provider = FailingTaskProvider(
      time: time, readTime: .zero, error: PartialSnapshotError(modifiedSince: Self.start))
    await #expect(throws: PartialSnapshotError.self) {
      try await service(provider, store: store, time: time).run(ImportRequest(trigger: .manual))
    }
    #expect(try await store.lastImportAttempt()?.outcome == .failed(.partialSnapshot))
  }

  @Test func recordFailureWritesOneRowAndLeavesTheCommittedRunAndTheVersion() async throws {
    let store = InMemoryStore()
    let pending = PendingImportRun(
      request: ImportRequest(trigger: .timer, signalledAt: .zero), startedAt: Self.start,
      started: .zero, clock: .frozen(at: Self.start))
    try await store.recordFailure(pending, .permissionDenied)
    #expect(try await store.lastImportAttempt()?.outcome == .failed(.permissionDenied))
    #expect(try await store.lastCommittedImport() == nil)
    #expect(await store.identityMap().version == 0)
  }
}
