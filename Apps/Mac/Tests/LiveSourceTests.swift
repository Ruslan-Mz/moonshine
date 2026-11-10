import AppKit
import Foundation
import MoonShineCore
import MoonShineFixtures
import ObsidianAdapter
import OmniFocusAdapter
import Synchronization
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5), not the bundled copy.
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

/// Counts reads and records writes; never the owner's defaults.
final class CountingSettings: AppSettings, @unchecked Sendable {
  private let stored: String?
  private(set) var reads = 0
  private(set) var writes: [String] = []

  init(_ stored: String?) {
    self.stored = stored
  }

  var source: String? {
    reads += 1
    return writes.last ?? stored
  }

  func setSource(_ value: String) {
    writes.append(value)
  }

  /// The vault bookmark (S4-4d), counted apart from the source.
  private(set) var vaultReads = 0
  private(set) var vaultWrites: [StoredBookmark] = []
  var storedBookmark: StoredBookmark?

  var vaultBookmark: StoredBookmark? {
    vaultReads += 1
    return vaultWrites.last ?? storedBookmark
  }

  func setVaultBookmark(_ value: StoredBookmark) {
    vaultWrites.append(value)
  }
}

/// An error that names its kind, as the bridge's do.
struct KindedError: ImportFailureKind {
  let importFailure: ImportFailure
}

/// The tracked snapshot, or a set failure; while closed, every snapshot waits for `open()`.
actor FakeTasks: TaskProvider {
  private let inner = SnapshotFileTaskProvider(url: trackedSnapshot)
  private var failure: (any Error)?
  private var isOpen: Bool
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private(set) var calls = 0

  init(open: Bool = true) {
    isOpen = open
  }

  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
    calls += 1
    if !isOpen { await withCheckedContinuation { waiting.append($0) } }
    if let failure { throw failure }
    return try await inner.snapshot(modifiedSince: modifiedSince)
  }

  func fail(_ error: (any Error)?) {
    failure = error
  }

  func open() {
    isOpen = true
    for continuation in waiting { continuation.resume() }
    waiting = []
  }
}

/// One OmniFocus state, then nothing, as Live's 4c-1 source.
struct OneState: ChangeSignalSource {
  let state: OmniFocusState

  func signals() -> AsyncStream<ChangeSignal> {
    AsyncStream { continuation in
      continuation.yield(.omniFocus(state))
      continuation.finish()
    }
  }
}

/// The signals the test sends after the start, as Live's Mac source would.
final class PushSource: ChangeSignalSource, Sendable {
  private let stream: AsyncStream<ChangeSignal>
  private let continuation: AsyncStream<ChangeSignal>.Continuation

  init() {
    (stream, continuation) = AsyncStream.makeStream()
  }

  func signals() -> AsyncStream<ChangeSignal> { stream }

  func send(_ signals: ChangeSignal...) {
    for signal in signals { continuation.yield(signal) }
  }
}

/// Counts the store closes asked for.
final class Closes: Sendable {
  let count = Mutex(0)
}

/// What ⌘R reads as OmniFocus' state now.
final class Reading: Sendable {
  private let value: Mutex<OmniFocusState>

  init(_ value: OmniFocusState) {
    self.value = Mutex(value)
  }

  func set(_ new: OmniFocusState) {
    value.withLock { $0 = new }
  }

  func get() -> OmniFocusState { value.withLock { $0 } }
}

/// A store whose identity map cannot be read.
struct UnreadableStore: Store {
  let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
  struct Unreadable: Error {}

  func identityMap() async throws -> VersionedIdentityMap { throw Unreadable() }
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    try await inner.commit(
      workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
  }
  func lastCommittedImport() async throws -> ImportRun? { try await inner.lastCommittedImport() }
  func recordFailure(_ run: PendingImportRun, _ kind: ImportFailure) async throws {
    try await inner.recordFailure(run, kind)
  }
  func lastImportAttempt() async throws -> ImportRun? { try await inner.lastImportAttempt() }
  func workspace() async throws -> Workspace { try await inner.workspace() }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// A store that has committed once, but whose workspace cannot be read; with `gate`, the
/// identity map waits until the gate opens.
struct HalfReadableStore: Store {
  let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
  var gate: FakeTasks?
  struct Unreadable: Error {}

  func identityMap() async throws -> VersionedIdentityMap {
    if let gate { _ = try await gate.snapshot(modifiedSince: nil) }
    return VersionedIdentityMap(map: try await inner.identityMap().map, version: 1)
  }
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    try await inner.commit(
      workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
  }
  func lastCommittedImport() async throws -> ImportRun? { nil }
  func recordFailure(_ run: PendingImportRun, _ kind: ImportFailure) async throws {
    try await inner.recordFailure(run, kind)
  }
  func lastImportAttempt() async throws -> ImportRun? { nil }
  func workspace() async throws -> Workspace { throw Unreadable() }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// Records every read and write; `StandardSettings` must not reach it in a test host.
final class RecordingStorage: SettingsStorage {
  private(set) var reads: [String] = []
  private(set) var writes: [String] = []
  private var values: [String: Any] = [:]

  func string(forKey key: String) -> String? {
    reads.append(key)
    return values[key] as? String
  }

  func data(forKey key: String) -> Data? {
    reads.append(key)
    return values[key] as? Data
  }

  func set(_ value: Any?, forKey key: String) {
    writes.append(key)
    values[key] = value
  }
}

/// A Live-like environment over fakes: the clock is Demo's unless given, so the dataset's
/// Today shows; the mapping file names Demo's groups unless `mapping` says otherwise.
private func live(
  _ state: OmniFocusState, tasks: FakeTasks = FakeTasks(),
  notes: any NoteProvider = DemoVault(),
  store: any Store = InMemoryStore(timeZone: DemoVault.calendar.timeZone),
  reading: Reading? = nil, clock: ImportClock = DemoEnvironment.clock,
  source: (any ChangeSignalSource)? = nil, closes: Closes? = nil,
  mapping: Result<MappingFile.Read, MappingFileError> = .success(
    .groups(DemoMapping.metaTagGroups))
) -> AppEnvironment {
  let mapped = LiveMapping(mapping, tasks: tasks)
  var now: (@Sendable () -> OmniFocusState)?
  if let reading { now = { @Sendable in reading.get() } }
  var close: (@Sendable () -> Void)?
  if let closes { close = { @Sendable in closes.count.withLock { $0 += 1 } } }
  return AppEnvironment.make(
    tasks: mapped.tasks, notes: notes, store: store, importer: mapped.importer,
    vaultTimeZone: { DemoVault.calendar.timeZone }, mapping: mapped.state, clock: clock,
    source: source ?? OneState(state: state), omniFocusReading: now, close: close)
}

/// Demo's vault, with `dropped` left out of a clean read, or its lines unavailable.
actor ShrinkingVault: NoteProvider {
  private var dropped: Set<LineKey> = []
  private var unavailable = false

  func drop(_ keys: Set<LineKey>) { dropped = keys }
  func makeUnavailable() { unavailable = true }

  func vault(timeZone: TimeZone) async -> VaultSnapshot {
    let full = DemoVault.snapshot
    return VaultSnapshot(
      lines: unavailable
        ? .unavailable
        : .read(full.lines.read.filter { !dropped.contains($0.key) }, complete: true),
      artifacts: full.artifacts, notes: full.notes, issues: full.issues, unread: full.unread)
  }
}

/// A failed attempt as the import service records it.
private func failedAttempt() -> PendingImportRun {
  PendingImportRun(
    request: ImportRequest(trigger: .launch, signalledAt: .zero), startedAt: DemoEnvironment.now,
    started: .zero, clock: DemoEnvironment.clock)
}

/// A store holding one committed launch import of the tracked snapshot.
private func storeWithAnImport() async throws -> InMemoryStore {
  let store = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
  try await AppEnvironment.demo(snapshot: trackedSnapshot, store: store).coordinator.service
    .run(ImportRequest(trigger: .launch))
  return store
}

/// Live selected, outside a test host as far as the model knows.
@MainActor private func liveModel(_ environment: AppEnvironment?) -> AppModel {
  AppModel(isTestHost: false, settings: CountingSettings("live")) {
    $0 == .live ? environment : nil
  }
}

@MainActor
private func waitFor(_ condition: () -> Bool) async {
  for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

private func isLoaded(_ state: AppModel.State) -> Bool {
  if case .loaded = state { true } else { false }
}

private func isLoading(_ state: AppModel.State) -> Bool {
  if case .loading = state { true } else { false }
}

private func isUnavailable(_ state: AppModel.State) -> Bool {
  if case .unavailable = state { true } else { false }
}

@Suite(.serialized) struct LiveSourceTests {
  @MainActor @Test func aTestHostReadsDemoOnlyWhateverTheSettingSays() {
    let settings = CountingSettings("live")
    #expect(AppModel.source(isTestHost: true, settings: settings) == .demo)
    let model = AppModel(isTestHost: true, settings: settings) { _ in live(.background) }
    #expect(model.source == .demo)
    #expect(settings.reads == 0)
    model.select(.live)
    #expect(model.source == .demo)
    #expect(settings.writes.isEmpty)
    #expect(AppModel.production().source == .demo)
  }

  @Test func aLaunchOutsideTestsFollowsTheSetting() {
    #expect(AppModel.source(isTestHost: false, settings: CountingSettings("live")) == .live)
    for stored in ["LIVE", "demo", "x", ""] as [String?] + [nil] {
      #expect(
        AppModel.source(isTestHost: false, settings: CountingSettings(stored)) == .demo,
        "\(stored ?? "nil")")
    }
  }

  @MainActor @Test func liveWithNothingStoredAndOmniFocusNotRunningSaysSo() async {
    let model = liveModel(live(.notRunning))
    model.start()
    await waitFor { model.omniFocusState == .notRunning }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(isLoading(model.state))
    #expect(model.omniFocusNote == .notRunning)
    #expect(model.importOutcomes == 0)
    #expect(TodayPlaceholder(model) == .notReadYet(.notRunning))
  }

  @MainActor @Test func liveWithAStoredImportShowsItWhileOmniFocusIsNotRunning() async throws {
    let store = try await storeWithAnImport()
    let model = liveModel(live(.notRunning, store: store))
    model.start()
    await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
    #expect(isLoaded(model.state))
    #expect(model.omniFocusNote == .notRunning)
    #expect(model.lastImport?.trigger == .launch)
    #expect(TodayPlaceholder(model) == nil)
  }

  @MainActor @Test func aFailedLiveImportNamesItsKindAndTheNextCommitClearsIt() async {
    let tasks = FakeTasks()
    await tasks.fail(KindedError(importFailure: .permissionDenied))
    let model = liveModel(live(.background, tasks: tasks))
    await model.load()
    #expect(isUnavailable(model.state))
    #expect(model.lastFailure == .permissionDenied)
    #expect(model.omniFocusNote == .failure(.permissionDenied))
    #expect(TodayPlaceholder(model) == .notReadYet(.failure(.permissionDenied)))
    await tasks.fail(nil)
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    #expect(isLoaded(model.state))
    #expect(model.lastFailure == nil)
    #expect(model.omniFocusNote == nil)
    #expect(model.lastImport?.trigger == .manual)
  }

  @MainActor @Test func aQuitSeenOnlyByAFailedRefreshStillSaysNotRunning() async {
    let tasks = FakeTasks()
    let model = liveModel(live(.background, tasks: tasks, reading: Reading(.background)))
    await model.load()
    #expect(isLoaded(model.state))
    await tasks.fail(KindedError(importFailure: .providerNotRunning))
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    #expect(model.omniFocusNote == .notRunning)
    #expect(isLoaded(model.state))
  }

  @MainActor @Test func eachSourceIsBuiltOnceAndASwitchBackImportsAsManual() async {
    let settings = CountingSettings(nil)
    var built: [AppModel.Source] = []
    let model = AppModel(isTestHost: false, settings: settings) { source in
      built.append(source)
      return source == .live
        ? live(.background) : try? AppEnvironment.demo(snapshot: trackedSnapshot)
    }
    await model.load()
    #expect(model.source == .demo)
    model.select(.live)
    #expect(model.source == .live)
    await waitFor { model.importOutcomes == 1 }
    #expect(model.lastImport?.trigger == .launch)
    model.select(.demo)
    await waitFor { model.importOutcomes == 2 }
    #expect(model.lastImport?.trigger == .manual)
    model.select(.live)
    await waitFor { model.importOutcomes == 2 }
    #expect(model.lastImport?.trigger == .manual)
    #expect(built == [.demo, .live])
    #expect(settings.writes == ["live", "demo", "live"])
  }

  @MainActor @Test func eventsOfTheSourceNotShownChangeNothingShown() async {
    let tasks = FakeTasks(open: false)
    let model = AppModel(isTestHost: false, settings: CountingSettings(nil)) { source in
      source == .live
        ? live(.background, tasks: tasks) : try? AppEnvironment.demo(snapshot: trackedSnapshot)
    }
    await model.load()
    model.select(.live)
    await waitFor { model.isImporting }
    #expect(model.isImporting)
    model.select(.demo)
    await waitFor { model.importOutcomes == 2 }
    let shown = model.lastImport
    await tasks.open()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(model.source == .demo)
    #expect(model.lastImport == shown)
    #expect(!model.isImporting)
    #expect(model.importOutcomes == 2)
  }

  @MainActor @Test func liveThatCannotBeOpenedIsUnavailableAndDemoStaysSelectable() async {
    let model = AppModel(isTestHost: false, settings: CountingSettings("live")) { source in
      source == .live ? nil : try? AppEnvironment.demo(snapshot: trackedSnapshot)
    }
    model.start()
    #expect(model.source == .live)
    #expect(isUnavailable(model.state))
    #expect(TodayPlaceholder(model) == .liveUnavailable)
    model.select(.demo)
    await waitFor { isLoaded(model.state) }
    #expect(isLoaded(model.state))
  }

  @Test func theAppAsksForAutomationAndCarriesTheBridge() throws {
    let usage = try #require(
      Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String)
    #expect(!usage.isEmpty)
    let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
    let russian = try #require(Bundle(path: path)).localizedString(
      forKey: "NSAppleEventsUsageDescription", value: nil, table: "InfoPlist")
    #expect(russian.hasPrefix("MoonShine читает"))
    #expect(Bundle.main.url(forResource: "snapshot", withExtension: "js") != nil)
  }

  @MainActor @Test func refreshAfterOmniFocusStartsImportsOnceAsManual() async {
    let reading = Reading(.notRunning)
    let model = liveModel(live(.notRunning, reading: reading))
    model.start()
    await waitFor { model.omniFocusState == .notRunning }
    model.refresh()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(model.importOutcomes == 0)
    reading.set(.background)
    model.refresh()
    await waitFor { model.importOutcomes == 1 }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(model.importOutcomes == 1)
    #expect(model.lastImport?.trigger == .manual)
    #expect(model.omniFocusNote == nil)
  }

  /// ADR-0011's not-running sentence ends when OmniFocus is seen running again (S4-4b-2).
  @MainActor @Test func anOmniFocusStartClearsTheNotRunningSentence() async {
    for (kind, note) in [
      (ImportFailure.providerNotRunning, nil), (.permissionDenied, .failure(.permissionDenied)),
    ] as [(ImportFailure, SourceFeed.OmniFocusNote?)] {
      let (tasks, source) = (FakeTasks(), PushSource())
      await tasks.fail(KindedError(importFailure: kind))
      let model = liveModel(live(.background, tasks: tasks, source: source))
      source.send(.omniFocus(.background))
      await model.load()
      #expect(model.lastFailure == kind)
      // Each state is applied before the next is sent: the feed already holds background.
      source.send(.omniFocus(.notRunning))
      await waitFor { model.omniFocusState == .notRunning }
      #expect(model.omniFocusState == .notRunning)
      source.send(.omniFocus(.background))
      await waitFor { model.omniFocusState == .background }
      #expect(model.omniFocusState == .background)
      #expect(model.omniFocusNote == note, "\(kind)")
      #expect(model.importOutcomes == 1)
    }
  }

  @MainActor @Test func liveImportsNothingWhileDemoIsShownAndASwitchBackImportsOnce() async {
    let (tasks, source) = (FakeTasks(), PushSource())
    let model = AppModel(isTestHost: false, settings: CountingSettings(nil)) { selected in
      selected == .live
        ? live(.background, tasks: tasks, source: source)
        : try? AppEnvironment.demo(snapshot: trackedSnapshot)
    }
    await model.load()
    source.send(.omniFocus(.background))
    model.select(.live)
    await waitFor { model.importOutcomes == 1 }
    #expect(await tasks.calls == 1)

    model.select(.demo)
    await waitFor { model.importOutcomes == 2 }
    // A leave past its settle and a tick, while Demo is shown: Live stays put.
    source.send(.omniFocus(.frontmost), .omniFocus(.background), .timer)
    try? await Task.sleep(for: .seconds(1))
    source.send(.omniFocus(.frontmost))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await tasks.calls == 1)

    model.select(.live)
    #expect(model.omniFocusState == .frontmost)
    await waitFor { model.importOutcomes == 2 }
    #expect(model.lastImport?.trigger == .manual)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await tasks.calls == 2)
  }

  /// L2, 2026-11-07: an OmniFocus start that macOS posts as activate, then launch, imports
  /// nothing while OmniFocus is frontmost; a real leave afterwards imports once.
  @MainActor @Test func anOmniFocusStartSeenAsActivateThenLaunchImportsNothing() async {
    let (tasks, center) = (FakeTasks(), NotificationCenter())
    let source = MacChangeSignals(
      bundleIdentifier: NSRunningApplication.current.bundleIdentifier ?? "", center: center,
      reading: { .notRunning })
    let model = liveModel(live(.notRunning, tasks: tasks, source: source))
    model.start()
    await waitFor { model.omniFocusState == .notRunning }
    let info = [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
    ] {
      center.post(name: name, object: nil, userInfo: info)
    }
    // Past the 0.5 s settle a fake leave would have opened.
    try? await Task.sleep(for: .seconds(1))
    #expect(model.omniFocusState == .frontmost)
    #expect(!model.isImporting)
    #expect(await tasks.calls == 0)

    center.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil, userInfo: info)
    await waitFor { model.importOutcomes == 1 }
    #expect(model.lastImport?.trigger == .resignActive)
    #expect(await tasks.calls == 1)
  }

  /// Live is closed at quit also when Demo is shown: every built store, not the shown one.
  @MainActor @Test func quittingClosesEachBuiltStoreOnce() async {
    let (closes, center) = (Closes(), NotificationCenter())
    var built: [AppModel.Source] = []
    let model = AppModel(isTestHost: false, settings: CountingSettings("live")) { selected in
      built.append(selected)
      return selected == .live
        ? live(.background, closes: closes) : try? AppEnvironment.demo(snapshot: trackedSnapshot)
    }
    model.closeStores(onTerminationOf: center)
    await model.load()
    model.select(.demo)
    await waitFor { model.importOutcomes == 1 }
    #expect(model.importOutcomes == 1)
    center.post(name: NSApplication.willTerminateNotification, object: nil)
    center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(closes.count.withLock { $0 } == 1)
    #expect(built == [.live, .demo])
  }

  @Test func refreshSendsAStateOnlyWhenRunningChanged() {
    let table: [(OmniFocusState?, OmniFocusState?, ChangeSignal?)] = [
      (.notRunning, .background, .omniFocus(.background)),
      (.notRunning, .frontmost, .omniFocus(.background)),
      (.notRunning, .notRunning, nil),
      (.background, .notRunning, .omniFocus(.notRunning)),
      (.frontmost, .notRunning, .omniFocus(.notRunning)),
      (.frontmost, .background, nil), (.background, .frontmost, nil),
      (.background, .background, nil), (.notRunning, nil, nil), (nil, .background, nil),
    ]
    for (held, reading, signal) in table {
      #expect(
        SourceFeed.stateSignal(held: held, reading: reading) == signal,
        "\(String(describing: held)) → \(String(describing: reading))")
    }
  }

  @MainActor @Test func aStoredWorkspaceThatCannotBeReadIsNotNotReadYet() async {
    let model = liveModel(live(.notRunning, store: UnreadableStore()))
    model.start()
    await waitFor { isUnavailable(model.state) }
    #expect(isUnavailable(model.state))
    #expect(TodayPlaceholder(model) == .liveUnavailable)
  }

  @MainActor @Test func liveWithNothingStoredAndNoImportRunningShowsNoSpinner() async {
    let model = liveModel(live(.frontmost))
    model.start()
    await waitFor { model.omniFocusState == .frontmost }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(isLoading(model.state))
    #expect(!model.isImporting)
    #expect(TodayPlaceholder(model) == .notReadYet(nil))
  }

  @MainActor @Test func aTestHostNeverBuildsTheLiveEnvironment() throws {
    try #require(AppModel.isTestHost)
    let base = FileManager.default.temporaryDirectory.appending(path: "base-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: base) }
    #expect(AppEnvironment.live(base: base, vault: VaultFolder(settings: NoSettings())) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
  }

  /// The real defaults are never touched: the storage is an in-memory stub.
  @Test func standardSettingsReadAndWriteNothingInATestHost() throws {
    try #require(AppModel.isTestHost)
    let storage = RecordingStorage()
    let host = StandardSettings(storage: storage)
    #expect(host.source == nil)
    host.setSource("live")
    #expect(storage.reads.isEmpty)
    #expect(storage.writes.isEmpty)
    let app = StandardSettings(storage: storage, isTestHost: false)
    app.setSource("live")
    #expect(app.source == "live")
    #expect(storage.writes == ["source"])
  }

  /// S4-4d: the bookmark too; read and written as one value, data, name and time together.
  @Test func aTestHostReadsNoBookmarkAndWritesNone() throws {
    try #require(AppModel.isTestHost)
    let storage = RecordingStorage()
    let bookmark = StoredBookmark(
      data: Data([1, 2]), name: "Vault", savedAt: Date(timeIntervalSince1970: 1_790_000_000))
    let host = StandardSettings(storage: storage)
    #expect(host.vaultBookmark == nil)
    host.setVaultBookmark(bookmark)
    #expect(storage.reads.isEmpty && storage.writes.isEmpty)
    let app = StandardSettings(storage: storage, isTestHost: false)
    app.setVaultBookmark(bookmark)
    #expect(app.vaultBookmark == bookmark)
    #expect(storage.writes == ["vaultBookmark"])
  }

  @MainActor @Test func aReadableIdentityMapOverAnUnreadableWorkspaceIsUnavailable() async {
    let model = liveModel(live(.notRunning, store: HalfReadableStore()))
    model.start()
    await waitFor { isUnavailable(model.state) }
    #expect(isUnavailable(model.state))
    #expect(model.storeUnreadable)
    #expect(TodayPlaceholder(model) == .liveUnavailable)
  }

  @MainActor @Test func liveBeforeItsStoreIsCheckedIsNotNotReadYet() async {
    let gate = FakeTasks(open: false)
    let model = liveModel(live(.notRunning, store: HalfReadableStore(gate: gate)))
    model.start()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(!model.storeChecked)
    #expect(TodayPlaceholder(model) == .importing)
    await gate.open()
    await waitFor { model.storeChecked }
    #expect(TodayPlaceholder(model) == .liveUnavailable)
  }

  @MainActor @Test func aLiveImportWithNothingStoredShowsTheSpinner() async {
    let tasks = FakeTasks(open: false)
    let model = liveModel(live(.background, tasks: tasks))
    model.start()
    await waitFor { model.isImporting }
    #expect(isLoading(model.state))
    #expect(TodayPlaceholder(model) == .importing)
    await tasks.open()
    await waitFor { isLoaded(model.state) }
    #expect(TodayPlaceholder(model) == nil)
  }

  /// Owner, 2026-11-06: past midnight Today shows the new day from what it holds.
  @MainActor @Test func midnightRebuildsTodayWithoutAnImport() async throws {
    let store = try await storeWithAnImport()
    let time = SettableClock(DemoEnvironment.now)
    let model = liveModel(live(.notRunning, store: store, clock: time.clock))
    model.start()
    await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
    guard case .loaded(let before) = model.state else {
      Issue.record("not loaded")
      return
    }
    let tomorrow = DemoEnvironment.now.addingTimeInterval(9 * 3_600)
    #expect(!before.calendar.isDate(before.now, inSameDayAs: tomorrow))
    time.set(tomorrow)
    NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
    await waitFor {
      if case .loaded(let overview) = model.state { overview.now == tomorrow } else { false }
    }
    guard case .loaded(let after) = model.state else {
      Issue.record("not loaded")
      return
    }
    #expect(after.calendar.isDate(after.now, inSameDayAs: tomorrow))
    #expect(model.importOutcomes == 0)
    #expect(try await store.identityMap().version == 1)
  }

  /// An unmeasured duration reads `last full import` with no number, never 0.
  @Test func theOmniFocusLineOfSettings() throws {
    func run(_ duration: Duration?) -> ImportRun {
      ImportRun(
        trigger: .launch, startedAt: DemoEnvironment.now, finishedAt: DemoEnvironment.now,
        waited: nil, duration: duration, providerHeld: nil,
        outcome: .committed(
          ImportCounts(lines: 0, notes: 0, artifacts: 0, projects: 0, tasks: 1, tags: 0)))
    }
    #expect(OmniFocusLine(source: .demo, lastImport: run(nil), note: .notRunning) == .notReadInDemo)
    #expect(OmniFocusLine(source: .live, lastImport: run(nil), note: nil) == .lastImport(nil))
    let timed = run(.milliseconds(4_000))
    #expect(OmniFocusLine(source: .live, lastImport: timed, note: nil) == .lastImport(.seconds(4)))
    #expect(OmniFocusLine(source: .live, lastImport: nil, note: nil) == .notReadYet)
    #expect(
      OmniFocusLine(source: .live, lastImport: run(nil), note: .failure(.timedOut))
        == .note(.failure(.timedOut)))
    // Where Today says `Live data could not be opened.`, Settings says it too.
    #expect(
      OmniFocusLine(source: .live, lastImport: nil, note: nil, unavailable: true) == .unavailable)
    #expect(
      OmniFocusLine(source: .live, lastImport: run(nil), note: .notRunning, unavailable: true)
        == .unavailable)
    #expect(
      OmniFocusLine(source: .demo, lastImport: nil, note: nil, unavailable: true) == .notReadInDemo)
  }

  /// The groups read from the file reach the importer; a missing file means none; an invalid
  /// one refuses every import and never reaches OmniFocus.
  @Test func theMappingFileDecidesTheTasksTheImporterAndTheState() async throws {
    let tasks = FakeTasks()
    let mapped = LiveMapping(.success(.groups(["Effort", "Other"])), tasks: tasks)
    #expect(mapped.importer.metaTagGroups == ["Effort", "Other"])
    #expect(mapped.state == .groups(["Effort", "Other"]))
    #expect(mapped.tasks is FakeTasks)
    let missing = LiveMapping(.success(.missing), tasks: tasks)
    #expect(missing.importer.metaTagGroups.isEmpty)
    #expect(missing.state == .missing)
    #expect(missing.tasks is FakeTasks)
    let invalid = LiveMapping(.failure(.invalid(.invalidValue, key: .root)), tasks: tasks)
    #expect(invalid.importer.metaTagGroups.isEmpty)
    #expect(invalid.state == .invalid)
    await #expect(throws: MappingFileError.invalid(.invalidValue, key: .root)) {
      _ = try await invalid.tasks.snapshot(modifiedSince: nil)
    }
    #expect(await tasks.calls == 0)
  }

  /// With OmniFocus running, an invalid file shows the stored workspace, refuses the import
  /// without asking OmniFocus, and says why in the status bar and Settings.
  @MainActor @Test func liveWithAnInvalidMappingFileShowsTheStoreAndImportsNothing() async throws {
    let store = try await storeWithAnImport()
    let tasks = FakeTasks()
    let model = liveModel(
      live(.background, tasks: tasks, store: store, mapping: .failure(.unreadable)))
    await model.load()
    #expect(isLoaded(model.state))
    #expect(model.importOutcomes == 1)
    #expect(await tasks.calls == 0)
    #expect(model.lastImport?.trigger == .launch)
    #expect(model.omniFocusNote == .failure(.mappingInvalid))
    #expect(LiveNote.notes(model) == [.mappingInvalid])
    #expect(TagGroupsLine(model) == .invalid)
  }

  @MainActor @Test func notRunningAndAnInvalidMappingFileAreBothSaid() async throws {
    let store = try await storeWithAnImport()
    let model = liveModel(live(.notRunning, store: store, mapping: .failure(.unreadable)))
    model.start()
    await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
    #expect(LiveNote.notes(model) == [.notRunning, .mappingInvalid])
  }

  @MainActor @Test func demoHasNoLiveNotes() async {
    let model = AppModel(snapshot: trackedSnapshot, isTestHost: true)
    await model.load()
    #expect(LiveNote.notes(model).isEmpty)
  }

  /// Counted from the workspace shown: a misspelt group finds no tag.
  @MainActor @Test func theTagGroupsLineCountsTheGroupsFound() async throws {
    let model = liveModel(
      live(.background, mapping: .success(.groups(["Effort", "Setting", "Misspelt"]))))
    await model.load()
    #expect(TagGroupsLine(model) == .found(2, of: 3))
    let demo = AppModel(snapshot: trackedSnapshot, isTestHost: true)
    await demo.load()
    #expect(TagGroupsLine(demo) == .found(2, of: 2))
  }

  /// The store was imported under Demo's groups; the file now names others. Before an import
  /// runs (OmniFocus not running), the count is the current file's names among the shown
  /// workspace's top-level tags: a misspelt name is not found, and n never exceeds m.
  @MainActor @Test func theTagGroupsLineCountsTheCurrentFileNotTheLastImport() async throws {
    for (groups, line) in [
      (["Effort", "Settng"], TagGroupsLine.found(1, of: 2)),
      (["Effort"], .found(1, of: 1)),
    ] {
      let store = try await storeWithAnImport()
      let model = liveModel(
        live(.notRunning, store: store, mapping: .success(.groups(Set(groups)))))
      model.start()
      await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
      #expect(model.importOutcomes == 0)
      #expect(TagGroupsLine(model) == line)
    }
  }

  @Test func theTagGroupsLineOfSettings() {
    let workspace = Workspace(timeZone: .gmt)
    #expect(
      TagGroupsLine(source: .live, mapping: .groups(["A", "B"]), workspace: nil) == .notCountedYet)
    #expect(
      TagGroupsLine(source: .live, mapping: .groups(["A", "B"]), workspace: workspace)
        == .found(0, of: 2))
    #expect(TagGroupsLine(source: .live, mapping: .missing, workspace: workspace) == .missing)
    #expect(TagGroupsLine(source: .live, mapping: .missing, workspace: nil) == .missing)
    #expect(TagGroupsLine(source: .live, mapping: .invalid, workspace: workspace) == .invalid)
    #expect(TagGroupsLine(source: .live, mapping: nil, workspace: nil) == .liveUnavailable)
    #expect(TagGroupsLine(source: .demo, mapping: nil, workspace: nil) == .demoUnavailable)
    #expect(
      TagGroupsLine(source: .demo, mapping: .demo(groups: ["A", "B"]), workspace: workspace)
        == .found(0, of: 2))
  }

  @MainActor @Test func settingsTakesTodaysUnavailableState() async {
    let model = liveModel(live(.notRunning, store: UnreadableStore()))
    model.start()
    await waitFor { isUnavailable(model.state) }
    #expect(TodayPlaceholder(model) == .liveUnavailable)
    #expect(
      OmniFocusLine(
        source: model.source, lastImport: model.lastImport, note: model.omniFocusNote,
        unavailable: TodayPlaceholder(model) == .liveUnavailable) == .unavailable)
  }

  // MARK: S4-4c-3, a recorded failure

  /// A launch that imports nothing (OmniFocus not running) still says why the last one failed.
  @MainActor @Test func aStoredFailureSaysWhyAfterARelaunch() async throws {
    let store = try await storeWithAnImport()
    try await store.recordFailure(failedAttempt(), .permissionDenied)
    let model = liveModel(live(.notRunning, store: store))
    model.start()
    await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
    #expect(model.lastFailure == .permissionDenied)
  }

  /// A store with only failure rows is at version 0: the failure is still said.
  @MainActor @Test func aStoredFailureInAStoreThatNeverCommittedSaysWhy() async throws {
    let store = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
    try await store.recordFailure(failedAttempt(), .timedOut)
    let model = liveModel(live(.notRunning, store: store))
    model.start()
    await waitFor { model.storeChecked && model.omniFocusState == .notRunning }
    #expect(model.lastFailure == .timedOut)
  }

  /// This process reads the mapping file itself: a stored mapping failure says nothing.
  @MainActor @Test func aStoredMappingFailureIsNotSeeded() async throws {
    let store = try await storeWithAnImport()
    try await store.recordFailure(failedAttempt(), .mappingInvalid)
    let model = liveModel(live(.notRunning, store: store))
    model.start()
    await waitFor { isLoaded(model.state) && model.omniFocusState == .notRunning }
    #expect(model.lastFailure == nil)
  }

  // MARK: S4-4e, a held removal

  /// Launch with every line, then a clean read without the first four: held.
  @MainActor private func heldModel(
    _ vault: ShrinkingVault, source: PushSource
  ) async throws -> (AppModel, [LineKey]) {
    let model = liveModel(live(.background, notes: vault, source: source))
    source.send(.omniFocus(.background))
    await model.load()
    guard case .loaded(let overview) = model.state else { throw NotLoaded() }
    let keys = Array(overview.workspace.lines.map(\.key).prefix(4))
    await vault.drop(Set(keys))
    model.refresh()
    await waitFor { model.importOutcomes == 2 }
    #expect(model.heldLineRemoval.map(\.key) == keys)
    #expect(!model.removalApproved)
    return (model, keys)
  }

  struct NotLoaded: Error {}

  @MainActor @Test
  func theNoticeListsTheHeldLinesAndRemoveApprovesExactlyThemAndTheRemovalLandsOnThatImport()
    async throws
  {
    let vault = ShrinkingVault()
    let (model, keys) = try await heldModel(vault, source: PushSource())
    guard case .loaded(let held) = model.state else { throw NotLoaded() }
    #expect(TodayScreen(held).heldRemoval.map(\.id) == model.heldLineRemoval.map(\.id))
    model.approveHeldRemoval()
    await waitFor { model.importOutcomes == 3 }
    #expect(model.heldLineRemoval.isEmpty)
    #expect(!model.removalApproved)
    guard case .loaded(let overview) = model.state else { throw NotLoaded() }
    #expect(!overview.workspace.lines.contains { keys.contains($0.key) })
    #expect(TodayScreen(overview).heldRemoval.isEmpty)
  }

  @MainActor @Test func removeWhileOmniFocusIsNotRunningShowsApprovedPending() async throws {
    let source = PushSource()
    let (model, _) = try await heldModel(ShrinkingVault(), source: source)
    source.send(.omniFocus(.notRunning))
    await waitFor { model.omniFocusState == .notRunning }
    let dropped = model.droppedRequests
    model.approveHeldRemoval()
    // Remove's ⌘R reached the coordinator and was dropped, so no import ran.
    await waitFor { model.droppedRequests == dropped + 1 }
    #expect(model.removalApproved)
    #expect(model.omniFocusNote == .notRunning)
    #expect(model.importOutcomes == 2)
    #expect(model.heldLineRemoval.count == 4)
  }

  @MainActor @Test func anIncompleteReadAfterRemoveKeepsTheButtonsStateHonest() async throws {
    let source = PushSource()
    let vault = ShrinkingVault()
    let (model, _) = try await heldModel(vault, source: source)
    source.send(.omniFocus(.notRunning))
    await waitFor { model.omniFocusState == .notRunning }
    model.approveHeldRemoval()
    await waitFor { model.removalApproved }
    #expect(!model.removalKept)
    await vault.makeUnavailable()
    source.send(.omniFocus(.background))
    await waitFor { model.omniFocusState == .background }
    model.refresh()
    await waitFor { model.importOutcomes == 3 }
    #expect(model.heldLineRemoval.count == 4)
    #expect(model.removalApproved)
    // S4-4d: the notice says the budget note was not read in full.
    #expect(model.removalKept)
  }

  @MainActor @Test func aChangedHeldSetAfterRemoveShowsTheButtonAgain() async throws {
    let source = PushSource()
    let vault = ShrinkingVault()
    let (model, keys) = try await heldModel(vault, source: source)
    source.send(.omniFocus(.notRunning))
    await waitFor { model.omniFocusState == .notRunning }
    model.approveHeldRemoval()
    await waitFor { model.removalApproved }
    await vault.drop(Set(keys.dropLast()))
    source.send(.omniFocus(.background))
    await waitFor { model.omniFocusState == .background }
    model.refresh()
    await waitFor { model.importOutcomes == 3 }
    #expect(model.heldLineRemoval.map(\.key) == Array(keys.dropLast()))
    #expect(!model.removalApproved)
  }
}
