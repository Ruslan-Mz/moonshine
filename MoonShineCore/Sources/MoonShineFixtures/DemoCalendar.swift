import Foundation
import MoonShineCore

/// Demo-mode calendars: week 40 of `design/demo-data.md` § Draft-3 (invented). Never calls
/// EventKit. W41 and the September Month events come with the slice that shows them (S5).
public struct DemoCalendar: CalendarProvider {
  public static let calendar = DemoVault.calendar
  /// Thu 1 Oct 2026, 16:20.
  public static let now = at(10, 1, 16, 20)

  public init() {}

  public func access() async -> CalendarAccess { .granted }
  public func requestAccess() async -> CalendarAccess { .granted }
  public func calendars() async -> CalendarRead<[CalendarInfo]> {
    .read(Self.calendars, skipped: 0)
  }

  public func events(in interval: DateInterval) async throws -> CalendarRead<[CalendarEvent]> {
    try CalendarRange.check(interval)
    return .read(Self.events.filter { $0.overlaps(interval) }, skipped: 0)
  }

  public func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  // MARK: Calendars (Settings, Demo)

  static let family = CalendarID("demo-family")
  static let music = CalendarID("demo-music-lessons")
  static let personal = CalendarID("demo-personal")
  static let birthdays = CalendarID("demo-birthdays")
  static let work = CalendarID("demo-work")
  static let holidays = CalendarID("demo-holidays")

  public static let calendars: [CalendarInfo] = [
    CalendarInfo(id: family, title: "Family", account: "iCloud", colorHex: "#E8A33D", kind: .other),
    CalendarInfo(
      id: music, title: "Music lessons", account: "iCloud", colorHex: "#9B6BD6", kind: .other),
    CalendarInfo(
      id: personal, title: "Personal", account: "iCloud", colorHex: "#3D8FE8", kind: .other),
    CalendarInfo(
      id: birthdays, title: "Birthdays", account: "iCloud", colorHex: "#8E8E93", kind: .birthdays),
    CalendarInfo(
      id: work, title: "Work", account: "Work · Exchange", colorHex: "#4CAF7A", kind: .other),
    CalendarInfo(
      id: holidays, title: "Holidays in Latvia", account: "Subscribed", colorHex: "#C75C5C",
      kind: .subscribed),
  ]

  /// Birthdays off; Holidays shown and not busy (`demo-data.md` § Draft-3, Settings).
  public static let visibility = CalendarVisibility([
    birthdays: CalendarSetting(show: false, countsAsBusy: false),
    holidays: CalendarSetting(show: true, countsAsBusy: false),
  ])

  // MARK: Week 40 (Mon 28 Sep – Sun 4 Oct 2026): 16 timed events + 1 two-day all-day event

  public static let events: [CalendarEvent] = [
    standUp(9, 28), event("Design review", work, at(9, 28, 14, 0), at(9, 28, 15, 30)),
    standUp(9, 29), event("Quarterly planning", work, at(9, 29, 15, 0), at(9, 29, 16, 30)),
    event("Dentist — kids", family, at(9, 29, 16, 0), at(9, 29, 17, 0)),
    standUp(9, 30), event("Physio", personal, at(9, 30, 12, 30), at(9, 30, 13, 30)),
    standUp(10, 1), event("Lunch with Marta", personal, at(10, 1, 13, 0), at(10, 1, 14, 0)),
    event("Violin lesson", music, at(10, 1, 17, 0), at(10, 1, 18, 0)),
    event("Parents' evening at school", family, at(10, 1, 18, 30), at(10, 1, 20, 0)),
    standUp(10, 2),
    event(
      "Sprint demo", work, at(10, 2, 15, 0), at(10, 2, 16, 0), display: .tentative,
      occupiesTime: false),
    event("Concert — string quartet", personal, at(10, 2, 19, 0), at(10, 2, 21, 0)),
    event("Weekend in Sigulda", family, at(10, 3, 0, 0), at(10, 5, 0, 0), isAllDay: true),
    event("Castle walk", family, at(10, 3, 11, 0), at(10, 3, 12, 30)),
    event("Call with parents", family, at(10, 4, 18, 0), at(10, 4, 19, 0)),
  ]

  static func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
  }

  private static func standUp(_ month: Int, _ day: Int) -> CalendarEvent {
    event("Team stand-up", work, at(month, day, 9, 30), at(month, day, 10, 0))
  }

  private static func event(
    _ title: String, _ calendarID: CalendarID, _ start: Date, _ end: Date,
    isAllDay: Bool = false, display: EventDisplay = .normal, occupiesTime: Bool = true
  ) -> CalendarEvent {
    CalendarEvent(
      id: "demo-\(calendarID.rawValue)-\(Int(start.timeIntervalSince1970))",
      calendarID: calendarID, title: title, start: start, end: end, isAllDay: isAllDay,
      display: display, occupiesTime: occupiesTime, timeZone: calendar.timeZone)!
  }
}
