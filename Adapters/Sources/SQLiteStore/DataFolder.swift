import Foundation

/// Where MoonShine keeps its data: `<base>/MoonShine/`, the base being Application Support,
/// passed in by the app and the measurement tool only (tests pass a temporary folder). It holds
/// raw data, like `data/` (CLAUDE.md rule 5).
public enum DataFolder {
  /// The app's store: its import path is its only writer (ADR-0011, 2026-11-05).
  public static let appStore = "MoonShine.sqlite"
  /// `moonshine-import full`'s own store, never the app's.
  public static let measurementStore = "moonshine-import.sqlite"

  public static func url(base: URL) -> URL {
    base.appending(path: "MoonShine", directoryHint: .isDirectory)
  }

  /// Creates the folder if it is missing and returns it, before any store opens inside it.
  /// Throws when something other than a folder stands at its path.
  public static func create(base: URL) throws -> URL {
    let folder = url(base: base)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  public static func appStorePath(in folder: URL) -> String {
    folder.appending(path: appStore).path(percentEncoded: false)
  }

  public static func measurementStorePath(in folder: URL) -> String {
    folder.appending(path: measurementStore).path(percentEncoded: false)
  }
}
