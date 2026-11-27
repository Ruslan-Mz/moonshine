import AppKit
import CalendarAdapter
import Foundation
import MoonShineCore
import Observation

/// The app's settings. Tests pass their own; `StandardSettings` reads and writes nothing in a
/// test host, whose defaults domain is the owner's app's (`dev.moonshine.mac`).
protocol AppSettings {
  var source: String? { get }
  func setSource(_ value: String)
  /// The vault folder's bookmark (S4-4d); nil while none is chosen.
  var vaultBookmark: StoredBookmark? { get }
  func setVaultBookmark(_ value: StoredBookmark)
  /// Which due dates are deadlines (S4-3c-2); all due dates while none is stored.
  var deadlineRule: DeadlineRule { get }
  func setDeadlineRule(_ value: DeadlineRule)
  /// Show and Counts as busy per calendar (S4-3d), each entry checked on read.
  var calendarVisibility: CalendarVisibility { get }
  /// Stores one calendar's setting; every other stored entry stays as it is.
  func setCalendarSetting(_ value: CalendarSetting, for id: CalendarID)
  /// The span of the Day rail and the free term (S4-3d); `DayWindow.standard` while none is
  /// stored or the stored one is not valid.
  var dayWindow: DayWindow { get }
  func setDayWindow(_ value: DayWindow)
  /// When `Not now` was pressed on Today's calendar row (S4-3d); nil when never.
  var calendarNotNow: Date? { get }
  func setCalendarNotNow(_ value: Date)
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
  /// The rule's mode and tag apart: each is meaningful alone, so a reader never pairs them
  /// wrongly (S4-3c-2).
  private static let deadlineModeKey = "deadlineMode"
  private static let deadlineTagKey = "deadlineTag"
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

  /// An absent or unknown mode reads as all due dates, the spec's default; an absent tag as
  /// `deadline`.
  var deadlineRule: DeadlineRule {
    guard !isTestHost else { return .allDueDates }
    let mode = storage.string(forKey: Self.deadlineModeKey).flatMap(DeadlineRule.Mode.init)
    return DeadlineRule(
      mode: mode ?? .allDueDates, tag: storage.string(forKey: Self.deadlineTagKey) ?? "")
  }

  func setDeadlineRule(_ value: DeadlineRule) {
    guard !isTestHost else { return }
    storage.set(value.mode.rawValue, forKey: Self.deadlineModeKey)
    storage.set(value.tag, forKey: Self.deadlineTagKey)
  }

  /// Read in key order; an entry without both booleans, or with an id the system would not
  /// give (empty, longer than 256 bytes), is left out, and so is everything after 500 entries.
  var calendarVisibility: CalendarVisibility {
    guard !isTestHost, let data = storage.data(forKey: Self.calendarSettingsKey),
      let entries = try? JSONDecoder().decode([String: StoredCalendarSetting].self, from: data)
    else { return CalendarVisibility() }
    let read = entries.keys.sorted().lazy
      .filter(Self.isStorable)
      .compactMap { id in entries[id]?.setting.map { (CalendarID(id), $0) } }
      .prefix(Self.calendarSettingsLimit)
    return CalendarVisibility(Dictionary(read, uniquingKeysWith: { first, _ in first }))
  }

  /// Replaces this calendar's entry only: entries the read ignores stay as stored. Bytes the
  /// read accepts but `JSONSerialization` does not (a number out of range) keep the entries the
  /// read shows. A new calendar past the 500 entries the read takes is not stored: it could
  /// never be read back.
  func setCalendarSetting(_ value: CalendarSetting, for id: CalendarID) {
    guard !isTestHost, Self.isStorable(id.rawValue) else { return }
    let readable = calendarVisibility.stored
    guard readable[id] != nil || readable.count < Self.calendarSettingsLimit else { return }
    let data = storage.data(forKey: Self.calendarSettingsKey)
    let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    var entries: [String: Any]
    if let object {
      entries = object
    } else {
      entries = [:]
      for (id, setting) in readable {
        entries[id.rawValue] = ["show": setting.show, "busy": setting.countsAsBusy]
      }
    }
    entries[id.rawValue] = ["show": value.show, "busy": value.countsAsBusy]
    guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .sortedKeys)
    else { return }
    storage.set(data, forKey: Self.calendarSettingsKey)
  }

  /// A window off the quarter hour is not one Settings offers: it reads as the standard one.
  var dayWindow: DayWindow {
    guard !isTestHost, let data = storage.data(forKey: Self.dayWindowKey),
      let stored = try? JSONDecoder().decode(StoredDayWindow.self, from: data),
      stored.start % Self.windowStep == 0, stored.end % Self.windowStep == 0,
      let window = DayWindow(startMinute: stored.start, endMinute: stored.end)
    else { return .standard }
    return window
  }

  func setDayWindow(_ value: DayWindow) {
    guard !isTestHost, value.startMinute % Self.windowStep == 0,
      value.endMinute % Self.windowStep == 0,
      let data = try? JSONEncoder().encode(
        StoredDayWindow(start: value.startMinute, end: value.endMinute))
    else { return }
    storage.set(data, forKey: Self.dayWindowKey)
  }

  var calendarNotNow: Date? {
    guard !isTestHost, let data = storage.data(forKey: Self.calendarNotNowKey) else { return nil }
    return (try? JSONDecoder().decode(StoredDay.self, from: data))?.day
  }

  func setCalendarNotNow(_ value: Date) {
    guard !isTestHost, let data = try? JSONEncoder().encode(StoredDay(day: value)) else { return }
    storage.set(data, forKey: Self.calendarNotNowKey)
  }

  /// One value per setting under its own key (S4-3d), each checked on read.
  private static let calendarSettingsKey = "calendarSettings"
  private static let dayWindowKey = "dayWindow"
  private static let calendarNotNowKey = "calendarNotNow"
  private static let calendarSettingsLimit = 500
  private static let windowStep = 15

  private static func isStorable(_ id: String) -> Bool {
    (1...256).contains(id.utf8.count)
  }
}

/// One stored calendar entry; anything but both booleans reads as none, so one bad entry never
/// hides the others.
private struct StoredCalendarSetting: Decodable {
  let setting: CalendarSetting?

  private enum Key: String, CodingKey {
    case show, busy
  }

  init(from decoder: any Decoder) throws {
    guard let container = try? decoder.container(keyedBy: Key.self),
      let show = try? container.decode(Bool.self, forKey: .show),
      let busy = try? container.decode(Bool.self, forKey: .busy)
    else {
      setting = nil
      return
    }
    setting = CalendarSetting(show: show, countsAsBusy: busy)
  }
}

private struct StoredDayWindow: Codable {
  let start: Int
  let end: Int
}

private struct StoredDay: Codable {
  let day: Date
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
  /// Which due dates are deadlines; every source's overview is built with it (S4-3c-2).
  private(set) var deadlineRule: DeadlineRule
  /// The one way the app opens a task, project or note (S4-5).
  let linkOpener: LinkOpener
  private let calendarProviders: @MainActor (Source) -> any CalendarProvider
  /// Built on a source's first use, like its feed; ignored, so a view's read may build one.
  @ObservationIgnored private var calendarFeeds: [Source: CalendarFeed] = [:]
  /// Live's stored calendar rules, read at launch (S4-3d).
  private(set) var liveCalendarVisibility: CalendarVisibility
  private(set) var liveDayWindow: DayWindow
  /// When Today's `Not now` was pressed; nil when never.
  private(set) var calendarNotNow: Date?

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

  /// Live reads the system calendars outside the test host only; the test host gets Demo's
  /// whatever the source (CLAUDE.md rule 5), and `live` is not called then.
  nonisolated static func calendarProvider(
    for source: Source, isTestHost: Bool, live: () -> any CalendarProvider
  ) -> any CalendarProvider {
    source == .live && !isTestHost ? live() : DemoEnvironment.calendarProvider()
  }

  /// `environments` builds a source's environment on its first selection, once per process.
  /// Live's environment reads `vaultFolder`, which keeps its bookmark in `settings`. `calendars`
  /// builds a source's calendar provider on its first use; only `production()` names the
  /// system's, so no test reaches a live calendar store (CLAUDE.md rule 5).
  init(
    isTestHost: Bool = AppModel.isTestHost, settings: any AppSettings,
    vaultFolder: VaultFolder? = nil,
    linkOpener: @MainActor (VaultFolder) -> LinkOpener = LinkOpener.production,
    calendars: @escaping @MainActor (Source) -> any CalendarProvider = { _ in
      DemoEnvironment.calendarProvider()
    },
    environments: @escaping @MainActor (Source) -> AppEnvironment?
  ) {
    self.isTestHost = isTestHost
    self.settings = settings
    self.environments = environments
    calendarProviders = calendars
    let vaultFolder = vaultFolder ?? VaultFolder(settings: settings)
    self.vaultFolder = vaultFolder
    self.linkOpener = linkOpener(vaultFolder)
    source = Self.source(isTestHost: isTestHost, settings: settings)
    deadlineRule = settings.deadlineRule
    liveCalendarVisibility = settings.calendarVisibility
    liveDayWindow = settings.dayWindow
    calendarNotNow = settings.calendarNotNow
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
    let model = AppModel(
      settings: settings, vaultFolder: vault,
      calendars: {
        calendarProvider(for: $0, isTestHost: isTestHost, live: { EventKitCalendarProvider() })
      },
      environments: { source in
        switch source {
        case .demo:
          DemoEnvironment.bundledSnapshot.flatMap { try? AppEnvironment.demo(snapshot: $0) }
        case .live:
          applicationSupport().flatMap { AppEnvironment.live(base: $0, vault: vault) }
        }
      })
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

  /// Starts the selected source's feed and calendar. Idempotent.
  func start() {
    feed(for: source).start()
    calendar.resume()
  }

  /// The Settings picker. The first selection of a source starts its feed (a launch import);
  /// a switch back to it imports as ⌘R does (owner, 2026-11-05). The source left imports
  /// nothing until then (owner, 2026-11-07). A test host never selects Live and never writes
  /// the setting.
  func select(_ new: Source) {
    guard new != source, !(isTestHost && new == .live) else { return }
    settings.setSource(new.rawValue)
    feeds[source]?.pause()
    calendarFeeds[source]?.pause()
    source = new
    if let feed = feeds[new] { feed.refresh() } else { feed(for: new).start() }
    calendar.resume()
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

  /// Opens a task, project or note of the workspace shown, through the one opener; nothing
  /// while no workspace is shown, except System Settings, which needs none (S4-3d); nothing in
  /// Demo (owner, 2026-11-25). The task is for tests.
  @discardableResult
  func open(_ target: OpenTarget) -> Task<OpenOutcome, Never>? {
    var overview: Overview?
    if case .loaded(let shown) = state { overview = shown }
    guard overview != nil || target == .calendarPrivacySettings else { return nil }
    let isDemo = source == .demo
    return Task { await linkOpener.open(target, in: overview, isDemo: isDemo) }
  }

  /// The selected source's calendar.
  var calendar: CalendarFeed {
    if let feed = calendarFeeds[source] { return feed }
    let feed = CalendarFeed(provider: calendarProviders(source))
    calendarFeeds[source] = feed
    return feed
  }

  /// Show and Counts as busy: Demo's invented ones, in memory only; Live's stored (owner,
  /// 2026-11-27).
  var calendarVisibility: CalendarVisibility {
    source == .demo ? DemoEnvironment.calendarVisibility : liveCalendarVisibility
  }

  /// Demo always spans 08:00–22:00, as `design/demo-data.md` draws it (owner, 2026-11-27).
  var dayWindow: DayWindow { source == .demo ? .standard : liveDayWindow }

  /// What the Day rail reads, in `calendar`'s zone (Today's).
  func dayRailInput(calendar zone: Calendar) -> DayRailInput {
    let feed = calendar
    var input = DayRailInput(
      events: feed.events, visibility: calendarVisibility, calendars: feed.calendars,
      window: dayWindow, isFrozen: source == .demo)
    input.row = CalendarRow(
      access: feed.access, notNow: calendarNotNow, now: clock.wall(), calendar: zone)
    input.isConnecting = feed.isConnecting
    input.connect = { [weak self] in self?.calendar.connect() }
    input.notNow = { [weak self] in self?.calendarNotNowPressed() }
    return input
  }

  /// Today's day, which the calendar reads.
  func showCalendarDay(_ day: DateInterval) {
    calendar.show(day: day)
  }

  /// Today's `Not now`: the connect row hides for 30 days, in every window (owner, 2026-11-27).
  func calendarNotNowPressed() {
    let now = clock.wall()
    calendarNotNow = now
    settings.setCalendarNotNow(now)
  }

  /// Settings → Deadlines: stored, then every source built shows it at once, without an import.
  func setDeadlineRule(_ rule: DeadlineRule) {
    guard rule != deadlineRule else { return }
    deadlineRule = rule
    settings.setDeadlineRule(rule)
    for feed in feeds.values { feed.deadlineRule = rule }
  }

  /// The Tag field's draft, committed with the current mode; returns the tag stored, which the
  /// field then shows (an empty draft shows `deadline`). An unchanged draft writes nothing.
  func commitDeadlineTag(_ draft: String) -> String {
    setDeadlineRule(DeadlineRule(mode: deadlineRule.mode, tag: draft))
    return deadlineRule.tag
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
    let feed = SourceFeed(environment: environments(source), deadlineRule: deadlineRule)
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
  var deadlineRule: DeadlineRule { .allDueDates }
  func setDeadlineRule(_ value: DeadlineRule) {}
  var calendarVisibility: CalendarVisibility { CalendarVisibility() }
  func setCalendarSetting(_ value: CalendarSetting, for id: CalendarID) {}
  var dayWindow: DayWindow { .standard }
  func setDayWindow(_ value: DayWindow) {}
  var calendarNotNow: Date? { nil }
  func setCalendarNotNow(_ value: Date) {}
}
