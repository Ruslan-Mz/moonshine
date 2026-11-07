import AppKit
import Foundation
import MoonShineCore
import OmniFocusAdapter
import SQLiteStore

extension AppEnvironment {
  /// Live: OmniFocus through the bridge into `<base>/MoonShine/MoonShine.sqlite`; the vault waits
  /// for S4-4d. Nil in a test host, read from the process before anything is opened or started
  /// (CLAUDE.md rule 5), and when the folder, the store or the bridge script is missing.
  static func live(base: URL) -> AppEnvironment? {
    guard !AppModel.isTestHost,
      let script = Bundle.main.url(forResource: "snapshot", withExtension: "js"),
      let folder = try? DataFolder.create(base: base),
      let store = try? SQLiteStore(path: DataFolder.appStorePath(in: folder))
    else { return nil }
    return make(
      tasks: OmniFocusBridge(script: script), notes: NotChosenVault(), store: store,
      clock: .system, source: MacChangeSignals(), omniFocusReading: RunningOmniFocus.now,
      close: { try? store.close() })
  }
}

/// No vault is chosen until S4-4d: nothing is read, and the store keeps every line, note and
/// artifact it holds.
struct NotChosenVault: NoteProvider {
  func vault() async throws -> VaultSnapshot {
    .notRead(issues: [.vaultWide(VaultProblem(.vaultNotChosen))])
  }
}

/// OmniFocus' state now: the change signals' first reading, and ⌘R's resync.
enum RunningOmniFocus {
  @Sendable static func now() -> OmniFocusState {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: OmniFocusBridge.bundleIdentifier)
    if running.isEmpty { return .notRunning }
    return running.contains(where: \.isActive) ? .frontmost : .background
  }
}
