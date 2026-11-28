import Foundation
import MoonShineCore
import SwiftUI
import Testing

@testable import MoonShineMac

private let riga = TimeZone(identifier: "Europe/Riga")!
private let en = Locale(identifier: "en_GB")
private let ru = Locale(identifier: "ru_RU")

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
  TodayFormat.calendar(riga).date(
    from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite(.serialized) struct WeekScreenTests {
  // MARK: Demo (`design/demo-data.md`; today is Thu 1 Oct 2026, W40)

  @MainActor @Test func demoWeekFortyWithThursdayAsToday() async throws {
    let screen = WeekScreen(try await demoOverview())
    #expect(screen.week == 40)
    #expect(screen.days.count == 7)
    #expect(screen.days.map(\.isToday) == [false, false, false, true, false, false, false])
    #expect(screen.days.map(\.isPast) == [true, true, true, false, false, false, false])
  }

  @MainActor @Test func pastDaysCountDoneFutureDaysEstimateTodayBoth() async throws {
    let overview = try await demoOverview()
    let screen = WeekScreen(overview)
    let core = overview.week().days
    for index in 0..<3 {
      #expect(core[index].doneCount > 0)
      #expect(screen.days[index].summary == [.done(core[index].doneCount)])
    }
    // Thursday's done count is Today's (owner, 2026-11-27): both count every task done today.
    let done = overview.today().totals.done
    #expect(done == 6)
    #expect(core[3].estimateMinutes > 0)
    #expect(screen.days[3].summary == [.done(done), .estimate(core[3].estimateMinutes)])
    for index in 4..<7 {
      let minutes = core[index].estimateMinutes
      #expect(screen.days[index].summary == (minutes > 0 ? [.estimate(minutes)] : []))
    }
    #expect(core[4..<7].contains { $0.estimateMinutes > 0 })
  }

  // MARK: A constructed week (Wed 30 Sep 2026, W40, in Riga)

  private static func week(_ tasks: [TaskItem]) -> WeekScreen {
    WeekScreen(
      Overview(workspace: Workspace(timeZone: riga, tasks: tasks), now: date(2026, 9, 30, 12)))
  }

  private static func item(
    _ title: String, planned: Date? = nil, due: Date? = nil, estimate: Int? = nil,
    completed: Date? = nil
  ) -> TaskItem {
    TaskItem(
      id: .generate(), refs: [], title: title, projectID: nil, parentTaskID: nil, tagIDs: [],
      status: completed == nil ? .available : .completed, flagged: false, plannedAt: planned,
      deferUntil: nil, dueAt: due, effectivePlannedAt: planned, effectiveDeferUntil: nil,
      effectiveDueAt: due, estimateMinutes: estimate, completedAt: completed, modifiedAt: nil,
      occurrenceOf: nil, line: .lifeOps)
  }

  @Test func aZeroTermIsLeftOut() {
    let screen = Self.week([
      Self.item("Today, estimated", planned: date(2026, 9, 30, 18), estimate: 30),
      Self.item("Friday, no estimate", planned: date(2026, 10, 2, 9)),
    ])
    // Tuesday, past, nothing done; today, nothing done yet; Friday, no estimate.
    #expect(screen.days[1].summary.isEmpty)
    #expect(screen.days[2].summary == [.estimate(30)])
    #expect(screen.days[4].summary.isEmpty)
    #expect(screen.days[4].cards.count == 1)
  }

  @Test func dueTextIsForOpenCardsDueInsideTheWeek() {
    let tuesday = date(2026, 9, 29, 9)
    let screen = Self.week([
      Self.item("Due next Monday 00:00", planned: tuesday, due: date(2026, 10, 5)),
      Self.item("Due Sunday 23:59", planned: tuesday, due: date(2026, 10, 4, 23, 59)),
      Self.item("Done, due Friday", due: date(2026, 10, 2, 12), completed: tuesday),
    ])
    let cards = Dictionary(uniqueKeysWithValues: screen.days[1].cards.map { ($0.title, $0) })
    #expect(cards["Due next Monday 00:00"]?.due == nil)
    #expect(cards["Due Sunday 23:59"]?.due?.date == date(2026, 10, 4, 23, 59))
    #expect(cards["Done, due Friday"]?.isCompleted == true)
    #expect(cards["Done, due Friday"]?.due == nil)
  }

  @MainActor @Test func theFridayTaskIsADeadlineOnlyUnderAllDueDates() async throws {
    let overview = try await demoOverview()
    func friday(_ rule: DeadlineRule) -> WeekScreen.Card? {
      let screen = WeekScreen(
        Overview(workspace: overview.workspace, now: overview.now, deadlineRule: rule))
      return screen.days[4].cards.first { $0.title == "Book rehearsal room for November" }
    }
    let tagged = DeadlineRule(mode: .dueDateAndTag, tag: DeadlineRule.defaultTag)
    #expect(friday(tagged)?.due?.isDeadline == false)
    #expect(friday(tagged)?.due?.hasTime == true)
    #expect(friday(.allDueDates)?.due?.isDeadline == true)
  }

  /// The strip's filter is the screen's (owner, 2026-11-27): Core's header keeps every line and
  /// Life ops. The cells carry no text of their own; the Life ops label is checked in both
  /// languages so a cell never stands for it.
  @MainActor @Test(arguments: [en, ru])
  func theStripLeavesOutPausedLinesAndLifeOpsInBudgetOrder(locale: Locale) async throws {
    let overview = try await demoOverview()
    let screen = WeekScreen(overview)
    let header = overview.week().header
    #expect(header.count == 12)
    #expect(header.last?.line == .lifeOps)
    let shown = overview.workspace.lines.filter { $0.state != .paused }
    #expect(screen.cells.map(\.id) == shown.map(\.id))
    #expect(!screen.cells.contains { $0.name == "Calligraphy" })
    let lifeOps = TodayFormat.localized("Life ops", locale)
    #expect(!lifeOps.isEmpty)
    #expect(!screen.cells.contains { $0.name == lifeOps })
  }

  @MainActor @Test func theStripSaysWhichSeriesApply() async throws {
    let screen = WeekScreen(try await demoOverview())
    let cells = Dictionary(uniqueKeysWithValues: screen.cells.map { ($0.name, $0) })
    #expect(screen.cells.count == 10)
    #expect(cells["AI/ML"]?.hasRhythm == false)
    #expect(cells["AI/ML"]?.hasProgress == true)
    #expect(cells["Violin"]?.hasRhythm == true)
    #expect(cells["Japanese"]?.hasNoCompletions == true)
    #expect(screen.completedSince != nil)
  }

  @MainActor @Test func theTrayHoldsOnlyActiveLinesUndatedTasks() async throws {
    let overview = try await demoOverview()
    let screen = WeekScreen(overview)
    let active = Set(overview.workspace.lines.filter { $0.state == .active }.map(\.name))
    #expect(!screen.noPlan.isEmpty)
    #expect(screen.noPlan.allSatisfy { $0.lineName.map(active.contains) == true })
    #expect(screen.noPlan.allSatisfy { $0.due == nil })
  }

  // MARK: S5-1b, another week (owner, 2026-11-28)

  @MainActor @Test func lastAndNextWeekOnDemo() async throws {
    let overview = try await demoOverview()
    let navigation = WeekNavigation(overview)
    #expect(navigation.current == ISOWeek(year: 2026, week: 40))
    #expect(WeekScreen(overview).isCurrent)
    let last = WeekScreen(
      overview, week: navigation.current.adding(-1, calendar: overview.calendar))
    #expect(last.week == 39)
    #expect(!last.isCurrent)
    #expect(last.days.allSatisfy { $0.isPast && !$0.isToday })
    #expect(last.firstDay == date(2026, 9, 21))
    let next = WeekScreen(overview, week: navigation.current.adding(1, calendar: overview.calendar))
    #expect(next.week == 41)
    #expect(!next.isCurrent)
    #expect(next.days.allSatisfy { !$0.isPast && !$0.isToday })
    #expect(
      next.days.allSatisfy { $0.summary.allSatisfy { if case .done = $0 { false } else { true } } })
  }

  /// ‹ stops at the week where the store's data is known from: the earlier of the window start
  /// and the earliest kept completion (owner, 2026-11-28, PR #77 round 1); 6 July in Demo.
  @MainActor @Test func backStopsAtTheWeekTheDataIsKnownFrom() async throws {
    let overview = try await demoOverview()
    let navigation = WeekNavigation(overview)
    let july6 = ISOWeek(year: 2026, week: 28)
    let known = try #require(overview.knownSince)
    #expect(ISOWeek(containing: known, calendar: overview.calendar) == july6)
    #expect(navigation.earliest == july6)
    #expect(navigation.clamped(july6) == july6)
    #expect(navigation.clamped(ISOWeek(year: 2026, week: 27)) == july6)
    #expect(WeekScreen(overview, week: ISOWeek(year: 2026, week: 27)).week == 28)
    #expect(navigation.canStep(ISOWeek(year: 2026, week: 29), by: -1))
    #expect(!navigation.canStep(july6, by: -1))
    #expect(navigation.step(july6, by: -1) == july6)
    #expect(navigation.canStep(july6, by: 1))
  }

  @Test func withNoWindowStartBothWaysReachTenYears() {
    let navigation = WeekNavigation(
      Overview(workspace: Workspace(timeZone: riga), now: date(2026, 9, 30, 12)))
    let calendar = navigation.calendar
    #expect(
      navigation.earliest == navigation.current.adding(-WeekNavigation.reach, calendar: calendar))
    #expect(
      navigation.latest == navigation.current.adding(WeekNavigation.reach, calendar: calendar))
    #expect(navigation.canStep(nil, by: -1))
    #expect(!navigation.canStep(navigation.latest, by: 1))
    #expect(navigation.step(navigation.latest, by: 1) == navigation.latest)
    #expect(navigation.clamped(ISOWeek(year: 2100, week: 1)) == navigation.latest)
  }

  /// A completion kept from an earlier import, before the window, moves the stop back to it
  /// (ADR-0002); with none, the stop is the window's week.
  @Test func aKeptCompletionBeforeTheWindowMovesTheStopBack() {
    let window = date(2026, 7, 6)  // W28's Monday
    let kept = Self.item("Kept from an old import", completed: date(2026, 5, 13, 9))  // W20
    let now = date(2026, 9, 30, 12)
    let with = WeekNavigation(
      Overview(
        workspace: Workspace(timeZone: riga, tasks: [kept], completedSince: window), now: now))
    #expect(with.earliest == ISOWeek(year: 2026, week: 20))
    let without = WeekNavigation(
      Overview(workspace: Workspace(timeZone: riga, completedSince: window), now: now))
    #expect(without.earliest == ISOWeek(year: 2026, week: 28))
  }

  /// PR #77 round 1, Low: a window start after today (a clock set back) keeps this week shown.
  @Test func aWindowStartAfterTodayKeepsThisWeek() {
    let navigation = WeekNavigation(
      Overview(
        workspace: Workspace(timeZone: riga, completedSince: date(2026, 10, 14)),
        now: date(2026, 9, 30, 12)))
    #expect(navigation.earliest == navigation.current)
    #expect(navigation.clamped(nil) == navigation.current)
    #expect(!navigation.canStep(nil, by: -1))
  }

  /// PR #77 round 1, Medium: the shown week is held as the week itself, this week included, so
  /// the rebuild at midnight from Sunday to Monday does not move it.
  @Test func theShownWeekStaysPutAcrossMidnight() {
    var shown: ISOWeek?
    let binding = Binding(get: { shown }, set: { shown = $0 })
    let sunday = WeekNavigation(
      Overview(workspace: Workspace(timeZone: riga), now: date(2026, 10, 4, 23, 55)))
    let before = WeekStepper(navigation: sunday, shown: binding)
    before.hold()
    #expect(shown == ISOWeek(year: 2026, week: 40))
    let monday = WeekNavigation(
      Overview(workspace: Workspace(timeZone: riga), now: date(2026, 10, 5, 0, 5)))
    let after = WeekStepper(navigation: monday, shown: binding)
    after.hold()
    #expect(shown == ISOWeek(year: 2026, week: 40))
    #expect(!after.isCurrent)
    after.goToThisWeek()
    #expect(shown == ISOWeek(year: 2026, week: 41))
    #expect(after.isCurrent)
  }

  /// PR #77 round 1, Low: the toolbar's and the View menu's stepper.
  @Test func theStepperStepsWithinTheBoundsAndGoesBackToThisWeek() {
    var shown: ISOWeek?
    let navigation = WeekNavigation(
      Overview(workspace: Workspace(timeZone: riga), now: date(2026, 9, 30, 12)))
    let stepper = WeekStepper(
      navigation: navigation, shown: Binding(get: { shown }, set: { shown = $0 }))
    #expect(stepper.isCurrent)
    stepper.step(by: 1)
    #expect(shown == ISOWeek(year: 2026, week: 41))
    #expect(!stepper.isCurrent)
    stepper.step(by: -1)
    #expect(shown == navigation.current)
    #expect(stepper.isCurrent)
    stepper.step(by: -1)
    #expect(shown == ISOWeek(year: 2026, week: 39))
    stepper.goToThisWeek()
    #expect(shown == navigation.current)
    shown = navigation.latest
    #expect(!stepper.canStep(by: 1))
    #expect(stepper.canStep(by: -1))
    shown = navigation.earliest
    #expect(!stepper.canStep(by: -1))
  }

  /// Averages over known weeks only, with none hidden (owner, 2026-11-28, PR #77 round 1): on
  /// Demo, known from W28's Monday.
  @MainActor @Test func averagesCountOnlyTheKnownWeeks() async throws {
    let overview = try await demoOverview()
    let stats = overview.stats
    func week(_ number: Int) -> WeekScreen {
      WeekScreen(overview, week: ISOWeek(year: 2026, week: number))
    }
    func mean(_ id: LineID, _ weeks: ClosedRange<Int>) -> WeekAverage {
      let counts = weeks.map { stats.counts(.line(id), in: ISOWeek(year: 2026, week: $0)) }
      let total = Double(counts.count)
      return WeekAverage(
        rhythm: Double(counts.map(\.rhythm).reduce(0, +)) / total,
        progress: Double(counts.map(\.progress).reduce(0, +)) / total)
    }
    #expect(week(28).cells.allSatisfy { $0.average == nil })
    #expect(week(29).cells.allSatisfy { $0.average == mean($0.id, 28...28) })
    #expect(week(32).cells.allSatisfy { $0.average == mean($0.id, 28...31) })
    // Demo has no completion in W28, so W29's averages are 0 over one week: shown, not hidden.
    // Core's StatsTests pin one known week against four with data.
    #expect(week(29).cells.allSatisfy { $0.average != nil })
    // The future week's reference follows the same rule: the four known weeks before W40.
    #expect(week(41).cells.allSatisfy { $0.average == mean($0.id, 36...39) })
  }

  /// A future week has no count, and the same average for every future week: the four full weeks
  /// before the current one (owner, 2026-11-28).
  @MainActor @Test func aFutureWeeksStripShowsTheAverageOnly() async throws {
    let overview = try await demoOverview()
    let current = WeekScreen(overview)
    let w41 = WeekScreen(overview, week: ISOWeek(year: 2026, week: 41))
    let w43 = WeekScreen(overview, week: ISOWeek(year: 2026, week: 43))
    #expect(current.cells.allSatisfy { $0.thisWeek != nil })
    #expect(w41.cells.allSatisfy { $0.thisWeek == nil })
    #expect(w41.cells.map(\.average) == current.cells.map(\.average))
    #expect(w43.cells.map(\.average) == w41.cells.map(\.average))
    #expect(current.cells.contains { $0.average != WeekAverage(rhythm: 0, progress: 0) })
  }

  /// In Riga, not Demo's Moscow, which has no summer time.
  @Test func weeksAcrossTheDaylightSavingEndAndTheYearEnd() throws {
    let overview = Overview(workspace: Workspace(timeZone: riga), now: date(2026, 9, 30, 12))
    // W43: summer time ends in Riga on Sunday 25 October, a 25-hour day.
    let w43 = WeekScreen(overview, week: ISOWeek(year: 2026, week: 43))
    #expect(w43.week == 43)
    #expect(w43.days.map(\.start) == (19...25).map { date(2026, 10, $0) })
    let sunday = try #require(w43.days.last)
    #expect(date(2026, 10, 26).timeIntervalSince(sunday.start) == TimeInterval(25 * 3600))
    // 2026 has 53 ISO weeks: W53 starts Monday 28 December, 2027-W01 on 4 January.
    let calendar = overview.calendar
    let w53 = WeekScreen(
      overview, week: ISOWeek(year: 2026, week: 40).adding(13, calendar: calendar))
    #expect(w53.week == 53)
    #expect(w53.firstDay == date(2026, 12, 28))
    #expect(w53.days.count == 7)
    let w01 = WeekScreen(
      overview, week: ISOWeek(year: 2026, week: 40).adding(14, calendar: calendar))
    #expect(w01.week == 1)
    #expect(w01.firstDay == date(2027, 1, 4))
    #expect(w01.days.count == 7)
  }

  /// PR #75 round 2's deferred Low: the due text's window starts at the week's Monday 00:00.
  @Test func dueTextIsOnlyForTheShownWeeksOwnDays() {
    let tasks = [
      Self.item(
        "Planned last Wednesday", planned: date(2026, 9, 23, 9), due: date(2026, 9, 27, 23, 59)),
      Self.item(
        "Planned Tuesday, due last Sunday", planned: date(2026, 9, 29, 9),
        due: date(2026, 9, 27, 23, 59)),
    ]
    let overview = Overview(
      workspace: Workspace(timeZone: riga, tasks: tasks), now: date(2026, 9, 30, 12))
    let w39 = WeekScreen(overview, week: ISOWeek(year: 2026, week: 39))
    let last = w39.days.flatMap(\.cards).first { $0.title == "Planned last Wednesday" }
    #expect(last?.due?.date == date(2026, 9, 27, 23, 59))
    let w40 = WeekScreen(overview)
    let cards = Dictionary(uniqueKeysWithValues: w40.days.flatMap(\.cards).map { ($0.title, $0) })
    #expect(cards["Planned last Wednesday"] == nil)
    #expect(cards["Planned Tuesday, due last Sunday"] != nil)
    #expect(cards["Planned Tuesday, due last Sunday"]?.due == nil)
  }

  // MARK: Format

  @Test func rangeInOneYearAndAcrossTwo() {
    #expect(
      WeekFormat.range(date(2026, 9, 28), date(2026, 10, 4), timeZone: riga, locale: en)
        == "28 September – 4 October 2026")
    #expect(
      WeekFormat.range(date(2026, 12, 28), date(2027, 1, 3), timeZone: riga, locale: en)
        == "28 December 2026 – 3 January 2027")
    let russian = WeekFormat.range(date(2026, 9, 28), date(2026, 10, 4), timeZone: riga, locale: ru)
    #expect(russian.hasPrefix("28 сентября – 4 октября 2026"))
  }

  @Test func daysSoFarOnMondayThursdayAndSunday() {
    let monday = date(2026, 9, 28)
    #expect(
      WeekFormat.daysSoFar(first: monday, today: date(2026, 9, 28, 9), timeZone: riga, locale: en)
        == ("Mon", nil))
    #expect(
      WeekFormat.daysSoFar(first: monday, today: date(2026, 10, 1, 9), timeZone: riga, locale: en)
        == ("Mon", "Thu"))
    #expect(
      WeekFormat.daysSoFar(first: monday, today: date(2026, 10, 4, 23), timeZone: riga, locale: en)
        == ("Mon", "Sun"))
    #expect(
      WeekFormat.daysSoFar(first: monday, today: date(2026, 10, 1, 9), timeZone: riga, locale: ru)
        == ("пн", "чт"))
  }

  @Test func aColumnHeaderKeepsTheCapitalTextLowercasesRussian() {
    let thursday = date(2026, 10, 1, 9)
    #expect(WeekFormat.weekday(thursday, timeZone: riga, locale: en) == "Thu")
    #expect(WeekFormat.weekdayInText(thursday, timeZone: riga, locale: en) == "Thu")
    #expect(WeekFormat.weekdayInText(thursday, timeZone: riga, locale: ru) == "чт")
    #expect(
      WeekFormat.due(
        WeekScreen.Due(date: date(2026, 10, 2, 12), hasTime: true, isDeadline: false),
        timeZone: riga, locale: ru) == "пт 12:00")
  }

  @Test func averagesUseTheLocalesSeparator() {
    #expect(WeekFormat.average(4, locale: en) == "4.0")
    #expect(WeekFormat.average(4, locale: ru) == "4,0")
    #expect(WeekFormat.average(3.25, locale: ru).hasPrefix("3,"))
  }

  @Test func dueReadsTheWeekdayAndATimeWhenItHasOne() {
    let friday = date(2026, 10, 2, 12)
    #expect(
      WeekFormat.due(
        WeekScreen.Due(date: friday, hasTime: true, isDeadline: false), timeZone: riga,
        locale: en) == "Fri 12:00")
    #expect(
      WeekFormat.due(
        WeekScreen.Due(date: friday, hasTime: false, isDeadline: true), timeZone: riga,
        locale: en) == "Fri")
  }
}
