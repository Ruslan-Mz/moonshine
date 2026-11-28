import Foundation
import MoonShineCore
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

  private static func task(
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
      Self.task("Today, estimated", planned: date(2026, 9, 30, 18), estimate: 30),
      Self.task("Friday, no estimate", planned: date(2026, 10, 2, 9)),
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
      Self.task("Due next Monday 00:00", planned: tuesday, due: date(2026, 10, 5)),
      Self.task("Due Sunday 23:59", planned: tuesday, due: date(2026, 10, 4, 23, 59)),
      Self.task("Done, due Friday", due: date(2026, 10, 2, 12), completed: tuesday),
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
