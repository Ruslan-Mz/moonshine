import Foundation
import Observation

enum SidebarItem: Hashable {
  case today
}

@MainActor @Observable
final class AppModel {
  enum State: Equatable {
    case loading
    case loaded(TodayScreen)
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
      state = .loaded(TodayScreen(try await DemoEnvironment.overview(snapshot: snapshot)))
    } catch {
      state = .unavailable
    }
  }
}
