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

/// What the app reads and refreshes through, built once (ADR-0011). The app's import path is
/// the only writer of the app's store; the model re-reads it when an import commits.
struct AppEnvironment {
  let store: any Store
  let coordinator: RefreshCoordinator
  let source: any ChangeSignalSource
  /// Live only: OmniFocus' state now, read on ⌘R as a resync of the held state.
  let omniFocusReading: (@Sendable () -> OmniFocusState)?
  /// Live only: closes the store at quit.
  let close: (@Sendable () -> Void)?
  /// The import path's clock, so "updated …" counts from the same origin.
  let clock: ImportClock

  static func demo(
    snapshot: URL, store: (any Store)? = nil, source: any ChangeSignalSource = DemoSignals()
  ) throws -> AppEnvironment {
    make(
      tasks: SnapshotFileTaskProvider(url: snapshot), notes: DemoVault(),
      store: try store ?? SQLiteStore(timeZone: DemoVault.calendar.timeZone),
      clock: DemoEnvironment.clock, source: source)
  }

  static func make(
    tasks: any TaskProvider, notes: any NoteProvider, store: any Store, clock: ImportClock,
    source: any ChangeSignalSource, omniFocusReading: (@Sendable () -> OmniFocusState)? = nil,
    close: (@Sendable () -> Void)? = nil
  ) -> AppEnvironment {
    let service = ImportService(tasks: tasks, notes: notes, store: store, clock: clock)
    return AppEnvironment(
      store: store,
      coordinator: RefreshCoordinator(
        service: service, timerInterval: RefreshCoordinator.minimumTimerInterval),
      source: source, omniFocusReading: omniFocusReading, close: close, clock: clock)
  }
}
