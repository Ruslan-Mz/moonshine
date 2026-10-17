import Foundation
import MoonShineCore
import Testing

@testable import MoonShineFixtures

/// Invented cases in Europe/Riga (it has daylight saving; the demo zone has none).
struct RigaDay {
  static let zone = TimeZone(identifier: "Europe/Riga")!
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }()
  static let work = CalendarID("work")

  static func at(_ h: Int, _ m: Int = 0, _ s: Int = 0, day: Int = 1, month: Int = 10) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m, second: s))!
  }

  static func event(
    _ start: Date, _ end: Date, calendar: CalendarID = work, kind: CalendarKind = .other,
    allDay: Bool = false,
    display: EventDisplay = .normal, occupies: Bool = true
  ) -> CalendarEvent {
    CalendarEvent(
      id: UUID().uuidString, calendarID: calendar, calendarKind: kind, title: nil, start: start,
      end: end,
      isAllDay: allDay, display: display, occupiesTime: occupies)!
  }

  static func task(
    _ planned: Date?, estimate: Int?, status: TaskItemStatus = .available, due: Date? = nil
  ) -> TaskItem {
    TaskItem(
      id: .generate(), refs: [], title: "t", projectID: nil, parentTaskID: nil, tagIDs: [],
      status: status, flagged: false, plannedAt: planned, deferUntil: nil, dueAt: due,
      effectivePlannedAt: planned, effectiveDeferUntil: nil, effectiveDueAt: due,
      estimateMinutes: estimate, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
      line: .lifeOps)
  }

  static func load(
    _ events: [CalendarEvent] = [], tasks: [TaskItem] = [], now: Date = at(7),
    day: Date = at(12), window: DayWindow = .standard,
    visibility: CalendarVisibility = CalendarVisibility(),
    defaults: DefaultTimes = DefaultTimes(timeZone: zone, planned: TimeOfDay(hour: 9, minute: 0)),
    read: CalendarRead<[CalendarEvent]>? = nil, calendar: Calendar = calendar
  ) -> DayLoad {
    DayLoad.compute(
      day: day, now: now, window: window, events: read ?? .read(events, skipped: 0),
      visibility: visibility, tasks: tasks, defaultTimes: defaults,
      calendar: calendar)
  }
}

@Suite struct DemoDayLoadTests {
  func demoLoad(_ month: Int, _ day: Int, now: Date? = nil, tasks: [TaskItem] = []) -> DayLoad {
    DayLoad.compute(
      day: DemoCalendar.at(month, day, 12, 0), now: now ?? DemoCalendar.at(month, day, 7, 0),
      window: .standard, events: .read(DemoCalendar.events, skipped: 0),
      visibility: DemoCalendar.visibility, tasks: tasks,
      defaultTimes: DemoDay.defaultTimes, calendar: DemoCalendar.calendar)
  }

  @Test func thursdayAtSixTwentyMatchesTheDesign() {
    // `4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00`.
    let load = demoLoad(10, 1, now: DemoCalendar.now, tasks: DemoDay.tasks)
    #expect(load.eventCount == 4)
    #expect(load.inCalendarMinutes == 240)
    #expect(load.plannedMinutes == 75)
    #expect(load.freeFromNowMinutes == 145)
    #expect(load.freeWholeWindowMinutes == 525)
  }

  @Test func theDueTimesAreTimesAndOccupyNothing() {
    #expect(!DemoDay.defaultTimes.isDateOnly(DemoCalendar.at(10, 1, 18, 0), kind: .due))
    #expect(DemoDay.defaultTimes.isDateOnly(DemoCalendar.at(10, 1, 17, 0), kind: .due))
    let dueOnly = DemoDay.tasks.filter { $0.effectiveDueAt != nil }
    #expect(dueOnly.count == 2)
    #expect(dueOnly.allSatisfy { ($0.estimateMinutes ?? 0) > 0 })
    #expect(demoLoad(10, 1, tasks: dueOnly).plannedMinutes == 0)
  }

  @Test func theOtherDaysOfWeekForty() {
    let days = [(9, 28), (9, 29), (9, 30), (10, 2)].map { demoLoad($0.0, $0.1) }
    #expect(days.map(\.eventCount) == [2, 3, 2, 3])
    // Tue: the 16:00–16:30 overlap counts once; Fri: the tentative Sprint demo is not busy.
    #expect(days.map(\.inCalendarMinutes) == [120, 150, 90, 150])
    #expect(days.map(\.freeWholeWindowMinutes) == [720, 690, 750, 690])
    #expect(days.allSatisfy { $0.freeFromNowMinutes == $0.freeWholeWindowMinutes })
    // The weekend's all-day event is shown and not busy.
    #expect(demoLoad(10, 3).eventCount == 2)
    #expect(demoLoad(10, 3).inCalendarMinutes == 90)
    #expect(demoLoad(10, 4).inCalendarMinutes == 60)
  }
}

@Suite struct DayLoadRuleTests {
  typealias R = RigaDay

  @Test func anEventInProgressCountsOnlyItsRemainingPart() {
    let load = R.load([R.event(R.at(16), R.at(17))], now: R.at(16, 20))
    #expect(load.freeFromNowMinutes == 340 - 40)
    #expect(load.inCalendarMinutes == 60)
  }

  @Test func plannedCountsOnlyWhatNoEventCovers() {
    let event = R.event(R.at(13), R.at(14))
    let over = R.load([event], tasks: [R.task(R.at(13, 45), estimate: 30)])
    #expect(over.inCalendarMinutes == 60)
    #expect(over.plannedMinutes == 15)
    #expect(over.freeWholeWindowMinutes == 840 - 75)
    let inside = R.load([event], tasks: [R.task(R.at(13, 15), estimate: 30)])
    #expect(inside.plannedMinutes == 0)
    #expect(inside.freeWholeWindowMinutes == 840 - 60)
  }

  @Test func estimatesAndStatus() {
    #expect(R.load(tasks: [R.task(R.at(10), estimate: nil)]).plannedMinutes == 0)
    #expect(R.load(tasks: [R.task(R.at(10), estimate: 0)]).plannedMinutes == 0)
    #expect(R.load(tasks: [R.task(R.at(10), estimate: -5)]).plannedMinutes == 0)
    #expect(R.load(tasks: [R.task(R.at(21), estimate: .max)]).plannedMinutes == 60)
    let open = R.load(tasks: [R.task(R.at(10), estimate: 30)], now: R.at(11))
    let done = R.load(tasks: [R.task(R.at(10), estimate: 30, status: .completed)], now: R.at(11))
    #expect(open == done)
    #expect(R.load(tasks: [R.task(nil, estimate: 30, due: R.at(10))]).plannedMinutes == 0)
    // Children that inherit a timed parent start together and count once.
    let children = (0..<3).map { _ in R.task(R.at(14), estimate: 30) }
    #expect(R.load(tasks: children).plannedMinutes == 30)
    #expect(R.load(tasks: [R.task(R.at(10, day: 2), estimate: 30)]).plannedMinutes == 0)
  }

  @Test func nowBeforeAtAndAfterTheWindow() {
    let events = [R.event(R.at(13), R.at(14))]
    let before = R.load(events, now: R.at(7, 59))
    #expect(before.freeFromNowMinutes == before.freeWholeWindowMinutes)
    #expect(R.load(events, now: R.at(22)).freeFromNowMinutes == nil)
    #expect(R.load(events, now: R.at(23)).freeFromNowMinutes == nil)
    #expect(R.load(events, now: R.at(23)).freeWholeWindowMinutes == 780)
  }

  @Test func withoutAccessThereIsNoCalendarFact() {
    let load = R.load(
      tasks: [R.task(R.at(10), estimate: 30)], now: R.at(9), read: .unavailable(.denied))
    #expect(load.eventCount == nil)
    #expect(load.inCalendarMinutes == nil)
    #expect(load.freeWholeWindowMinutes == nil)
    #expect(load.freeFromNowMinutes == nil)
    #expect(load.plannedMinutes == 30)
  }

  @Test func calendarsAndEventKinds() {
    let hidden = CalendarID("hidden")
    let quiet = CalendarID("quiet")
    let holidays = CalendarID("holidays")
    let load = R.load(
      [
        R.event(R.at(9), R.at(10), calendar: hidden),
        R.event(R.at(10), R.at(11), calendar: quiet),
        R.event(R.at(11), R.at(12), calendar: holidays, kind: .subscribed),
        R.event(R.at(12), R.at(13), display: .tentative, occupies: false),
        R.event(R.at(0), R.at(0, day: 2), allDay: true),
        R.event(R.at(14), R.at(15), calendar: CalendarID("new, not yet listed")),
        // A birthday calendar read before the calendar list: its kind still gives the default.
        R.event(R.at(15), R.at(16), calendar: CalendarID("birthdays"), kind: .birthdays),
      ],
      visibility: CalendarVisibility([
        hidden: CalendarSetting(show: false, countsAsBusy: true),
        quiet: CalendarSetting(show: true, countsAsBusy: false),
      ]))
    #expect(load.eventCount == 6)
    #expect(load.inCalendarMinutes == 60)
  }

  @Test func eventsAreClippedToTheWindowAndCountedOnTheirDays() {
    let load = R.load([
      R.event(R.at(7), R.at(9)),
      R.event(R.at(23, day: 30, month: 9), R.at(8, 30)),
      R.event(R.at(21, 30), R.at(1, day: 2)),
      R.event(R.at(23), R.at(0, day: 2)),
      R.event(R.at(0, day: 2), R.at(0, day: 2)),
    ])
    #expect(load.eventCount == 4)
    #expect(load.inCalendarMinutes == 60 + 30)
  }

  @Test func minutesAddUpToTheWindowWithSecondsInTheInputs() {
    let load = R.load(
      [R.event(R.at(9, 0, 30), R.at(10, 15, 45)), R.event(R.at(12, 0, 59), R.at(12, 1, 1))],
      tasks: [R.task(R.at(10, 0, 20), estimate: 30)])
    #expect(load.inCalendarMinutes == 76)
    #expect(load.plannedMinutes == 15)
    #expect(load.freeWholeWindowMinutes == 749)
    #expect(
      (load.inCalendarMinutes ?? 0) + load.plannedMinutes + (load.freeWholeWindowMinutes ?? 0)
        == 840)
  }

  @Test func theWindowFollowsTheWallClockOnDaylightSavingDays() {
    let full = DayWindow(startMinute: 0, endMinute: 24 * 60)!
    for (month, day, fullMinutes) in [(3, 29, 1_380), (10, 25, 1_500)] {
      let noon = R.at(12, day: day, month: month)
      #expect(R.load(day: noon).freeWholeWindowMinutes == 840)
      #expect(
        R.load(now: R.at(0, day: day, month: month), day: noon, window: full)
          .freeWholeWindowMinutes == fullMinutes)
    }
  }

  @Test func onlyTasksPlannedOnTheDayCount() {
    let full = DayWindow(startMinute: 0, endMinute: 24 * 60)!
    let yesterday = R.task(R.at(23, 30, day: 30, month: 9), estimate: 60)
    let load = R.load(
      [R.event(R.at(23, 30, day: 30, month: 9), R.at(0, 30))], tasks: [yesterday], window: full)
    #expect(load.plannedMinutes == 0)
    #expect(load.inCalendarMinutes == 30)
  }

  @Test func nowAndTaskStartsAreFlooredToTheMinute() {
    let fromNow = R.load([R.event(R.at(17), R.at(18))], now: R.at(16, 20, 30))
    #expect(fromNow.freeFromNowMinutes == 340 - 60)
    let touching = R.load(
      [R.event(R.at(10, 30), R.at(11))], tasks: [R.task(R.at(10, 0, 20), estimate: 30)])
    #expect(touching.plannedMinutes == 30)
  }

  @Test func midnightIsTheEndOfTheDayWhereDaylightSavingStartsAtMidnight() {
    var santiago = Calendar(identifier: .gregorian)
    santiago.timeZone = TimeZone(identifier: "America/Santiago")!
    let noon = santiago.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
    let full = DayWindow(startMinute: 0, endMinute: 24 * 60)!
    let load = R.load(now: noon, day: noon, window: full, calendar: santiago)
    #expect(load.freeWholeWindowMinutes == 1_380)
    #expect(load.window == santiago.dateInterval(of: .day, for: noon))
  }

  @Test func dayWindowBounds() {
    #expect(DayWindow(startMinute: 480, endMinute: 480) == nil)
    #expect(DayWindow(startMinute: 600, endMinute: 480) == nil)
    #expect(DayWindow(startMinute: -1, endMinute: 480) == nil)
    #expect(DayWindow(startMinute: 0, endMinute: 1_441) == nil)
    #expect(DayWindow(startMinute: 0, endMinute: 1_440) != nil)
  }
}

@Suite struct DateOnlyTests {
  typealias R = RigaDay

  @Test func timeOfDayBounds() {
    for (h, m) in [(24, 0), (25, 0), (9, 60), (-1, 0), (0, -1)] {
      #expect(TimeOfDay(hour: h, minute: m) == nil)
    }
    #expect(TimeOfDay(hour: 23, minute: 59) != nil)
    #expect(TimeOfDay(hour: 0, minute: 0) != nil)
  }

  @Test func theDefaultTimeIsDateOnlyInTheSnapshotsZone() {
    let moscow = TimeZone(identifier: "Europe/Moscow")!
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
    var msk = Calendar(identifier: .gregorian)
    msk.timeZone = moscow
    func at(_ h: Int) -> Date {
      msk.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: h))!
    }
    let defaults = DefaultTimes(timeZone: moscow, planned: TimeOfDay(hour: 9, minute: 0))
    // 09:00 in Moscow is 08:00 in Berlin: still date only.
    let load = R.load(
      tasks: [R.task(at(9), estimate: 30), R.task(at(10), estimate: 20)], day: at(12),
      defaults: defaults, calendar: berlin)
    #expect(load.plannedMinutes == 20)
  }

  @Test func absentDefaultsLeaveOnlyMidnight() {
    let none = DefaultTimes(timeZone: R.zone)
    let full = DayWindow(startMinute: 0, endMinute: 24 * 60)!
    let load = R.load(
      tasks: [R.task(R.at(9), estimate: 30), R.task(R.at(0), estimate: 20)], window: full,
      defaults: none)
    #expect(load.plannedMinutes == 30)
    #expect(none.isDateOnly(R.at(0), kind: .due))
    #expect(!none.isDateOnly(R.at(17), kind: .due))
    let due = DefaultTimes(timeZone: R.zone, due: TimeOfDay(hour: 17, minute: 0))
    #expect(due.isDateOnly(R.at(17), kind: .due))
    #expect(!due.isDateOnly(R.at(17, 0, 30), kind: .due))
    #expect(!due.isDateOnly(R.at(18), kind: .due))
    #expect(due.isDateOnly(R.at(0), kind: .planned))
    #expect(!due.isDateOnly(R.at(17), kind: .planned))
  }
}

@Suite struct DemoDayTests {
  @Test func holdsTheSixTimedTasksOfTheDesign() {
    #expect(DemoDay.tasks.count == 6)
    #expect(DemoDay.tasks.map(\.estimateMinutes) == [15, 10, 20, 45, 10, 30])
    #expect(DemoDay.tasks.filter { $0.status == .completed }.count == 2)
  }
}
