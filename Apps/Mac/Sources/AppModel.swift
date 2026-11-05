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
  /// An import is running ("Updating…").
  private(set) var isImporting = false
  /// Imports that ended, committed or not.
  private(set) var importOutcomes = 0
  /// Nil until the coordinator knows it. Live says so (S4-4c-1); Demo shows nothing.
  private(set) var omniFocusState: OmniFocusState?
  /// Nil when it could not be built: Today is then unavailable.
  private let environment: AppEnvironment?
  private var starting: Task<Void, Never>?
  private var consumer: Task<Void, Never>?

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

  init(environment: AppEnvironment?, isTestHost: Bool = AppModel.isTestHost) {
    self.environment = environment
    source = Self.source(isTestHost: isTestHost)
  }

  convenience init(
    snapshot: URL? = DemoEnvironment.bundledSnapshot, isTestHost: Bool = AppModel.isTestHost
  ) {
    self.init(
      environment: snapshot.flatMap { try? AppEnvironment.demo(snapshot: $0) },
      isTestHost: isTestHost)
  }

  /// Shows what the store holds, then sends the launch and the source's signals. Idempotent.
  /// The work runs in a task the model keeps, so a window's cancelled `.task` never loses it.
  func start() {
    guard starting == nil else { return }
    guard let environment else {
      state = .unavailable
      return
    }
    consumer = Task {
      for await event in environment.coordinator.events { await apply(event) }
    }
    starting = Task {
      await showStored(environment.store)
      await environment.coordinator.handle(.launch)
      await environment.coordinator.run(environment.source)
    }
  }

  /// ⌘R.
  func refresh() {
    guard let coordinator = environment?.coordinator else { return }
    Task { await coordinator.handle(.manual) }
  }

  /// For tests: `start()`, then wait until the first import has ended (bounded).
  func load() async {
    start()
    guard environment != nil else { return }
    for _ in 0..<1_000 where importOutcomes == 0 {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  /// A store that never committed shows nothing yet; one that cannot read its imports still
  /// shows its data.
  private func showStored(_ store: any Store) async {
    let last: ImportRun?
    do {
      last = try await store.lastCommittedImport()
      if last == nil { return }
    } catch {
      last = nil
    }
    guard let workspace = try? await store.workspace(), case .loading = state else { return }
    lastImport = last
    state = .loaded(Overview(workspace: workspace, now: clock.wall()))
  }

  private func apply(_ event: RefreshEvent) async {
    switch event {
    case .started:
      isImporting = true
    case .committed:
      await reload()
      isImporting = false
      importOutcomes += 1
    case .notCommitted:
      if case .loading = state { state = .unavailable }
      isImporting = false
      importOutcomes += 1
    case .omniFocusNotRunning:
      break  // Live's sentence comes with S4-4c-1.
    case .omniFocusState(let new):
      omniFocusState = new
    }
  }

  /// The import is read on its own: a store that cannot read it loses only the freshness text.
  /// A failed read keeps what is shown, and with nothing shown Today is unavailable.
  private func reload() async {
    guard let store = environment?.store else { return }
    lastImport = try? await store.lastCommittedImport()
    do {
      state = .loaded(Overview(workspace: try await store.workspace(), now: clock.wall()))
    } catch {
      if case .loading = state { state = .unavailable }
    }
  }

  /// Read again on every minute's tick of the status bar.
  func freshness() -> Freshness? {
    lastImport.map { Freshness(finishedAt: $0.finishedAt, now: clock.wall()) }
  }
}
