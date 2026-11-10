import AppKit
import Foundation
import MoonShineCore
import Observation

enum SidebarItem: Hashable {
  case today
}

/// The app's settings. Tests pass their own; `StandardSettings` reads and writes nothing in a
/// test host, whose defaults domain is the owner's app's (`dev.moonshine.mac`).
protocol AppSettings {
  var source: String? { get }
  func setSource(_ value: String)
  /// The vault folder's bookmark (S4-4d); nil while none is chosen.
  var vaultBookmark: StoredBookmark? { get }
  func setVaultBookmark(_ value: StoredBookmark)
}

/// The vault folder's bookmark, its name and when it was chosen: one value under one key, so a
/// reader never pairs new data with an old time (S4-4d). Kept in the app's defaults only.
struct StoredBookmark: Codable, Equatable, Sendable {
  var data: Data
  /// The folder's own name, which the Settings row shows; never its path.
  var name: String
  var savedAt: Date
}

/// Where `StandardSettings` keeps its values; tests pass an in-memory one.
protocol SettingsStorage {
  func string(forKey key: String) -> String?
  func data(forKey key: String) -> Data?
  func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStorage {}

struct StandardSettings: AppSettings {
  private static let sourceKey = "source"
  private static let vaultKey = "vaultBookmark"
  private let storage: any SettingsStorage
  private let isTestHost: Bool

  init(
    storage: any SettingsStorage = UserDefaults.standard, isTestHost: Bool = AppModel.isTestHost
  ) {
    self.storage = storage
    self.isTestHost = isTestHost
  }

  var source: String? {
    isTestHost ? nil : storage.string(forKey: Self.sourceKey)
  }

  func setSource(_ value: String) {
    guard !isTestHost else { return }
    storage.set(value, forKey: Self.sourceKey)
  }

  var vaultBookmark: StoredBookmark? {
    guard !isTestHost, let data = storage.data(forKey: Self.vaultKey) else { return nil }
    return try? PropertyListDecoder().decode(StoredBookmark.self, from: data)
  }

  func setVaultBookmark(_ value: StoredBookmark) {
    guard !isTestHost, let data = try? PropertyListEncoder().encode(value) else { return }
    storage.set(data, forKey: Self.vaultKey)
  }
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

  /// Where Today's data comes from (the setting `source`).
  enum Source: String, CaseIterable {
    case demo
    case live
  }

  var selection: SidebarItem? = .today
  private(set) var source: Source
  private var feeds: [Source: SourceFeed] = [:]
  private let environments: @MainActor (Source) -> AppEnvironment?
  private let settings: any AppSettings
  private let isTestHost: Bool
  private var termination: (any NSObjectProtocol)?
  private var closed = false
  /// The vault folder Live reads (S4-4d).
  let vaultFolder: VaultFolder
  /// Why the last folder picked was not kept; cleared by a kept one.
  private(set) var vaultRefusal: VaultFolder.Refusal?

  /// The unit tests run inside the app (`project.yml`), so every test run launches it.
  nonisolated static var isTestHost: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /// A test host always gets Demo, before any setting is read (CLAUDE.md rule 5); any other
  /// launch gets Live when the setting says `live`.
  nonisolated static func source(isTestHost: Bool, settings: any AppSettings) -> Source {
    guard !isTestHost else { return .demo }
    return settings.source == Source.live.rawValue ? .live : .demo
  }

  /// `environments` builds a source's environment on its first selection, once per process.
  /// Live's environment reads `vaultFolder`, which keeps its bookmark in `settings`.
  init(
    isTestHost: Bool = AppModel.isTestHost, settings: any AppSettings,
    vaultFolder: VaultFolder? = nil,
    environments: @escaping @MainActor (Source) -> AppEnvironment?
  ) {
    self.isTestHost = isTestHost
    self.settings = settings
    self.environments = environments
    self.vaultFolder = vaultFolder ?? VaultFolder(settings: settings)
    source = Self.source(isTestHost: isTestHost, settings: settings)
  }

  /// Demo only, with no settings.
  convenience init(environment: AppEnvironment?, isTestHost: Bool = AppModel.isTestHost) {
    self.init(
      isTestHost: isTestHost, settings: NoSettings(),
      environments: { $0 == .demo ? environment : nil })
  }

  convenience init(
    snapshot: URL? = DemoEnvironment.bundledSnapshot, isTestHost: Bool = AppModel.isTestHost
  ) {
    self.init(
      environment: snapshot.flatMap { try? AppEnvironment.demo(snapshot: $0) },
      isTestHost: isTestHost)
  }

  /// The app's own: the setting, the bundled Demo and Live in Application Support.
  static func production() -> AppModel {
    let settings = StandardSettings()
    let vault = VaultFolder(settings: settings)
    let model = AppModel(settings: settings, vaultFolder: vault) { source in
      switch source {
      case .demo:
        DemoEnvironment.bundledSnapshot.flatMap { try? AppEnvironment.demo(snapshot: $0) }
      case .live:
        applicationSupport().flatMap { AppEnvironment.live(base: $0, vault: vault) }
      }
    }
    model.closeStores(onTerminationOf: .default)
    return model
  }

  /// Quit closes every store built, so its data is in the main file (the #46 follow-up). The
  /// block runs on the posting thread, the main one, before the app exits.
  func closeStores(onTerminationOf center: NotificationCenter) {
    termination = center.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: nil
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.closeStores() }
    }
  }

  /// Once; a source never selected is not built for it.
  func closeStores() {
    guard !closed else { return }
    closed = true
    for feed in feeds.values { feed.environment?.close?() }
  }

  /// The data folder's base; only this entry point and the CLI's name it.
  private static func applicationSupport() -> URL? {
    try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
  }

  private var feed: SourceFeed? { feeds[source] }
  var state: State { feed?.state ?? .loading }
  var lastImport: ImportRun? { feed?.lastImport }
  var clock: ImportClock { feed?.clock ?? DemoEnvironment.clock }
  var isImporting: Bool { feed?.isImporting ?? false }
  var importOutcomes: Int { feed?.importOutcomes ?? 0 }
  var droppedRequests: Int { feed?.droppedRequests ?? 0 }
  var omniFocusState: OmniFocusState? { feed?.omniFocusState }
  var lastFailure: ImportFailure? { feed?.lastFailure }
  var omniFocusNote: SourceFeed.OmniFocusNote? { feed?.omniFocusNote }
  /// Nil when the source's environment could not be built.
  var mapping: MappingState? { feed?.environment?.mapping }
  var storeUnreadable: Bool { feed?.storeUnreadable ?? false }
  var storeChecked: Bool { feed?.storeChecked ?? false }
  var heldLineRemoval: [Line] { feed?.heldLineRemoval ?? [] }
  var removalApproved: Bool { feed?.removalApproved ?? false }
  var removalKept: Bool { feed?.removalKept ?? false }

  /// Starts the selected source's feed. Idempotent.
  func start() {
    feed(for: source).start()
  }

  /// The Settings picker. The first selection of a source starts its feed (a launch import);
  /// a switch back to it imports as ⌘R does (owner, 2026-11-05). The source left imports
  /// nothing until then (owner, 2026-11-07). A test host never selects Live and never writes
  /// the setting.
  func select(_ new: Source) {
    guard new != source, !(isTestHost && new == .live) else { return }
    settings.setSource(new.rawValue)
    feeds[source]?.pause()
    source = new
    if let feed = feeds[new] { feed.refresh() } else { feed(for: new).start() }
  }

  /// ⌘R.
  func refresh() {
    feed?.refresh()
  }

  /// Remove N lines: approves exactly the held set and imports as ⌘R (S4-4e).
  func approveHeldRemoval() {
    feed?.approveHeldRemoval()
  }

  /// The folder a picker returned (S4-4d): kept when it is an Obsidian vault, then read at once
  /// in Live; otherwise nothing is saved and the row says why.
  func chooseVault(_ url: URL) {
    do throws(VaultFolder.Refusal) {
      try vaultFolder.choose(url)
      vaultRefusal = nil
      if source == .live { refresh() }
    } catch {
      vaultRefusal = error
    }
  }

  /// For tests: `start()`, then wait until the first import has ended (bounded).
  func load() async {
    start()
    guard feed?.environment != nil else { return }
    for _ in 0..<1_000 where importOutcomes == 0 {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  private func feed(for source: Source) -> SourceFeed {
    if let feed = feeds[source] { return feed }
    let feed = SourceFeed(environment: environments(source))
    feeds[source] = feed
    return feed
  }

  /// Read again on every minute's tick of the status bar.
  func freshness() -> Freshness? {
    lastImport.map { Freshness(finishedAt: $0.finishedAt, now: clock.wall()) }
  }
}

/// No setting is read or written.
struct NoSettings: AppSettings {
  var source: String? { nil }
  func setSource(_ value: String) {}
  var vaultBookmark: StoredBookmark? { nil }
  func setVaultBookmark(_ value: StoredBookmark) {}
}
