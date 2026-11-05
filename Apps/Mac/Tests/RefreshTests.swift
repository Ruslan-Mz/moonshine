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

/// A store whose workspace reads fail from the commit after `failAfterNextCommit()` on, so the
/// import itself commits and only the model's re-read fails.
final class FailingReadsStore: Store {
  let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
  private let flags = Mutex((armed: false, failing: false))
  struct Unreadable: Error {}

  func failAfterNextCommit() {
    flags.withLock { $0.armed = true }
  }

  func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    try await inner.commit(
      workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
    flags.withLock { if $0.armed { $0.failing = true } }
  }
  func lastCommittedImport() async throws -> ImportRun? { try await inner.lastCommittedImport() }
  func workspace() async throws -> Workspace {
    if flags.withLock({ $0.failing }) { throw Unreadable() }
    return try await inner.workspace()
  }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// A store that commits without an import row, as `moonshine-import full` does.
struct RunlessStore: Store {
  let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)

  func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    try await inner.commit(
      workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: nil)
  }
  func lastCommittedImport() async throws -> ImportRun? { try await inner.lastCommittedImport() }
  func workspace() async throws -> Workspace { try await inner.workspace() }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// Fills `store` through the import path the app runs, before a model starts over it.
private func fill(_ store: any Store) async throws {
  let environment = try AppEnvironment.demo(snapshot: trackedSnapshot, store: store)
  try await environment.coordinator.service.run(ImportRequest(trigger: .launch))
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
    let store = FailingReadsStore()
    let model = AppModel(environment: try .demo(snapshot: trackedSnapshot, store: store))
    await model.load()
    #expect(isLoaded(model.state))
    store.failAfterNextCommit()
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    // The ⌘R import committed; only the re-read failed.
    #expect(model.lastImport?.trigger == .manual)
    #expect(isLoaded(model.state))
    #expect(!model.isImporting)
  }

  @MainActor @Test func aFailedFirstReloadIsUnavailable() async throws {
    let store = FailingReadsStore()
    store.failAfterNextCommit()
    let model = AppModel(environment: try .demo(snapshot: trackedSnapshot, store: store))
    await model.load()
    #expect(model.lastImport?.trigger == .launch)
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
    try await fill(store)
    // No state ever arrives, so the launch import never runs: what shows is the store's.
    let model = AppModel(
      environment: try .demo(snapshot: trackedSnapshot, store: store, source: SilentSignals()))
    model.start()
    await waitFor { isLoaded(model.state) }
    #expect(isLoaded(model.state))
    #expect(model.lastImport?.trigger == .launch)
    #expect(model.importOutcomes == 0)
  }

  @MainActor @Test func aStoreCommittedWithoutAnImportRowIsShownAtLaunch() async throws {
    let store = RunlessStore()
    try await fill(store)
    let model = AppModel(
      environment: try .demo(snapshot: trackedSnapshot, store: store, source: SilentSignals()))
    model.start()
    await waitFor { isLoaded(model.state) }
    #expect(isLoaded(model.state))
    #expect(model.lastImport == nil)
    #expect(model.importOutcomes == 0)
  }
}
