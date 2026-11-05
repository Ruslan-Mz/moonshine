import Foundation
import MoonShineCore
import Observation

enum SidebarItem: Hashable {
  case today
}

@MainActor @Observable
final class AppModel {
  enum State {
    case loading
    /// Views build their screens from it, with their own view state (Top 3's "Show all").
    case loaded(Overview)
    /// Shown as one neutral sentence; no error text, id or value reaches the screen.
    case unavailable
  }

  /// Where Today's data comes from. Demo only until S4-4c adds Live.
  enum Source: Equatable {
    case demo
  }

  private(set) var state: State = .loading
  var selection: SidebarItem? = .today
  let source: Source
  /// The last committed import; nil before one, or when it could not be read.
  private(set) var lastImport: ImportRun?
  /// The clock the import was timed by, so "updated …" counts from the same origin.
  let clock: ImportClock = DemoEnvironment.clock
  private let snapshot: URL?

  /// The unit tests run inside the app (`project.yml`), so every test run launches it.
  nonisolated static var isTestHost: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /// A test host always gets Demo, never a live source (CLAUDE.md rule 5). S4-4c adds Live
  /// for any other launch whose setting says so; a test pins the test-host case.
  nonisolated static func source(isTestHost: Bool) -> Source {
    _ = isTestHost
    return .demo
  }

  init(
    snapshot: URL? = DemoEnvironment.bundledSnapshot, isTestHost: Bool = AppModel.isTestHost
  ) {
    self.snapshot = snapshot
    source = Self.source(isTestHost: isTestHost)
  }

  func load() async {
    guard let snapshot else {
      state = .unavailable
      return
    }
    do {
      let loaded = try await DemoEnvironment.load(snapshot: snapshot)
      lastImport = loaded.lastImport
      state = .loaded(loaded.overview)
    } catch {
      state = .unavailable
    }
  }

  /// Read again on every minute's tick of the status bar.
  func freshness() -> Freshness? {
    lastImport.map { Freshness(finishedAt: $0.finishedAt, now: clock.wall()) }
  }
}
