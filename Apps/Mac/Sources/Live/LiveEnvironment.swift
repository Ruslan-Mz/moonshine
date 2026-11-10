import AppKit
import Foundation
import MoonShineCore
import ObsidianAdapter
import OmniFocusAdapter
import SQLiteStore

extension AppEnvironment {
  /// Live: OmniFocus through the bridge and the vault folder `vault` names, into
  /// `<base>/MoonShine/MoonShine.sqlite`. Nil in a test host, read from the process before
  /// anything is opened or started (CLAUDE.md rule 5), and when the folder, the store or the
  /// bridge script is missing. The meta tag groups come from `mapping.yaml` in the folder
  /// (`LiveMapping`).
  static func live(base: URL, vault: VaultFolder) -> AppEnvironment? {
    guard !AppModel.isTestHost,
      let script = Bundle.main.url(forResource: "snapshot", withExtension: "js"),
      let folder = try? DataFolder.create(base: base),
      let store = try? SQLiteStore(path: DataFolder.appStorePath(in: folder))
    else { return nil }
    let mapping = LiveMapping(
      Result { () throws(MappingFileError) in
        try MappingFile.read(file: DataFolder.mappingFile(in: folder))
      },
      tasks: OmniFocusBridge(script: script))
    return make(
      tasks: mapping.tasks, notes: BookmarkedVault(folder: vault), store: store,
      importer: mapping.importer, vaultTimeZone: localTimeZone, mapping: mapping.state,
      clock: .system, source: MacChangeSignals(), omniFocusReading: RunningOmniFocus.now,
      close: { try? store.close() })
  }
}

/// The Mac's zone now, the one the bridge reads in its own process (`bridge/snapshot.js`). The
/// cached system zone is reset first, so a running app follows a zone change.
@Sendable func localTimeZone() -> TimeZone {
  NSTimeZone.resetSystemTimeZone()
  return .current
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
