import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import MoonShineMac

/// Settings → Calendars (S4-3d-2): the access row, the calendars by account, the day window, the
/// switches in Demo and Live, the reopen sentence and identical events on the rail.
@Suite(.serialized) struct CalendarsSettingsViewTests {
  static let english = Locale(identifier: "en")
  static let russian = Locale(identifier: "ru")
  static let reopenEN = "Then reopen MoonShine."
  static let reopenRU = "Затем перезапустите MoonShine."

  func text(_ resource: LocalizedStringResource?, _ locale: Locale = english) -> String? {
    resource.map { CalendarAccessLine.string($0, in: locale) }
  }

  // MARK: The access row

  @Test func eachAccessStateHasItsLine() {
    #expect(CalendarAccessLine(nil) == nil)
    #expect(CalendarAccessLine(.notDetermined) == .notConnected)
    #expect(CalendarAccessLine(.granted) == .connected)
    #expect(CalendarAccessLine(.denied) == .denied)
    #expect(CalendarAccessLine(.writeOnly) == .eventsOnly)
    #expect(CalendarAccessLine(.restricted) == .restricted)
  }

  @Test func theLinesSayTheDesignsWords() {
    let lines = CalendarAccessLine.allCases
    #expect(
      lines.map { text($0.label) } == [
        "Not connected", "Connected", "Access denied", "Can't read events", "Not available",
      ])
    #expect(
      lines.map { text($0.button) } == [
        "Connect calendars…", "Open System Settings…", "Open System Settings",
        "Open System Settings", nil,
      ])
    #expect(
      lines.map(\.action) == [.connect, .systemSettings, .systemSettings, .systemSettings, nil])
    #expect(
      text(CalendarAccessLine.notConnected.caption)
        == "MoonShine asks macOS for read-only access. Nothing is created or edited. "
        + "The app works fully without it.")
    #expect(
      text(CalendarAccessLine.connected.caption)
        == "MoonShine reads events through macOS (EventKit), read-only.")
    #expect(
      text(CalendarAccessLine.restricted.caption)
        == "Calendar access is restricted on this device, for example by a device-management "
        + "profile. Today, Week and Month work without events.")
    #expect(
      text(CalendarAccessLine.restricted.label, Self.russian) == "Недоступно")
  }

  /// Where access is turned on in System Settings, the caption says to reopen, after the
  /// sentence that names System Settings (owner, 2026-11-27, the live check of #74).
  @Test func deniedAndAddEventsOnlySayToReopen() {
    #expect(
      text(CalendarAccessLine.denied.caption)
        == "Calendar access is off for MoonShine. Allow it in System Settings → Privacy & "
        + "Security → Calendars. Then reopen MoonShine. Today, Week and Month work without events.")
    #expect(
      text(CalendarAccessLine.eventsOnly.caption)
        == "MoonShine can only read calendars with Full Access. Change it in System Settings → "
        + "Privacy & Security → Calendars. Then reopen MoonShine. Today, Week and Month work "
        + "without events.")
    for line in CalendarAccessLine.allCases {
      let reopens = line == .denied || line == .eventsOnly
      #expect(text(line.caption)?.contains(Self.reopenEN) == reopens)
      #expect(text(line.caption, Self.russian)?.contains(Self.reopenRU) == reopens)
    }
  }

  @Test func todaysOffRowsSayToReopenAfterTheLink() {
    #expect(CalendarRow.off.reopens)
    #expect(CalendarRow.fullAccessOnly.reopens)
    #expect(!CalendarRow.connect.reopens)
    #expect(CalendarRow.reopen(in: Self.english) == Self.reopenEN)
    #expect(CalendarRow.reopen(in: Self.russian) == Self.reopenRU)
  }

  // MARK: The calendars

  @Test func calendarsAreGroupedByAccountInTheirOrder() {
    let groups = CalendarGroup.groups(DemoCalendar.calendars)
    #expect(groups.map(\.account) == ["iCloud", "Work · Exchange", "Subscribed"])
    #expect(groups.map(\.calendars.count) == [4, 1, 1])
    #expect(groups.flatMap(\.calendars) == DemoCalendar.calendars)
    let mixed = [
      Self.calendar("a", account: "Invented one"), Self.calendar("b", account: nil),
      Self.calendar("c", account: "Invented one"),
    ]
    #expect(
      CalendarGroup.groups(mixed).map { $0.calendars.map(\.id.rawValue) } == [["a", "c"], ["b"]])
  }

  /// Two accounts with one title are two sections: they are told apart by their identifier.
  @Test func accountsThatShareATitleAreTwoGroups() {
    let calendars = [
      Self.calendar("a", account: "Invented", accountID: "one"),
      Self.calendar("b", account: "Invented", accountID: "two"),
      Self.calendar("c", account: "Invented", accountID: "one"),
    ]
    #expect(
      CalendarGroup.groups(calendars).map { $0.calendars.map(\.id.rawValue) } == [
        ["a", "c"], ["b"],
      ])
  }

  static func calendar(_ id: String, account: String?, accountID: String? = nil) -> CalendarInfo {
    CalendarInfo(
      id: CalendarID(id), title: "Invented", account: account, colorHex: nil, kind: .other,
      accountID: accountID)
  }

  // MARK: The day window

  @Test func theStartsAreQuarterHoursOfTheDay() {
    #expect(DayWindowChoice.starts.first == 0)
    #expect(DayWindowChoice.starts.last == 23 * 60 + 45)
    #expect(DayWindowChoice.starts.count == 96)
    #expect(DayWindowChoice.starts.allSatisfy { $0 % 15 == 0 })
  }

  @Test(arguments: [0, 8 * 60, 22 * 60 + 30, 23 * 60 + 45])
  func theEndNeverOffersATimeAtOrBeforeTheStart(_ start: Int) {
    let ends = DayWindowChoice.ends(after: start)
    #expect(ends.first == start + 15)
    #expect(ends.last == 24 * 60)
    #expect(ends.allSatisfy { $0 > start && $0 % 15 == 0 })
  }

  @Test func aStartAtOrAfterTheEndMovesTheEnd() throws {
    func window(_ start: Int, _ end: Int) -> DayWindow? {
      DayWindow(startMinute: start, endMinute: end)
    }
    #expect(DayWindowChoice.window(start: 7 * 60, end: 23 * 60) == window(420, 1380))
    #expect(DayWindowChoice.window(start: 22 * 60, end: 22 * 60) == window(1320, 1335))
    #expect(DayWindowChoice.window(start: 23 * 60, end: 9 * 60) == window(1380, 1395))
    #expect(DayWindowChoice.window(start: 23 * 60 + 50, end: 24 * 60) == nil)
  }

  @Test func theLabelsAreTwentyFourHour() {
    #expect(DayWindowChoice.label(0) == "00:00")
    #expect(DayWindowChoice.label(8 * 60) == "08:00")
    #expect(DayWindowChoice.label(22 * 60 + 45) == "22:45")
    #expect(DayWindowChoice.label(24 * 60) == "24:00")
  }

  // MARK: The switches and the window, in Demo and Live

  static let music = CalendarID("demo-music-lessons")

  @MainActor func liveModel(_ storage: RecordingStorage) -> AppModel {
    storage.set(AppModel.Source.live.rawValue, forKey: "source")
    return AppModel(
      isTestHost: false, settings: StandardSettings(storage: storage, isTestHost: false),
      environments: { _ in nil })
  }

  /// Demo's switches act in memory and store nothing (owner, 2026-11-27).
  @MainActor @Test func demosSwitchesStoreNothing() {
    let storage = RecordingStorage()
    let model = AppModel(
      isTestHost: false, settings: StandardSettings(storage: storage, isTestHost: false),
      environments: { _ in nil })
    #expect(model.source == .demo)
    let off = CalendarSetting(show: true, countsAsBusy: false)
    model.setCalendarSetting(off, for: Self.music)
    #expect(model.calendarVisibility.stored[Self.music] == off)
    #expect(!storage.writes.contains("calendarSettings"))
    model.setDayWindow(DayWindow(startMinute: 7 * 60, endMinute: 23 * 60)!)
    #expect(model.dayWindow == .standard)
    #expect(!storage.writes.contains("dayWindow"))
  }

  @MainActor @Test func livesSwitchesAndWindowAreStoredAndReadBack() throws {
    let storage = RecordingStorage()
    let model = liveModel(storage)
    #expect(model.source == .live)
    let hidden = CalendarSetting(show: false, countsAsBusy: true)
    model.setCalendarSetting(hidden, for: Self.music)
    #expect(model.calendarVisibility.stored[Self.music] == hidden)
    let wide = try #require(DayWindow(startMinute: 7 * 60, endMinute: 23 * 60))
    model.setDayWindow(wide)
    #expect(model.dayWindow == wide)
    #expect(model.dayRailInput(calendar: DemoCalendar.calendar).window == wide)
    let again = liveModel(storage)
    #expect(again.calendarVisibility.stored[Self.music] == hidden)
    #expect(again.dayWindow == wide)
  }

  /// What shows is what is stored: a write the settings refuse (an id the read would ignore, a
  /// window off the quarter hour) changes nothing shown.
  @MainActor @Test func aRefusedWriteShowsNothingNew() throws {
    let storage = RecordingStorage()
    let model = liveModel(storage)
    let tooLong = CalendarID(String(repeating: "x", count: 257))
    model.setCalendarSetting(CalendarSetting(show: false, countsAsBusy: false), for: tooLong)
    #expect(model.calendarVisibility.stored[tooLong] == nil)
    model.setDayWindow(try #require(DayWindow(startMinute: 7 * 60 + 10, endMinute: 23 * 60)))
    #expect(model.dayWindow == .standard)
    #expect(!storage.writes.contains("calendarSettings"))
    #expect(!storage.writes.contains("dayWindow"))
  }

  /// Counts as busy off changes the free-time facts and nothing else (`settings-calendars.md`
  /// § Acceptance): the Violin lesson stays on the rail and in the count.
  @MainActor @Test func countsAsBusyOffChangesOnlyTheTotals() async throws {
    let overview = try await demoOverview()
    let screen = TodayScreen(overview)
    let model = AppModel(isTestHost: true, settings: NoSettings()) { _ in nil }
    func rail() -> DayRail {
      screen.rail(
        now: overview.now,
        input: DayRailInput(
          events: .read(DemoCalendar.events, skipped: 0), visibility: model.calendarVisibility,
          calendars: DemoCalendar.calendars, window: model.dayWindow, isFrozen: true))
    }
    let before = rail()
    model.setCalendarSetting(CalendarSetting(show: true, countsAsBusy: false), for: Self.music)
    let after = rail()
    #expect(after.marks == before.marks)
    #expect(after.allDay == before.allDay)
    #expect(after.load.eventCount == before.load.eventCount)
    #expect(after.load.plannedMinutes == before.load.plannedMinutes)
    #expect(before.load.inCalendarMinutes == 240)
    #expect(after.load.inCalendarMinutes == 180)
    #expect(after.load.freeFromNowMinutes == (before.load.freeFromNowMinutes ?? 0) + 60)
  }

  // MARK: Identical events on the rail (owner, 2026-11-27)

  /// Two invented copies of the Violin lesson, one in another calendar: one row that reads its
  /// count, and the design's day fact unchanged.
  @MainActor @Test func copiesOfAnEventAreOneRowThatReadsItsCount() async throws {
    let overview = try await demoOverview()
    let screen = TodayScreen(overview)
    let violin = try #require(DemoCalendar.events.first { $0.title == "Violin lesson" })
    let copies = try ["demo-family", "demo-music-lessons"].enumerated().map { index, id in
      try #require(
        CalendarEvent(
          id: "invented-copy-\(index)", calendarID: CalendarID(id), calendarKind: .other,
          title: violin.title, start: violin.start, end: violin.end,
          timeZone: violin.timeZone))
    }
    let rail = screen.rail(
      now: overview.now,
      input: DayRailInput(
        events: .read(DemoCalendar.events + copies, skipped: 0),
        visibility: DemoCalendar.visibility, calendars: DemoCalendar.calendars,
        window: .standard, isFrozen: true))
    #expect(
      TodayFormat.dayFact(rail.load) == [
        .events(4), .inCalendar(.hours(4)), .planned(.hoursAndMinutes(1, 15)),
        .free(.hoursAndMinutes(2, 25), until: rail.load.window.end),
      ])
    let mark = try #require(
      rail.marks.first {
        if case .event(let event) = $0.kind { event.title == violin.title } else { false }
      })
    guard case .event(let shown) = mark.kind else { return }
    // All three count as busy: by calendar id, the Family copy stands for them.
    #expect(shown.calendarID == CalendarID("demo-family"))
    #expect(rail.copies(of: shown) == 3)
    let reading = RailReading(
      now: overview.now, dayStart: DemoCalendar.calendar.startOfDay(for: overview.now),
      zone: screen.timeZone, locale: Self.english, lines: screen.lineNames, selected: nil,
      copies: rail.copies)
    #expect(
      reading.row(mark) == "17:00 to 18:00, Violin lesson, event, in 40 minutes, "
        + "3 copies of this event")
    #expect(RailReading.copies(3, Self.russian) == "3 копии этого события")
    #expect(RailReading.copies(5, Self.russian) == "5 копий этого события")
  }
}
