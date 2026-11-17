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
  }

  /// Demo's Thursday keeps every mark at both lanes of the 300-pt rail (S4-3b-2).
  @MainActor @Test func demosThursdayHasNoBlock() async throws {
    let overview = try await demoOverview()
    let rail = TodayScreen(overview).rail(now: overview.now, input: .demo)
    for lane in DenseRailTests.lanes {
      #expect(
        rail.layout(minimumWidth: DayRailView.minimumWidth(lane: lane))
          == rail.marks.map { .mark($0) })
    }
    #expect(DayRailView.minimumWidth(lane: 0) == 0)
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

/// The Day rail on a dense day (S4-3b-2, owner 2026-11-17), invented tasks on Demo's Thursday:
/// a run that does not fit is one block, with its rows and its reading; two at once still fit
/// in the 300-pt rail with a visible scroller (lane ≈ 213) and without it (≈ 228).
struct DenseRailTests {
  static let calendar = DemoCalendar.calendar
  static let lanes: [CGFloat] = [228, 213]

  static func at(_ hour: Int, _ minute: Int) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: DemoCalendar.now)!
  }

  static func item(
    _ title: String, _ planned: Date?, estimate: Int?, done: Bool = false, due: Date? = nil
  ) -> TaskItem {
    TaskItem(
      id: .generate(), refs: [], title: title, projectID: nil, parentTaskID: nil, tagIDs: [],
      status: done ? .completed : .available, flagged: false, plannedAt: planned,
      deferUntil: nil, dueAt: due, effectivePlannedAt: planned, effectiveDeferUntil: nil,
      effectiveDueAt: due, estimateMinutes: estimate, completedAt: nil, modifiedAt: nil,
      occurrenceOf: nil, line: .lifeOps)
  }

  static func event(_ start: Date, _ end: Date) -> CalendarEvent {
    CalendarEvent(
      id: UUID().uuidString, calendarID: CalendarID("invented"), calendarKind: .other,
      title: nil, start: start, end: end, isAllDay: false, display: .normal, occupiesTime: true)!
  }

  static func rail(
    _ tasks: [TaskItem], events: [CalendarEvent] = [], deadlines: Set<TaskItemID> = []
  ) -> DayRail {
    DayRail.compute(
      day: DemoCalendar.now, now: DemoCalendar.now, window: .standard,
      events: .read(events, skipped: 0), visibility: CalendarVisibility(), tasks: tasks,
      deadlines: deadlines, defaultTimes: DefaultTimes(timeZone: calendar.timeZone),
      footprint: DayRailView.footprint, calendar: calendar)
  }

  static var dayStart: Date { calendar.startOfDay(for: DemoCalendar.now) }

  /// The only block of `rail` at `lane`.
  static func block(_ rail: DayRail, lane: CGFloat) throws -> DayRail.Block {
    let layout = rail.layout(minimumWidth: DayRailView.minimumWidth(lane: lane))
    #expect(layout.count == 1)
    guard case .block(let block) = try #require(layout.first) else { throw Missing.block }
    return block
  }

  enum Missing: Error { case block }

  static func rows(_ block: DayRail.Block, _ locale: String) -> [ClusterRows.Row] {
    ClusterRows.rows(
      block, emoji: [:], dayStart: dayStart, zone: calendar.timeZone,
      locale: Locale(identifier: locale))
  }

  static func reading(_ block: DayRail.Block, _ locale: String) -> String {
    RailReading.block(
      block, now: DemoCalendar.now, dayStart: dayStart, zone: calendar.timeZone,
      locale: Locale(identifier: locale))
  }

  static let four = [
    item("Invented A", at(17, 25), estimate: nil), item("Invented B", at(17, 30), estimate: nil),
    item("Invented C", at(17, 30), estimate: 15),
    item("Invented D", at(17, 45), estimate: 10, done: true),
  ]

  @Test func aRunThatDoesNotFitIsOneBlockWithItsRowsAndReading() throws {
    let rail = Self.rail(Self.four)
    let dayStart = Self.calendar.startOfDay(for: DemoCalendar.now)
    for lane in Self.lanes {
      let layout = rail.layout(minimumWidth: DayRailView.minimumWidth(lane: lane))
      #expect(layout.count == 1)
      guard case .block(let block) = try #require(layout.first) else {
        Issue.record("no block at \(lane)")
        continue
      }
      #expect(block.leading == 0 && block.width == 1)
      let rows = ClusterRows.rows(
        block, emoji: [Self.four[2].id: "🧺"], dayStart: dayStart, zone: Self.calendar.timeZone,
        locale: Locale(identifier: "en_GB"))
      #expect(rows.map(\.when) == ["17:25", "17:30", "17:30", "17:45"])
      #expect(rows.map(\.title) == ["Invented A", "Invented B", "Invented C", "Invented D"])
      #expect(rows.map(\.item) == Self.four.map(\.id))
      #expect(rows.map(\.emoji) == [nil, nil, "🧺", nil])
      #expect(rows.map(\.isDone) == [false, false, false, true])
      func reading(_ id: String) -> String {
        RailReading.block(
          block, now: DemoCalendar.now, dayStart: dayStart, zone: Self.calendar.timeZone,
          locale: Locale(identifier: id))
      }
      #expect(
        reading("en_GB")
          == "4 items: 17:25, Invented A, task, Not completed; "
          + "17:30, Invented B, task, Not completed; "
          + "17:30, Invented C, task, estimate 15 minutes, Not completed; "
          + "17:45, Invented D, task, estimate 10 minutes, Completed")
      #expect(
        reading("ru")
          == "4 элемента: 17:25, Invented A, задача, Не выполнено; "
          + "17:30, Invented B, задача, Не выполнено; "
          + "17:30, Invented C, задача, оценка 15 минут, Не выполнено; "
          + "17:45, Invented D, задача, оценка 10 минут, Выполнено")
    }
  }

  @Test func aDeadlineInABlockStaysADeadline() throws {
    let tasks = [
      Self.item("Invented A", Self.at(17, 25), estimate: nil),
      Self.item("Invented B", Self.at(17, 30), estimate: nil),
      Self.item("Invented C", nil, estimate: nil, due: Self.at(17, 30)),
      Self.item("Invented D", nil, estimate: nil, due: Self.at(17, 30)),
    ]
    let rail = Self.rail(tasks, deadlines: [tasks[2].id])
    for lane in Self.lanes {
      let block = try Self.block(rail, lane: lane)
      #expect(block.holdsDeadline)
      let rows = Self.rows(block, "en_GB")
      #expect(rows.map(\.when) == ["17:25", "17:30", "Due 17:30", "due 17:30"])
      #expect(rows.map(\.isDeadline) == [false, false, true, false])
      #expect(rows.map(\.item) == tasks.map(\.id))
      #expect(Self.rows(block, "ru").map(\.when) == ["17:25", "17:30", "Срок 17:30", "срок 17:30"])
      #expect(
        Self.reading(block, "en_GB")
          == "4 items: 17:25, Invented A, task, Not completed; "
          + "17:30, Invented B, task, Not completed; "
          + "Due 17:30, Invented C, deadline, Not completed; "
          + "due 17:30, Invented D, task, Not completed")
      #expect(
        Self.reading(block, "ru")
          == "4 элемента: 17:25, Invented A, задача, Не выполнено; "
          + "17:30, Invented B, задача, Не выполнено; "
          + "Срок 17:30, Invented C, крайний срок, Не выполнено; "
          + "срок 17:30, Invented D, задача, Не выполнено")
    }
  }

  @Test func eventsCollapseIntoAnEventBlock() throws {
    // Untitled, 100 minutes after Demo's 16:20.
    let events = (0..<3).map { _ in Self.event(Self.at(18, 0), Self.at(19, 0)) }
    let rail = Self.rail([], events: events)
    for lane in Self.lanes {
      let block = try Self.block(rail, lane: lane)
      #expect(!block.holdsDeadline)
      let rows = Self.rows(block, "en_GB")
      #expect(rows.map(\.when) == ["18:00", "18:00", "18:00"])
      #expect(rows.map(\.title) == ["Busy", "Busy", "Busy"])
      #expect(rows.allSatisfy { $0.item == nil && !$0.isDone && !$0.isDeadline })
      #expect(Self.rows(block, "ru").map(\.title) == ["Занято", "Занято", "Занято"])
      let one = "18:00, Busy, event, in 100 minutes"
      #expect(Self.reading(block, "en_GB") == "3 items: \(one); \(one); \(one)")
      let ru = "18:00, Занято, событие, через 100 минут"
      #expect(Self.reading(block, "ru") == "3 элемента: \(ru); \(ru); \(ru)")
    }
  }

  /// VO-Space on a block opens its popover (owner, 2026-11-17). The test host exposes no
  /// SwiftUI accessibility tree, so this checks the modifier the block applies; the owner's
  /// live check presses VO-Space.
  @MainActor @Test func aBlocksVoiceOverActionOpensItsPopover() {
    var isOpen = false
    let accessibility = BlockAccessibility(
      reading: "4 items", isOpen: Binding(get: { isOpen }, set: { isOpen = $0 }))
    accessibility.show()
    #expect(isOpen)
  }

  @Test func twoAtOnceKeepTheirColumnsWithAndWithoutAScroller() {
    let rail = Self.rail([
      Self.item("Invented E", Self.at(12, 10), estimate: nil),
      Self.item("Invented F", Self.at(12, 20), estimate: 10),
    ])
    for lane in Self.lanes {
      let layout = rail.layout(minimumWidth: DayRailView.minimumWidth(lane: lane))
      #expect(layout == rail.marks.map { .mark($0) })
      #expect(rail.marks.map(\.width) == [0.5, 0.5])
    }
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
