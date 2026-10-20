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

  /// The snapshot copied into the app bundle from `fixtures/`.
  static var bundledSnapshot: URL? {
    Bundle.main.url(forResource: "omnifocus.snapshot", withExtension: "json")
  }

  static func overview(snapshot: URL) async throws -> Overview {
    let store = try SQLiteStore(timeZone: DemoVault.calendar.timeZone)
    let service = ImportService(
      tasks: SnapshotFileTaskProvider(url: snapshot), notes: DemoVault(), store: store)
    try await service.run(now: now)
    return Overview(workspace: try await store.workspace(), now: now)
  }
}
