import Foundation
import MoonShineCore
import MoonShineFixtures
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
