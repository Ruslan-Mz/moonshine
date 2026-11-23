import Foundation
import MoonShineCore
import MoonShineFixtures
import SwiftUI
import Testing

@testable import MoonShineMac

/// Today's Day rail as the app builds it from Demo (`design/screens/today.md` § Calendar).
@Suite(.serialized) struct DayRailTests {
  /// Every row of the table, wherever it sits.
  static func rows(_ screen: TodayScreen) -> [TodayScreen.Row] {
    screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
      + screen.doneToday
  }

  static func row(_ screen: TodayScreen, _ title: String) throws -> TodayScreen.Row {
    try #require(rows(screen).first { $0.title == title })
  }

  static func time(_ date: Date?) -> String? {
    date.map {
      TodayFormat.time(
        $0, timeZone: DemoCalendar.calendar.timeZone, locale: Locale(identifier: "en_GB"))
    }
  }

  @MainActor @Test func theWhenColumnShowsTodaysTimes() async throws {
    let screen = TodayScreen(try await demoOverview())
    let allemande = try Self.row(screen, "Allemande, bars 1–16 at ♩ = 60")
    #expect(Self.time(allemande.plannedTime) == "20:30")
    #expect(allemande.due == nil)
    let recital = try Self.row(screen, "Send recital repertoire list to teacher")
    #expect(recital.dueIsToday && recital.dueHasTime && recital.isUrgent)
    #expect(Self.time(recital.due) == "18:00")
    #expect(recital.plannedTime == nil)
    let deck = try Self.row(screen, "Definitions deck — 15 cards")
    #expect(Self.time(deck.plannedTime) == "12:00")
  }

  @MainActor @Test func theDemoRailIsTheDesignsThursday() async throws {
    let overview = try await demoOverview()
    let screen = TodayScreen(overview)
    let rail = screen.rail(now: overview.now, input: .demo)
    let describe = { RailText.describe($0) }
    #expect(
      rail.marks.map(describe) == [
        "event 09:30", "planned 12:00 Definitions deck — 15 cards", "event 13:00",
        "planned 15:00 Scales & arpeggios — G minor, 3 octaves", "event 17:00",
        "Due 18:00 Send recital repertoire list to teacher", "event 18:30",
        "planned 20:30 Allemande, bars 1–16 at ♩ = 60",
      ])
    #expect(rail.above.map(describe) == ["planned 07:30 Mobility — hips & shoulders"])
    #expect(rail.below.map(describe) == ["Due 23:59 Submit workshop abstract"])
    // `4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00`.
    #expect(
      TodayFormat.dayFact(rail.load) == [
        .events(4), .inCalendar(.hours(4)), .planned(.hoursAndMinutes(1, 15)),
        .free(.hoursAndMinutes(2, 25), until: rail.load.window.end),
      ])
    #expect(Self.time(rail.load.window.end) == "22:00")
    let reading = RailReading(
      now: overview.now, dayStart: DemoCalendar.calendar.startOfDay(for: overview.now),
      zone: screen.timeZone, locale: Locale(identifier: "en_GB"), lines: screen.lineNames,
      selected: nil)
    #expect(
      reading.section(rail, DayTimeline.layout(rail, now: overview.now))
        == "Day, 10 items with a time, 1 before 08:00, 1 after 22:00. "
        + "Shortened: 08:00 to 09:30, 10:00 to 12:00, 15:20 to 17:00. Now 16:20.")
  }

  /// The reading's line: Life ops, a line's name, or no term when the line is not found.
  @MainActor @Test func theRailReadsATasksLine() async throws {
    let overview = try await demoOverview()
    var workspace = overview.workspace
    let lost = TaskItem(
      id: .generate(), refs: [], title: "Invented", projectID: nil, parentTaskID: nil,
      tagIDs: [], status: .available, flagged: true, plannedAt: nil, deferUntil: nil,
      dueAt: nil, effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: nil,
      estimateMinutes: nil, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
      line: .line(.generate()))
    workspace.tasks.append(lost)
    let screen = TodayScreen(Overview(workspace: workspace, now: overview.now))
    let allemande = try Self.row(screen, "Allemande, bars 1–16 at ♩ = 60")
    guard case .named = screen.lineNames[allemande.id] else {
      Issue.record("no line name")
      return
    }
    let lifeOps = try #require(screen.lifeOps.first)
    #expect(screen.lineNames[lifeOps.id] == .lifeOps)
    // On the rail, though no table section holds a line that is not found.
    #expect(screen.railTasks.contains { $0.id == lost.id })
    #expect(screen.lineNames[lost.id] == nil)
  }

  @MainActor @Test func liveHasNoEventsAndKeepsThePlannedTerm() async throws {
    let overview = try await demoOverview()
    let rail = TodayScreen(overview).rail(now: overview.now, input: .live)
    #expect(rail.marks.count == 4)
    #expect(rail.allDay.isEmpty)
    #expect(TodayFormat.dayFact(rail.load) == [.planned(.hoursAndMinutes(1, 15))])
  }

  @MainActor @Test func aRailClickFindsTheRowAndItsDisclosure() async throws {
    let screen = TodayScreen(try await demoOverview())
    let section = try #require(screen.sections.first?.rows.first)
    #expect(screen.row(section.id)?.row == section)
    #expect(screen.row(section.id)?.disclosure == nil)
    let lifeOps = try #require(screen.lifeOps.first)
    #expect(screen.row(lifeOps.id)?.disclosure == .lifeOps)
    for row in screen.fromEarlier { #expect(screen.row(row.id)?.disclosure == .fromEarlier) }
    for row in screen.doneMore { #expect(screen.row(row.id)?.disclosure == .moreDone) }
    #expect(screen.row(TaskItemID.generate()) == nil)
  }

  @MainActor @Test func aDueTimeOnAnEarlierDayIsADateAndNoMark() async throws {
    let overview = try await demoOverview()
    var workspace = overview.workspace
    let due = DemoCalendar.calendar.date(byAdding: .hour, value: -23, to: overview.now)!
    let late = TaskItem(
      id: .generate(), refs: [], title: "Invented", projectID: nil, parentTaskID: nil,
      tagIDs: [], status: .available, flagged: false, plannedAt: nil, deferUntil: nil,
      dueAt: due, effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: due,
      estimateMinutes: nil, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
      line: .lifeOps)
    workspace.tasks.append(late)
    let changed = Overview(workspace: workspace, now: overview.now)
    let screen = TodayScreen(changed)
    let row = try Self.row(screen, "Invented")
    #expect(row.isUrgent && row.dueHasTime && !row.dueIsToday)
    let rail = screen.rail(now: changed.now, input: .demo)
    #expect(
      !(rail.above + rail.marks + rail.below).contains {
        RailText.describe($0).hasSuffix("Invented")
      })
  }

  @Test func dayFactTerms() {
    let end = Date(timeIntervalSince1970: 0)
    func fact(_ events: Int?, _ inCalendar: Int?, _ planned: Int, _ free: Int?) -> [DayFact] {
      TodayFormat.dayFact(
        events: events, inCalendar: inCalendar, planned: planned, free: free, until: end)
    }
    #expect(fact(nil, nil, 0, nil) == [])
    #expect(fact(0, 0, 0, 840) == [.noEvents, .free(.hours(14), until: end)])
    // Only tentative or free events: `in calendar` at 0 min is left out (owner, 2026-11-16).
    #expect(fact(2, 0, 45, nil) == [.events(2), .planned(.minutes(45))])
    #expect(
      fact(1, 30, 0, 0) == [.events(1), .inCalendar(.minutes(30)), .free(.minutes(0), until: end)])
  }

  static func row(
    due: Date? = nil, hasTime: Bool = false, today: Bool = false, planned: Date? = nil
  )
    -> TodayScreen.Row
  {
    TodayScreen.Row(
      id: .generate(), title: "Invented", trace: [], estimateMinutes: nil, due: due,
      dueHasTime: hasTime, dueIsToday: today, isUrgent: due != nil, plannedDaysAgo: nil,
      plannedTime: planned, isDone: false)
  }

  /// The When column's four cases (`today.md` § Calendar).
  @Test func theWhenColumnChoosesTheTimeOnlyForToday() {
    let calendar = DemoCalendar.calendar
    let at = { (day: Int, hour: Int, minute: Int) in
      calendar.date(
        from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func when(_ row: TodayScreen.Row) -> TodayFormat.When? {
      TodayFormat.when(row, timeZone: calendar.timeZone, locale: Locale(identifier: "en_GB"))
    }
    #expect(when(Self.row(due: at(1, 18, 0), hasTime: true, today: true)) == .due("18:00"))
    #expect(when(Self.row(due: at(1, 17, 0), today: true)) == .due("1 Oct"))
    #expect(when(Self.row(due: at(2, 17, 30), hasTime: true)) == .due("2 Oct"))
    #expect(when(Self.row(planned: at(1, 20, 30))) == .planned("20:30"))
    #expect(
      when(Self.row(due: at(1, 18, 0), hasTime: true, today: true, planned: at(1, 9, 30)))
        == .due("18:00"))
    #expect(when(Self.row()) == nil)
  }

  /// An event that began on an earlier day shows that day's short weekday (owner, 2026-11-16).
  @Test func anEarlierDaysStartNamesItsWeekday() {
    let calendar = DemoCalendar.calendar
    let zone = calendar.timeZone
    let day = calendar.startOfDay(for: DemoCalendar.now)
    let wednesday = calendar.date(byAdding: .hour, value: -1, to: day)!
    let morning = calendar.date(byAdding: .hour, value: 8, to: day)!
    func mark(_ date: Date, _ id: String) -> String {
      TodayFormat.markTime(date, dayStart: day, timeZone: zone, locale: Locale(identifier: id))
    }
    #expect(mark(wednesday, "en_GB") == "Wed 23:00")
    #expect(mark(wednesday, "ru") == "Ср 23:00")
    #expect(mark(morning, "en_US") == "08:00")
  }

  @Test func aCalendarColourIsSixHexDigits() {
    #expect(Tokens.isCalendarHex("#6C84AE"))
    for bad in ["#-00001", "#+FFFFF", "6C84AE0", "#6C84A", "#6C84AG", "", "#６C84AE"] {
      #expect(!Tokens.isCalendarHex(bad))
    }
  }

  @Test func timesAreOnTheTwentyFourHourClockInEveryLanguage() {
    let zone = DemoCalendar.calendar.timeZone
    let evening = DemoCalendar.calendar.date(
      bySettingHour: 20, minute: 30, second: 0, of: DemoCalendar.now)!
    let morning = DemoCalendar.calendar.date(
      bySettingHour: 8, minute: 0, second: 0, of: DemoCalendar.now)!
    for id in ["en_US", "en_GB", "ru"] {
      let locale = Locale(identifier: id)
      #expect(TodayFormat.time(evening, timeZone: zone, locale: locale) == "20:30")
      #expect(TodayFormat.time(morning, timeZone: zone, locale: locale) == "08:00")
      #expect(TodayFormat.hour(morning, timeZone: zone, locale: locale) == "08")
    }
  }
}

/// The Day rail's readings on the compressed timeline (S4-3b-3, `day-rail-dense.md` §
/// VoiceOver), on the design's invented dense Monday laid on Demo's Thursday.
struct RailReadingTests {
  static let calendar = DemoCalendar.calendar

  static func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: DemoCalendar.now)!
  }

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

  static let monday: [TaskItem] = [
    item("Warm-up routine", at(6, 45), estimate: 15),
    item("Review flash cards", at(8, 10)), item("Check the mailbox", at(8, 30)),
    item("Read a paper", at(10, 5), estimate: 30),
    item("Submit the form", nil, due: at(10, 20)), item("Call a supplier", at(10, 20)),
    item("Run the test suite", at(11, 40)),
    item("Order office supplies", at(11, 50), estimate: 5),
    item("Draft the summary", at(14, 15), estimate: 60),
    item("Reply to two emails", at(14, 30)),
    item("Write the report", at(17, 30), estimate: 60),
    item("Review the notes", at(17, 45), estimate: 30),
    item("Send an invoice", at(18)), item("Plan tomorrow", at(19, 10)),
    item("Evening practice", at(19, 50), estimate: 100),
  ]

  static let rail = DayRail.compute(
    day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
    events: .unavailable(.notDetermined), visibility: CalendarVisibility(), tasks: monday,
    deadlines: [monday[4].id], defaultTimes: DefaultTimes(timeZone: calendar.timeZone),
    calendar: calendar)

  static func reading(_ locale: String, selected: TaskItemID? = nil) -> RailReading {
    RailReading(
      now: at(14, 40), dayStart: calendar.startOfDay(for: DemoCalendar.now),
      zone: calendar.timeZone, locale: Locale(identifier: locale),
      lines: Dictionary(uniqueKeysWithValues: monday.map { ($0.id, .lifeOps) }),
      selected: selected)
  }

  static var rows: [DayTimeline.Row] {
    DayTimeline.layout(rail, now: at(14, 40)).items.compactMap {
      if case .row(let row) = $0 { row } else { nil }
    }
  }

  @Test func theSectionNamesItsCountsGapsAndNow() {
    let timeline = DayTimeline.layout(Self.rail, now: Self.at(14, 40))
    #expect(
      Self.reading("en_GB").section(Self.rail, timeline)
        == "Day, 15 items with a time, 1 before 08:00. "
        + "Shortened: 08:30 to 10:05, 10:35 to 11:40, 11:55 to 14:15, 15:15 to 17:30. "
        + "Now 14:40, during Draft the summary.")
    #expect(
      Self.reading("ru").section(Self.rail, timeline)
        == "День, 15 элементов со временем, 1 до 08:00. "
        + "Сокращено: с 08:30 до 10:05, с 10:35 до 11:40, с 11:55 до 14:15, с 15:15 до 17:30. "
        + "Сейчас 14:40, идёт Draft the summary.")
  }

  @Test func aSelectedTaskSaysSo() {
    let call = Self.monday[5]
    let mark = Self.rows[4].mark
    #expect(
      Self.reading("en_GB", selected: call.id).row(mark)
        == "10:20, Call a supplier, task, no estimate, not completed, Life ops, selected")
    #expect(
      Self.reading("ru", selected: call.id).row(mark)
        == "10:20, Call a supplier, задача, без оценки, не выполнена, Быт и система, выбрана")
    #expect(
      Self.reading("en_GB").row(mark)
        == "10:20, Call a supplier, task, no estimate, not completed, Life ops")
    let due = Self.rows[3].mark
    #expect(
      Self.reading("en_GB").row(due)
        == "Due 10:20, Submit the form, deadline, not completed, Life ops")
    // With no line found, no line term.
    let unlined = RailReading(
      now: Self.at(14, 40), dayStart: Self.calendar.startOfDay(for: DemoCalendar.now),
      zone: Self.calendar.timeZone, locale: Locale(identifier: "en_GB"), lines: [:],
      selected: nil)
    #expect(unlined.row(mark) == "10:20, Call a supplier, task, no estimate, not completed")
  }

  @Test func aSpanNamesTheRowsInsideIt() {
    let report = Self.rows[9]
    #expect(
      Self.reading("en_GB").row(report.mark, inside: report.inside)
        == "17:30 to 18:30, Write the report, task, estimate 1 hour, not completed, Life ops. "
        + "Contains Review the notes, 17:45 to 18:15 and Send an invoice.")
    #expect(
      Self.reading("ru").row(report.mark, inside: report.inside)
        == "с 17:30 до 18:30, Write the report, задача, оценка 1 час, не выполнена, "
        + "Быт и система. Внутри: Review the notes, с 17:45 до 18:15 и Send an invoice.")
    let evening = Self.rows[13]
    #expect(
      Self.reading("en_GB").row(evening.mark)
        == "19:50 to 21:30, Evening practice, task, estimate 100 minutes, not completed, Life ops")
  }

  /// One task with a planned and a due row today is selected on both (owner, 2026-11-21).
  @Test func bothRowsOfOneTaskAreSelected() {
    let both = Self.item("Both", Self.at(9), estimate: 30, due: Self.at(12))
    let rail = DayRail.compute(
      day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
      events: .unavailable(.notDetermined), visibility: CalendarVisibility(), tasks: [both],
      deadlines: [], defaultTimes: DefaultTimes(timeZone: Self.calendar.timeZone),
      calendar: Self.calendar)
    let reading = RailReading(
      now: Self.at(14, 40), dayStart: Self.calendar.startOfDay(for: DemoCalendar.now),
      zone: Self.calendar.timeZone, locale: Locale(identifier: "en_GB"), lines: [:],
      selected: both.id)
    #expect(rail.marks.count == 2)
    #expect(rail.marks.allSatisfy { reading.row($0).hasSuffix(", selected") })
    // The fill and the ring, on both rows; never on another task's row.
    #expect(rail.marks.allSatisfy { DayRailView.isSelected($0, selected: both.id) })
    #expect(rail.marks.allSatisfy { !DayRailView.isSelected($0, selected: .generate()) })
  }

  /// A pinned row from an earlier day keeps `Wed 23:00` in the row, not the 40-pt gutter.
  @Test func onlyTodaysPinnedTimesSitInTheGutter() {
    let dayStart = Self.calendar.startOfDay(for: DemoCalendar.now)
    let overnight = CalendarEvent(
      id: "invented", calendarID: CalendarID("invented"), calendarKind: .other, title: nil,
      start: dayStart.addingTimeInterval(-3600), end: Self.at(7), isAllDay: false,
      display: .normal, occupiesTime: true)!
    let rail = DayRail.compute(
      day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
      events: .read([overnight], skipped: 0), visibility: CalendarVisibility(),
      tasks: [Self.item("Early", Self.at(7, 30)), Self.item("Late", nil, due: Self.at(23))],
      deadlines: [], defaultTimes: DefaultTimes(timeZone: Self.calendar.timeZone),
      calendar: Self.calendar)
    #expect(
      rail.above.map { DayRailView.showsGutterTime(pinned: $0, dayStart: dayStart) } == [
        false, true,
      ])
    #expect(
      rail.below.map { DayRailView.showsGutterTime(pinned: $0, dayStart: dayStart) } == [false])
  }
}

/// A mark as the tests read it: kind, time and the task's title.
enum RailText {
  static func describe(_ mark: DayRail.Mark) -> String {
    let time = DayRailTests.time(mark.start) ?? ""
    return switch mark.kind {
    case .event: "event \(time)"
    case .planned(let item): "planned \(time) \(item.title)"
    case .due(let item, let isDeadline): "\(isDeadline ? "Due" : "due") \(time) \(item.title)"
    }
  }
}
