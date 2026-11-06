import Foundation
import MoonShineCore
import MoonShineFixtures
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

  init(open: Bool = true) {
    isOpen = open
  }

  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
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
  func workspace() async throws -> Workspace { try await inner.workspace() }
  func stored() async throws -> StoredWorkspace { try await inner.stored() }
}

/// A Live-like environment over fakes: the clock is Demo's, so the dataset's Today shows.
private func live(
  _ state: OmniFocusState, tasks: FakeTasks = FakeTasks(),
  store: any Store = InMemoryStore(timeZone: DemoVault.calendar.timeZone),
  reading: Reading? = nil
) -> AppEnvironment {
  var now: (@Sendable () -> OmniFocusState)?
  if let reading { now = { @Sendable in reading.get() } }
  return AppEnvironment.make(
    tasks: tasks, notes: DemoVault(), store: store, clock: DemoEnvironment.clock,
    source: OneState(state: state), omniFocusReading: now)
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
    let store = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
    try await AppEnvironment.demo(snapshot: trackedSnapshot, store: store).coordinator.service
      .run(ImportRequest(trigger: .launch))
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
    let base = FileManager.default.temporaryDirectory.appending(path: "base-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: base) }
    #expect(AppEnvironment.live(base: base) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
    let settings = StandardSettings()
    #expect(settings.source == nil)
    settings.setSource("live")
    #expect(settings.source == nil)
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
  }
}
