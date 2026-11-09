import Foundation
import MoonShineCore
import ObsidianAdapter

/// What the app knows about its meta tag groups, for Settings and the status bar (S4-4c-2).
enum MappingState: Equatable {
  /// Demo's own invented set (`DemoMapping`).
  case demo(groups: Int)
  /// No `mapping.yaml`: no group is meta.
  case missing
  case groups(Int)
  /// Every import is refused until MoonShine is reopened with a valid file.
  case invalid
}

/// Live's task provider, importer and mapping state, from the read of `mapping.yaml` at Live's
/// first selection (one environment per process, so a fixed file needs a relaunch). An invalid
/// file refuses every import, so a broken edit never reclassifies tags; the store stays shown.
struct LiveMapping {
  let tasks: any TaskProvider
  let importer: Importer
  let state: MappingState

  init(_ read: Result<MappingFile.Read, MappingFileError>, tasks: any TaskProvider) {
    switch read {
    case .success(.missing):
      self.tasks = tasks
      importer = Importer(metaTagGroups: [])
      state = .missing
    case .success(.groups(let groups)):
      self.tasks = tasks
      importer = Importer(metaTagGroups: groups)
      state = .groups(groups.count)
    case .failure(let error):
      self.tasks = RefusedTasks(error: error)
      importer = Importer(metaTagGroups: [])
      state = .invalid
    }
  }
}

/// Refuses every read with the mapping file's error: OmniFocus is never asked.
struct RefusedTasks: TaskProvider {
  let error: MappingFileError

  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot { throw error }
}
