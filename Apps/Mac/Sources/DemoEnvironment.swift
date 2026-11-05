import Foundation
import MoonShineCore
import MoonShineFixtures
import OmniFocusAdapter
import SQLiteStore

/// Demo mode: the invented snapshot and `DemoVault`, imported into an in-memory store at a
/// frozen clock, Thu 1 Oct 2026 16:20 in the dataset's time zone (`docs/specs/phase-1-see.md`).
/// Views read the store, never the providers.
enum DemoEnvironment {
  static let now = DemoCalendar.now
  /// Stands still at `now`, so the Demo always reads as just imported.
  static let clock = ImportClock.frozen(at: now)

  /// The snapshot copied into the app bundle from `fixtures/`.
  static var bundledSnapshot: URL? {
    Bundle.main.url(forResource: "omnifocus.snapshot", withExtension: "json")
  }

  static func overview(snapshot: URL) async throws -> Overview {
    try await load(snapshot: snapshot).overview
  }

  /// The Overview and the import that filled it. The import is read on its own: a store that
  /// cannot read it loses only the freshness text, never Today.
  static func load(snapshot: URL, store: (any Store)? = nil) async throws -> (
    overview: Overview, lastImport: ImportRun?
  ) {
    let store = try store ?? SQLiteStore(timeZone: DemoVault.calendar.timeZone)
    let service = ImportService(
      tasks: SnapshotFileTaskProvider(url: snapshot), notes: DemoVault(), store: store,
      clock: clock)
    try await service.run(ImportRequest(trigger: .launch))
    let overview = Overview(workspace: try await store.workspace(), now: now)
    return (overview, try? await store.lastCommittedImport())
  }
}

/// Demo's signals: OmniFocus in the background, nothing else, so Demo imports at launch and
/// on ⌘R only.
struct DemoSignals: ChangeSignalSource {
  func signals() -> AsyncStream<ChangeSignal> {
    AsyncStream { continuation in
      continuation.yield(.omniFocus(.background))
      continuation.finish()
    }
  }
}

/// What the app reads and refreshes through, built once (ADR-0011). The import path is the
/// store's only writer; the model re-reads the store when an import commits.
struct AppEnvironment {
  let store: any Store
  let coordinator: RefreshCoordinator
  let source: any ChangeSignalSource

  static func demo(
    snapshot: URL, store: (any Store)? = nil, source: any ChangeSignalSource = DemoSignals()
  ) throws -> AppEnvironment {
    let store = try store ?? SQLiteStore(timeZone: DemoVault.calendar.timeZone)
    let service = ImportService(
      tasks: SnapshotFileTaskProvider(url: snapshot), notes: DemoVault(), store: store,
      clock: DemoEnvironment.clock)
    return AppEnvironment(
      store: store,
      coordinator: RefreshCoordinator(
        service: service, timerInterval: RefreshCoordinator.minimumTimerInterval),
      source: source)
  }
}
