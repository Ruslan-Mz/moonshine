import Foundation
import MoonShineCore
import MoonShineFixtures
import Synchronization
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5), not the bundled copy.
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

/// A store whose workspace reads fail while `failing` is set.
final class FailingReadsStore: Store {
  let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
  private let failing: Mutex<Bool>
  struct Unreadable: Error {}

  init(failing: Bool) {
    self.failing = Mutex(failing)
  }

  func setFailing(_ value: Bool) {
    failing.withLock { $0 = value }
  }

  func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    try await inner.commit(
      workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
  }
  func lastCommittedImport() async throws -> ImportRun? { try await inner.lastCommittedImport() }
  func workspace() async throws -> Workspace {
    if failing.withLock({ $0 }) { throw Unreadable() }
    return try await inner.workspace()
  }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// A source that ends without a state: OmniFocus counts as not running, so nothing imports.
struct SilentSignals: ChangeSignalSource {
  func signals() -> AsyncStream<ChangeSignal> { AsyncStream { $0.finish() } }
}

@MainActor
private func waitFor(_ condition: () -> Bool) async {
  for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

private func isLoaded(_ state: AppModel.State) -> Bool {
  if case .loaded = state { true } else { false }
}

private func isUnavailable(_ state: AppModel.State) -> Bool {
  if case .unavailable = state { true } else { false }
}

@Suite(.serialized) struct RefreshTests {
  @MainActor @Test func refreshInDemoImportsAgainAndRecordsAManualRun() async throws {
    let model = AppModel(snapshot: trackedSnapshot)
    await model.load()
    #expect(model.lastImport?.trigger == .launch)
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    #expect(model.lastImport?.trigger == .manual)
    #expect(isLoaded(model.state))
    #expect(!model.isImporting)
    #expect(model.omniFocusState == .background)
  }

  @MainActor @Test func startTwiceImportsOnce() async throws {
    let model = AppModel(snapshot: trackedSnapshot)
    async let first: Void = model.start()
    async let second: Void = model.start()
    _ = await (first, second)
    await waitFor { model.importOutcomes == 1 }
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.importOutcomes == 1)
  }

  @MainActor @Test func aFailedReloadKeepsTheShownToday() async throws {
    let store = FailingReadsStore(failing: false)
    let model = AppModel(environment: try .demo(snapshot: trackedSnapshot, store: store))
    await model.load()
    #expect(isLoaded(model.state))
    store.setFailing(true)
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    #expect(isLoaded(model.state))
    #expect(!model.isImporting)
  }

  @MainActor @Test func aFailedFirstReloadIsUnavailable() async throws {
    let store = FailingReadsStore(failing: true)
    let model = AppModel(environment: try .demo(snapshot: trackedSnapshot, store: store))
    await model.load()
    #expect(isUnavailable(model.state))
    #expect(!model.isImporting)
  }

  @MainActor @Test func aFailedImportClearsUpdating() async throws {
    let gone = FileManager.default.temporaryDirectory
      .appendingPathComponent("moonshine-\(UUID().uuidString).json")
    let model = AppModel(environment: try .demo(snapshot: gone))
    await model.load()
    #expect(isUnavailable(model.state))
    #expect(!model.isImporting)
    #expect(model.importOutcomes == 1)
  }

  @MainActor @Test func storedDataIsShownBeforeTheLaunchImport() async throws {
    let store = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
    _ = try await DemoEnvironment.load(snapshot: trackedSnapshot, store: store)
    // No state ever arrives, so the launch import never runs: what shows is the store's.
    let model = AppModel(
      environment: try .demo(snapshot: trackedSnapshot, store: store, source: SilentSignals()))
    model.start()
    await waitFor { isLoaded(model.state) }
    #expect(isLoaded(model.state))
    #expect(model.lastImport?.trigger == .launch)
    #expect(model.importOutcomes == 0)
  }

  @MainActor @Test func aStoreThatCannotReadItsImportsStillShowsTodayThroughTheModel()
    async throws
  {
    let model = AppModel(
      environment: try .demo(snapshot: trackedSnapshot, store: TodayScreenTests.NoImportsStore()))
    await model.load()
    #expect(isLoaded(model.state))
    #expect(model.lastImport == nil)
  }
}
