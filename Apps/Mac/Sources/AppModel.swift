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

  private(set) var state: State = .loading
  var selection: SidebarItem? = .today
  private let snapshot: URL?

  init(snapshot: URL? = DemoEnvironment.bundledSnapshot) {
    self.snapshot = snapshot
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
