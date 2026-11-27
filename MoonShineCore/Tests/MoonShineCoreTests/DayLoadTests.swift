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
    display: EventDisplay = .normal, occupies: Bool = true, title: String? = nil
  ) -> CalendarEvent {
    CalendarEvent(
      id: UUID().uuidString, calendarID: calendar, calendarKind: kind, title: title, start: start,
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

// MARK: - Day rail

extension RigaDay {
  static func rail(
    _ events: [CalendarEvent] = [], tasks: [TaskItem] = [], deadlines: Set<TaskItemID> = [],
    window: DayWindow = .standard, visibility: CalendarVisibility = CalendarVisibility(),
    read: CalendarRead<[CalendarEvent]>? = nil
  ) -> DayRail {
    DayRail.compute(
      day: at(12), now: at(7), window: window, events: read ?? .read(events, skipped: 0),
      visibility: visibility, tasks: tasks, deadlines: deadlines,
      defaultTimes: DefaultTimes(timeZone: zone, planned: TimeOfDay(hour: 9, minute: 0)),
      calendar: calendar)
  }

  /// `event 13:00–14:00`, `planned 13:45–14:15`, `due 18:00`, `Due 18:00` for a deadline.
  static func describe(_ mark: DayRail.Mark, calendar: Calendar = calendar) -> String {
    func time(_ date: Date) -> String {
      let parts = calendar.dateComponents([.hour, .minute], from: date)
      return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    let span = "\(time(mark.start))–\(time(mark.end))"
    return switch mark.kind {
    case .event: "event \(span)"
    case .planned: "planned \(span)"
    case .due(_, let isDeadline): "\(isDeadline ? "Due" : "due") \(time(mark.start))"
    }
  }
}

@Suite struct DemoDayRailTests {
  @Test func thursdayAtSixTwentyMatchesTheDesign() {
    let open = DemoDay.tasks.filter { $0.status != .completed && $0.effectiveDueAt != nil }
    let rail = DayRail.compute(
      day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
      events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
      tasks: DemoDay.tasks, deadlines: Set(open.map(\.id)), defaultTimes: DemoDay.defaultTimes,
      calendar: DemoCalendar.calendar)
    let describe = { RigaDay.describe($0, calendar: DemoCalendar.calendar) }
    #expect(
      rail.marks.map(describe) == [
        "event 09:30–10:00", "planned 12:00–12:10", "event 13:00–14:00", "planned 15:00–15:20",
        "event 17:00–18:00", "Due 18:00", "event 18:30–20:00", "planned 20:30–21:15",
      ])
    #expect(rail.above.map(describe) == ["planned 07:30–07:45"])
    #expect(rail.below.map(describe) == ["Due 23:59"])
    #expect(rail.allDay.isEmpty)
    #expect(
      rail.load
        == DayLoad.compute(
          day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
          events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
          tasks: DemoDay.tasks, defaultTimes: DemoDay.defaultTimes,
          calendar: DemoCalendar.calendar))
  }

  @Test func theWeekendsAllDayEventIsARowNotAMark() {
    let rail = DayRail.compute(
      day: DemoCalendar.at(10, 3, 12, 0), now: DemoCalendar.at(10, 3, 7, 0), window: .standard,
      events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
      tasks: [], deadlines: [], defaultTimes: DemoDay.defaultTimes, calendar: DemoCalendar.calendar)
    #expect(rail.allDay.count == 1)
    #expect(
      rail.marks.map { RigaDay.describe($0, calendar: DemoCalendar.calendar) } == [
        "event 11:00–12:30"
      ])
  }
}

@Suite struct DayRailRuleTests {
  typealias R = RigaDay

  @Test func theWindowsEdges() {
    let rail = R.rail(
      [R.event(R.at(7, 30), R.at(8, 30)), R.event(R.at(6, 40), R.at(7, 55))],
      tasks: [R.task(nil, estimate: 10, due: R.at(22)), R.task(R.at(21, 50), estimate: 45)])
    #expect(rail.marks.map { R.describe($0) } == ["event 07:30–08:30", "planned 21:50–22:35"])
    #expect(rail.above.map { R.describe($0) } == ["event 06:40–07:55"])
    #expect(rail.below.map { R.describe($0) } == ["due 22:00"])
    // Ending exactly at the window's start is above; an instant at the start and an item ending
    // exactly at the end are on the scale.
    let exact = R.rail(
      [R.event(R.at(7), R.at(8)), R.event(R.at(21), R.at(22))],
      tasks: [R.task(nil, estimate: nil, due: R.at(8))])
    #expect(exact.above.map { R.describe($0) } == ["event 07:00–08:00"])
    #expect(exact.marks.map { R.describe($0) } == ["due 08:00", "event 21:00–22:00"])
    #expect(exact.below.isEmpty)
  }

  @Test func anEventFromTheDayBeforeKeepsItsOwnStart() {
    let overnight = R.event(R.at(23, day: 30, month: 9), R.at(7))
    let rail = R.rail([overnight, R.event(R.at(23, day: 30, month: 9), R.at(9))])
    #expect(rail.above.map(\.start) == [R.at(23, day: 30, month: 9)])
    #expect(rail.marks.map(\.start) == [R.at(23, day: 30, month: 9)])
  }

  @Test func aDateOnlyTimeGivesNoMark() {
    let defaults = DefaultTimes(
      timeZone: R.zone, due: TimeOfDay(hour: 17, minute: 0), planned: TimeOfDay(hour: 9, minute: 0))
    func rail(_ defaults: DefaultTimes, _ tasks: [TaskItem]) -> DayRail {
      DayRail.compute(
        day: R.at(12), now: R.at(7), window: .standard, events: .read([], skipped: 0),
        visibility: CalendarVisibility(), tasks: tasks, deadlines: [], defaultTimes: defaults,
        calendar: R.calendar)
    }
    let dated = [R.task(R.at(9), estimate: 30), R.task(nil, estimate: nil, due: R.at(17))]
    #expect(rail(defaults, dated).marks.isEmpty)
    let none = DefaultTimes(timeZone: R.zone)
    #expect(rail(none, dated).marks.map { R.describe($0) } == ["planned 09:00–09:30", "due 17:00"])
    #expect(rail(none, [R.task(R.at(0), estimate: 30)]).marks.isEmpty)
  }

  @Test func hiddenUnreadAndAllDayEvents() {
    let work = R.event(R.at(13), R.at(14))
    let off = CalendarVisibility([R.work: CalendarSetting(show: false, countsAsBusy: true)])
    #expect(R.rail([work], visibility: off).marks.isEmpty)
    let task = R.task(R.at(15), estimate: 20)
    let unread = R.rail(tasks: [task], read: .unavailable(.denied))
    #expect(unread.marks.map { R.describe($0) } == ["planned 15:00–15:20"])
    #expect(unread.allDay.isEmpty)
    let allDay = R.event(R.at(0), R.at(0, day: 2), allDay: true)
    let rail = R.rail([allDay, work])
    #expect(rail.allDay == [allDay])
    #expect(rail.marks.map { R.describe($0) } == ["event 13:00–14:00"])
  }

  // MARK: Identical events (owner, 2026-11-27): one row, whatever their calendar

  static let copy = "Invented sync"
  static let home = CalendarID("home")

  @Test func threeIdenticalCopiesAreOneRowOfThree() {
    let copies = (0..<3).map { _ in R.event(R.at(13), R.at(14), title: Self.copy) }
    let rail = R.rail(copies)
    #expect(rail.marks.map { R.describe($0) } == ["event 13:00–14:00"])
    guard case .event(let shown) = rail.marks.first?.kind else {
      Issue.record("no event row")
      return
    }
    #expect(shown == copies[0])
    #expect(rail.copies(of: shown) == 3)
    // `N events` counts rows.
    #expect(rail.load.eventCount == 1)
    #expect(R.load(copies).eventCount == 1)
  }

  @Test func anotherEndOrTitleIsAnotherRow() {
    let first = R.event(R.at(13), R.at(14), title: Self.copy)
    let longer = R.event(R.at(13), R.at(14, 30), title: Self.copy)
    let renamed = R.event(R.at(13), R.at(14), title: "Invented other")
    for pair in [[first, longer], [first, renamed]] {
      let rail = R.rail(pair)
      #expect(rail.marks.count == 2)
      #expect(rail.copies.isEmpty)
      #expect(rail.load.eventCount == 2)
    }
  }

  /// Another calendar's copy counts; a hidden calendar's is left out before the collapse.
  @Test func copiesAcrossCalendarsAndAHiddenOne() {
    let work = R.event(R.at(13), R.at(14), title: Self.copy)
    let home = R.event(R.at(13), R.at(14), calendar: Self.home, title: Self.copy)
    #expect(R.rail([work, home]).copies(of: work) == 2)
    let hidden = CalendarVisibility([Self.home: CalendarSetting(show: false, countsAsBusy: true)])
    let rail = R.rail([work, home], visibility: hidden)
    #expect(rail.marks.count == 1)
    #expect(rail.copies.isEmpty)
    #expect(rail.copies(of: work) == 1)
  }

  @Test func allDayCopiesAreOneRow() {
    let copies = (0..<2).map { _ in
      R.event(R.at(0), R.at(0, day: 2), allDay: true, title: Self.copy)
    }
    let rail = R.rail(copies)
    #expect(rail.allDay == [copies[0]])
    #expect(rail.copies(of: copies[0]) == 2)
  }

  @Test func theBusyTotalIsOneCopys() {
    let one = R.load([R.event(R.at(13), R.at(14), title: Self.copy)])
    let three = R.load((0..<3).map { _ in R.event(R.at(13), R.at(14), title: Self.copy) })
    #expect(three.inCalendarMinutes == one.inCalendarMinutes)
    #expect(three.freeWholeWindowMinutes == one.freeWholeWindowMinutes)
    #expect(three.inCalendarMinutes == 60)
  }

  @Test func anotherDaysTimesGiveNoMark() {
    let rail = R.rail(tasks: [
      R.task(R.at(23, 30, day: 30, month: 9), estimate: 60),
      R.task(R.at(15, day: 30, month: 9), estimate: 20),
      R.task(nil, estimate: nil, due: R.at(17, 30, day: 30, month: 9)),
      R.task(nil, estimate: nil, due: R.at(9, day: 2)),
    ])
    #expect(rail.marks.isEmpty && rail.above.isEmpty && rail.below.isEmpty)
  }

  @Test func aTaskWithBothTimesHasBothMarksAndOnlyDeadlinesAreAmber() {
    let both = R.task(R.at(14), estimate: 30, due: R.at(16))
    let other = R.task(nil, estimate: nil, due: R.at(18))
    let rail = R.rail(tasks: [both, other], deadlines: [both.id])
    #expect(rail.marks.map { R.describe($0) } == ["planned 14:00–14:30", "Due 16:00", "due 18:00"])
  }
}

/// The compressed timeline (S4-3b-3, `design/screens/day-rail-dense.md`, owner 2026-11-17 and
/// 2026-11-21). Invented days in Europe/Riga with no default times, so 09:00 is a time.
@Suite struct DayTimelineTests {
  typealias R = RigaDay

  static func item(
    _ title: String, _ planned: Date?, estimate: Int? = nil, due: Date? = nil
  ) -> TaskItem {
    TaskItem(
      id: .generate(), refs: [], title: title, projectID: nil, parentTaskID: nil, tagIDs: [],
      status: .available, flagged: false, plannedAt: planned, deferUntil: nil, dueAt: due,
      effectivePlannedAt: planned, effectiveDeferUntil: nil, effectiveDueAt: due,
      estimateMinutes: estimate, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
      line: .lifeOps)
  }

  static func rail(
    _ events: [CalendarEvent] = [], tasks: [TaskItem] = [], deadlines: Set<TaskItemID> = [],
    read: CalendarRead<[CalendarEvent]>? = nil
  ) -> DayRail {
    DayRail.compute(
      day: R.at(12), now: R.at(12), window: .standard, events: read ?? .read(events, skipped: 0),
      visibility: CalendarVisibility(), tasks: tasks, deadlines: deadlines,
      defaultTimes: DefaultTimes(timeZone: R.zone), calendar: R.calendar)
  }

  static func hhmm(_ date: Date, _ calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  static func points(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }

  /// `row 18:30 @290 h45 block end`, `row 10:05 @79 h22 line 149`, `gap 08:00–09:30 @0 h18`,
  /// and last `height 395` and `now gap 221.2`.
  static func describe(_ timeline: DayTimeline, _ calendar: Calendar = R.calendar) -> [String] {
    let time = { hhmm($0, calendar) }
    let items = timeline.items.map { item -> String in
      switch item {
      case .gap(let gap):
        return "gap \(time(gap.from))–\(time(gap.to)) @\(points(gap.top)) h\(points(gap.height))"
      case .row(let row):
        var text = "row \(time(row.mark.start)) @\(points(row.top)) h\(points(row.height))"
        if row.isBlock { text += " block" }
        if row.showsEnd { text += " end" }
        if row.showsRange { text += " range" }
        if !row.showsStart { text += " nostart" }
        if let line = row.line {
          text += " line \(points(line.end))" + (line.endTime.map { " \(time($0))" } ?? "")
        }
        return text
      }
    }
    let now = timeline.now.map { ["now \($0.place) \(points($0.y))"] } ?? []
    var height = "height \(points(timeline.height))"
    if !timeline.showsStartEdge { height += " nostartedge" }
    if !timeline.showsEndEdge { height += " noendedge" }
    return items + [height] + now
  }

  static func title(_ mark: DayRail.Mark?) -> String? {
    switch mark?.kind {
    case .planned(let item), .due(let item, _): item.title
    case .event: "event"
    case nil: nil
    }
  }

  @Test func demosThursdayAtSixTwentyIsTheDesigns() {
    let open = DemoDay.tasks.filter { $0.status != .completed && $0.effectiveDueAt != nil }
    let rail = DayRail.compute(
      day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
      events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
      tasks: DemoDay.tasks, deadlines: Set(open.map(\.id)), defaultTimes: DemoDay.defaultTimes,
      calendar: DemoCalendar.calendar)
    let timeline = DayTimeline.layout(rail, now: DemoCalendar.now)
    #expect(
      Self.describe(timeline, DemoCalendar.calendar) == [
        "gap 08:00–09:30 @0 h18", "row 09:30 @22 h22 block", "gap 10:00–12:00 @50 h18",
        "row 12:00 @72 h22 block", "row 13:00 @102 h30 block", "row 15:00 @162 h22 block",
        "gap 15:20–17:00 @190 h40", "row 17:00 @234 h30 block", "row 18:00 @266 h22 nostart",
        "row 18:30 @290 h45 block end", "row 20:30 @350 h22.5 block", "height 395",
        "now gap 221.2",
      ])
    #expect(timeline.now?.during == nil)
  }

  /// The design's invented dense Monday at 14:40, no calendar access: 14 items with a time in
  /// the window and one before it (`day-rail-dense.md` § Notes on the data).
  static let monday: [TaskItem] = [
    item("Warm-up routine", R.at(6, 45), estimate: 15),
    item("Review flash cards", R.at(8, 10)), item("Check the mailbox", R.at(8, 30)),
    item("Read a paper", R.at(10, 5), estimate: 30),
    item("Submit the form", nil, due: R.at(10, 20)), item("Call a supplier", R.at(10, 20)),
    item("Run the test suite", R.at(11, 40)),
    item("Order office supplies", R.at(11, 50), estimate: 5),
    item("Draft the summary", R.at(14, 15), estimate: 60),
    item("Reply to two emails", R.at(14, 30)),
    item("Write the report", R.at(17, 30), estimate: 60),
    item("Review the notes", R.at(17, 45), estimate: 30),
    item("Send an invoice", R.at(18)), item("Plan tomorrow", R.at(19, 10)),
    item("Evening practice", R.at(19, 50), estimate: 100),
  ]

  static var mondayRail: DayRail {
    rail(tasks: monday, deadlines: [monday[4].id], read: .unavailable(.notDetermined))
  }

  @Test func theDenseMondayAtFourtyPastTwoIsTheDesigns() {
    let rail = Self.mondayRail
    #expect(rail.above.count == 1 && rail.marks.count == 14 && rail.below.isEmpty)
    // 30 + 5 + 60 + 60 + 100: `Review the notes` lies inside `Write the report`.
    #expect(rail.load.plannedMinutes == 255)
    let timeline = DayTimeline.layout(rail, now: R.at(14, 40))
    #expect(
      Self.describe(timeline) == [
        "row 08:10 @5 h22", "row 08:30 @29 h22", "gap 08:30–10:05 @57 h18",
        "row 10:05 @79 h22 line 149", "row 10:20 @103 h22 nostart", "row 10:20 @127 h22",
        "gap 10:35–11:40 @155 h18", "row 11:40 @177 h22", "row 11:50 @201 h22 block",
        "gap 11:55–14:15 @229 h18", "row 14:15 @251 h22 line 297.5",
        // The now label covers 14:30 in the gutter: it gives way (owner, 2026-11-21).
        "row 14:30 @275 h22 nostart", "gap 15:15–17:30 @303 h18",
        "row 17:30 @325 h22 line 395 18:30", "row 17:45 @349 h22 range", "row 18:00 @373 h22",
        "row 19:10 @408 h22", "row 19:50 @432 h50 block end", "height 497", "now line 280",
      ])
    #expect(Self.title(timeline.now?.during) == "Draft the summary")
    let rows = timeline.items.compactMap { if case .row(let row) = $0 { row } else { nil } }
    #expect(rows[2].inside.map { Self.title($0) } == ["Submit the form", "Call a supplier"])
    #expect(rows[9].inside.map { Self.title($0) } == ["Review the notes", "Send an invoice"])
    // A nested span: now on the outer span's line, the only one drawn.
    let evening = DayTimeline.layout(rail, now: R.at(17, 50))
    #expect(evening.now?.place == .line)
    #expect(evening.now?.y == 357)
    #expect(Self.title(evening.now?.during) == "Write the report")
    // At 18:15 the label covers the line's 18:30 end time, which gives way.
    let late = DayTimeline.layout(rail, now: R.at(18, 15))
    #expect(late.now?.y == 384)
    #expect(Self.describe(late).contains("row 17:30 @325 h22 line 395"))
  }

  @Test func anHourStaysToScaleAndLongerIsAGap() {
    let hour = DayTimeline.layout(
      Self.rail(tasks: [Self.item("a", R.at(10)), Self.item("b", R.at(11))]), now: R.at(7))
    #expect(
      Self.describe(hour) == [
        "gap 08:00–10:00 @0 h18", "row 10:00 @22 h22", "row 11:00 @52 h22",
        "gap 11:00–22:00 @80 h18", "height 102",
      ])
    let longer = DayTimeline.layout(
      Self.rail(tasks: [Self.item("a", R.at(10)), Self.item("b", R.at(11, 1))]), now: R.at(7))
    #expect(
      Self.describe(longer) == [
        "gap 08:00–10:00 @0 h18", "row 10:00 @22 h22", "gap 10:00–11:01 @50 h18",
        "row 11:01 @72 h22", "gap 11:01–22:00 @100 h18", "height 122",
      ])
  }

  /// The design's "Now" column (owner, 2026-11-20).
  @Test func nowBetweenRowsBeforeTheFirstAndInABlock() {
    let three = Self.rail(
      tasks: [(9, 0), (9, 20), (9, 40)].map { Self.item("t", R.at($0.0, $0.1)) })
    #expect(
      Self.describe(DayTimeline.layout(three, now: R.at(9, 30))) == [
        "row 09:00 @30 h22", "row 09:20 @54 h22", "row 09:40 @104 h22",
        "gap 09:40–22:00 @132 h18", "height 154", "now slot 90",
      ])
    let first = Self.rail(tasks: [Self.item("t", R.at(8, 10))])
    #expect(
      Self.describe(DayTimeline.layout(first, now: R.at(8, 5))) == [
        // The label covers the 08:00 edge time, which gives way.
        "row 08:10 @26 h22", "gap 08:10–22:00 @54 h18", "height 76 nostartedge", "now slot 12",
      ])
    let block = Self.rail(tasks: [
      Self.item("Task A", R.at(9), estimate: 150), Self.item("Task B", R.at(11, 30)),
    ])
    let inBlock = DayTimeline.layout(block, now: R.at(9, 40))
    // The block's end time gives way to the now label (`day-rail-dense.md` § Layout).
    #expect(
      Self.describe(inBlock) == [
        "row 09:00 @30 h75 block nostart", "row 11:30 @107 h22", "gap 11:30–22:00 @135 h18",
        "height 157", "now block 50",
      ])
    #expect(Self.title(inBlock.now?.during) == "Task A")
    #expect(DayTimeline.layout(block, now: R.at(7)).now == nil)
    #expect(DayTimeline.layout(block, now: R.at(22)).now == nil)
  }

  /// Spans that overlap without nesting (owner, 2026-11-21): the outer line runs to the latest
  /// end of every span that starts inside it, and `during` names the span still running.
  @Test func anOverlappingSpanExtendsTheOuterLine() {
    let task = Self.item("Long task", R.at(14, 30), estimate: 90)
    let after = Self.item("After", R.at(15, 15))
    let rail = Self.rail([R.event(R.at(14), R.at(15))], tasks: [task, after])
    let timeline = DayTimeline.layout(rail, now: R.at(15, 30))
    #expect(
      Self.describe(timeline) == [
        "gap 08:00–14:00 @0 h18", "row 14:00 @22 h22 line 92.5", "row 14:30 @46 h22 range",
        "row 15:15 @70 h22 nostart", "gap 16:00–22:00 @98 h18", "height 120", "now line 77.5",
      ])
    #expect(Self.title(timeline.now?.during) == "Long task")
    // The same start: the event comes first and is the outer span; the line runs to 12:00.
    let same = Self.rail(
      [R.event(R.at(10), R.at(10, 30))], tasks: [Self.item("Two hours", R.at(10), estimate: 120)])
    #expect(
      Self.describe(DayTimeline.layout(same, now: R.at(7))) == [
        "gap 08:00–10:00 @0 h18", "row 10:00 @22 h22 line 106", "row 10:00 @46 h22 range",
        "gap 12:00–22:00 @110 h18", "height 132",
      ])
  }

  /// Review round 1: now after a span with rows inside sits below the span's line.
  @Test func nowAfterAnEndedSpanIsBelowItsLine() {
    let rail = Self.rail(tasks: [
      Self.item("Long", R.at(9), estimate: 180), Self.item("Inside", R.at(9, 5)),
      Self.item("After", R.at(12, 30)),
    ])
    #expect(
      Self.describe(DayTimeline.layout(rail, now: R.at(12, 10))) == [
        "row 09:00 @30 h22 line 141.5 12:00", "row 09:05 @54 h22", "row 12:30 @175.5 h22",
        "gap 12:30–22:00 @203.5 h18", "height 225.5", "now slot 161.5",
      ])
  }

  /// Review round 1: now in a block that crosses the window's edge, over the part drawn.
  @Test func nowInABlockAcrossTheWindowsEdges() {
    let early = Self.rail([R.event(R.at(7, 30), R.at(9))])
    #expect(abs((DayTimeline.layout(early, now: R.at(8, 30)).now?.y ?? 0) - 15) < 1e-9)
    let late = Self.rail([R.event(R.at(20, 30), R.at(23, 30))])
    #expect(abs((DayTimeline.layout(late, now: R.at(21)).now?.y ?? 0) - 37) < 1e-9)
    // The label near the end line covers its 22:00.
    let two = Self.rail(tasks: [Self.item("a", R.at(21)), Self.item("b", R.at(21, 40))])
    #expect(
      Self.describe(DayTimeline.layout(two, now: R.at(21, 50))).suffix(2) == [
        "height 94 noendedge", "now slot 82",
      ])
  }

  @Test func theWindowsEdges() {
    // From before the window: at the start line, its range in the row, no gutter time.
    let early = Self.rail([R.event(R.at(7, 30), R.at(9))])
    #expect(
      Self.describe(DayTimeline.layout(early, now: R.at(7))) == [
        "row 07:30 @0 h30 block range nostart", "gap 09:00–22:00 @36 h18", "height 58",
      ])
    // Past the window's end: the block and the line stop at the end line, with no end time.
    let late = Self.rail([R.event(R.at(20, 30), R.at(23, 30))])
    #expect(
      Self.describe(DayTimeline.layout(late, now: R.at(7))) == [
        "gap 08:00–20:30 @0 h18", "row 20:30 @22 h45 block", "height 67",
      ])
    let holding = Self.rail(
      [R.event(R.at(21), R.at(23, 30))], tasks: [Self.item("Due", nil, due: R.at(21, 30))])
    #expect(
      Self.describe(DayTimeline.layout(holding, now: R.at(7))) == [
        "gap 08:00–21:00 @0 h18", "row 21:00 @22 h22 line 68", "row 21:30 @46 h22 nostart",
        "height 68",
      ])
  }

  @Test func anEmptyDayAndOneWithOnlyPinnedRows() {
    #expect(
      Self.describe(DayTimeline.layout(Self.rail(), now: R.at(7)))
        == ["gap 08:00–22:00 @0 h18", "height 22"])
    #expect(
      Self.describe(DayTimeline.layout(Self.rail(), now: R.at(12)))
        == ["gap 08:00–22:00 @0 h40", "height 44", "now gap 24.3"])
    let pinned = Self.rail(tasks: [
      Self.item("Early", R.at(7)), Self.item("Late", nil, due: R.at(23)),
    ])
    #expect(pinned.above.count == 1 && pinned.below.count == 1 && pinned.marks.isEmpty)
    #expect(
      Self.describe(DayTimeline.layout(pinned, now: R.at(7)))
        == ["gap 08:00–22:00 @0 h18", "height 22"])
  }
}
