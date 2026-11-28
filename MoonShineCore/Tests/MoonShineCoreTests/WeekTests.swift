import Foundation
import Testing

@testable import MoonShineCore

@Suite struct WeekTests {
  typealias W = TestWorld
  // Wednesday of 2026-W40 (Mon 28 Sep – Sun 4 Oct).
  let now = W.date(2026, 9, 30)

  func placement(_ week: WeekOverview) -> [String: [Int]] {
    var result: [String: [Int]] = [:]
    for (index, day) in week.days.enumerated() {
      for item in day.items { result[item.task.title, default: []].append(index) }
    }
    return result
  }

  @Test func sevenDaysFromMondayInLocalTime() {
    let week = Overview(workspace: W().workspace, now: now).week()
    #expect(week.week == ISOWeek(year: 2026, week: 40))
    #expect(week.days.count == 7)
    #expect(week.days.first?.day.start == W.date(2026, 9, 28, 0))
    #expect(week.days.last?.day.start == W.date(2026, 10, 4, 0))
    #expect(week.days.last?.day.end == W.date(2026, 10, 5, 0))
  }

  @Test func eachTaskAppearsOnceOnPlannedElseDeferElseDue() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "All three", line: violin, planned: W.date(2026, 9, 29, 9), defer: W.date(2026, 9, 30, 9),
      due: W.date(2026, 10, 2, 9))
    world.task(
      "Defer and due", line: violin, defer: W.date(2026, 10, 1, 9), due: W.date(2026, 10, 3, 9))
    world.task("Due only", line: violin, due: W.date(2026, 10, 4, 20))
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(placement(week) == ["All three": [1], "Defer and due": [3], "Due only": [6]])
  }

  @Test func dueBadgeOnlyWhenTheDueDateIsInTheSameWeek() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Due Friday", line: violin, planned: W.date(2026, 9, 29, 9), due: W.date(2026, 10, 2, 9))
    world.task(
      "Due next Monday", line: violin, planned: W.date(2026, 9, 29, 9),
      due: W.date(2026, 10, 5, 9))
    world.task("Due Sunday", line: violin, due: W.date(2026, 10, 4, 9))
    let items = Overview(workspace: world.workspace, now: now).week().days.flatMap(\.items)
    let badges = Dictionary(uniqueKeysWithValues: items.map { ($0.task.title, $0.hasDueBadge) })
    #expect(badges == ["Due Friday": true, "Due next Monday": false, "Due Sunday": true])
  }

  @Test func inheritedDatesPlaceTasksAndGiveTheDueBadge() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Group planned Thursday", line: violin, inheritedPlanned: W.date(2026, 10, 1, 9))
    world.task(
      "Own planned beats inherited", line: violin, planned: W.date(2026, 9, 29, 9),
      inheritedPlanned: W.date(2026, 10, 1, 9))
    world.task(
      "Project due Saturday", line: violin, planned: W.date(2026, 9, 28, 9),
      inheritedDue: W.date(2026, 10, 3, 18))
    world.task("Project due Friday only", line: violin, inheritedDue: W.date(2026, 10, 2, 18))
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(
      placement(week) == [
        "Group planned Thursday": [3], "Own planned beats inherited": [1],
        "Project due Saturday": [0], "Project due Friday only": [4],
      ])
    let badges = week.days.flatMap(\.items).filter(\.hasDueBadge).map(\.task.title)
    #expect(Set(badges) == ["Project due Saturday", "Project due Friday only"])
    #expect(week.noPlan.isEmpty)
  }

  @Test func tasksAnchoredOutsideTheWeekOrNotAvailableAreNotShown() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Last Friday", line: violin, planned: W.date(2026, 9, 25, 9))
    world.task("Next Tuesday", line: violin, planned: W.date(2026, 10, 6, 9))
    world.task(
      "Done Tuesday", line: violin, planned: W.date(2026, 9, 29, 9),
      completed: W.date(2026, 9, 29, 10))
    world.task("Blocked Tuesday", line: violin, status: .blocked, planned: W.date(2026, 9, 29, 9))
    world.task("Sunday 23:30", line: violin, planned: W.date(2026, 10, 4, 23, 30))
    let week = Overview(workspace: world.workspace, now: now).week()
    // A completion sits on its day since S5-1 (owner, 2026-11-27).
    #expect(placement(week) == ["Done Tuesday": [1], "Sunday 23:30": [6]])
  }

  @Test func noPlanTrayHoldsUndatedAvailableTasksInActiveLinesOnly() {
    var world = W()
    let active = LineAssignment.line(world.line("violin").id)
    let maintenance = LineAssignment.line(world.line("piano", state: .maintenance).id)
    world.task("Undated", line: active)
    world.task("Dated", line: active, planned: W.date(2026, 10, 20))
    world.task("Undated, done", line: active, completed: W.date(2026, 9, 1))
    world.task("Undated, maintenance", line: maintenance)
    world.task("Undated, life ops", line: .lifeOps)
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(week.noPlan.map(\.task.title) == ["Undated"])
  }

  @Test func headerComparesThisWeekWithTheFourWeeksBefore() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    world.session("Scales", line: violin, at: W.date(2026, 9, 29))
    for day in [1, 8, 15, 22] {
      world.task("Etude \(day)", line: violin, completed: W.date(2026, 9, day))
    }
    let header = Overview(workspace: world.workspace, now: now).week().header
    #expect(header.map(\.line) == [violin, piano, .lifeOps])
    #expect(header.first?.thisWeek == WeekCounts(rhythm: 1))
    #expect(header.first?.previousAverage == WeekAverage(rhythm: 0, progress: 1))
  }

  // MARK: S5-1 (owner, 2026-11-27)

  @Test func onlyLeafTasksArePlaced() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let group = world.task("Group", line: violin, planned: W.date(2026, 9, 29, 9))
    world.task("Step", line: violin, parent: group.id, planned: W.date(2026, 9, 29, 9))
    let undated = world.task("Undated group", line: violin)
    world.task("Undated step", line: violin, parent: undated.id)
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(placement(week) == ["Step": [1]])
    #expect(week.noPlan.map { $0.task.title } == ["Undated step"])
  }

  @Test func blockedTasksArePlacedOnlyWhenDeferredPastNow() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Deferred Friday", line: violin, status: .blocked, defer: W.date(2026, 10, 2, 9))
    world.task(
      "Deferred Monday, still blocked", line: violin, status: .blocked,
      defer: W.date(2026, 9, 28, 9))
    world.task(
      "Blocked, planned Thursday", line: violin, status: .blocked,
      planned: W.date(2026, 10, 1, 9))
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(placement(week) == ["Deferred Friday": [4]])
  }

  @Test func onHoldProjectsAreInNoColumnAndNotInTheTray() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let held = world.project("Held", line: violin, status: .onHold)
    let active = world.project("Active", line: violin)
    world.task("Held, Thursday", line: violin, project: held.id, planned: W.date(2026, 10, 1, 9))
    world.task("Held, undated", line: violin, project: held.id)
    world.task("Active, undated", line: violin, project: active.id)
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(placement(week).isEmpty)
    #expect(week.noPlan.map { $0.task.title } == ["Active, undated"])
  }

  @Test func completionsSitOnTheirDayAfterTheOpenTasks() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Done Monday, planned Friday", line: violin, planned: W.date(2026, 10, 2, 9),
      completed: W.date(2026, 9, 28, 10))
    world.task("Open Monday", line: violin, planned: W.date(2026, 9, 28, 18))
    world.task("Done today", line: .lifeOps, completed: W.date(2026, 9, 30, 9))
    world.task(
      "Done last week, planned Tuesday", line: violin, planned: W.date(2026, 9, 29, 9),
      completed: W.date(2026, 9, 25, 10))
    let week = Overview(workspace: world.workspace, now: now).week()
    #expect(
      placement(week) == [
        "Done Monday, planned Friday": [0], "Open Monday": [0], "Done today": [2],
      ])
    #expect(
      week.days[0].items.map { $0.task.title } == ["Open Monday", "Done Monday, planned Friday"])
    #expect(week.days[0].items.map(\.isCompleted) == [false, true])
    #expect(week.days.map(\.doneCount) == [1, 0, 1, 0, 0, 0, 0])
  }

  @Test func aCompletedDeadlineHasNoBadge() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Due Tuesday, done Monday", line: violin, due: W.date(2026, 9, 29, 18),
      completed: W.date(2026, 9, 28, 10))
    let items = Overview(workspace: world.workspace, now: now).week().days.flatMap(\.items)
    #expect(items.map(\.hasDueBadge) == [false])
  }

  @Test func dayEstimatesSumTheOpenItemsPositiveEstimatesSaturating() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let tuesday = W.date(2026, 9, 29, 9)
    world.task("A", line: violin, planned: tuesday, estimate: 20)
    world.task("B", line: violin, planned: tuesday)
    world.task("C", line: violin, planned: tuesday, estimate: 30)
    world.task("D", line: violin, planned: tuesday, estimate: -5)
    world.task("Done", line: violin, planned: tuesday, estimate: 50, completed: tuesday)
    world.task("Huge", line: violin, planned: W.date(2026, 10, 1, 9), estimate: .max)
    world.task("More", line: violin, planned: W.date(2026, 10, 1, 9), estimate: 5)
    let days = Overview(workspace: world.workspace, now: now).week().days
    #expect(days.map(\.estimateMinutes) == [0, 50, 0, .max, 0, 0, 0])
  }

  @Test func headerKeepsEveryLineAndSaysWhichSeriesApply() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    let japanese = LineAssignment.line(world.line("japanese").id)
    let italian = LineAssignment.line(world.line("italian", state: .paused).id)
    world.session("Scales", line: violin, at: W.date(2026, 8, 3))
    world.task("Sonatina", line: piano, completed: W.date(2026, 9, 2))
    world.task("Kana", line: japanese)
    let header = Overview(workspace: world.workspace, now: now).week().header
    // Every line and Life ops; Week's screen leaves paused lines and Life ops out of the strip.
    #expect(header.map(\.line) == [violin, piano, japanese, italian, .lifeOps])
    #expect(header.map(\.hasRhythm) == [true, false, false, false, false])
    #expect(header.map(\.hasProgress) == [false, true, false, false, false])
  }

  @Test func aDaylightSavingWeekHasSevenLocalDays() throws {
    // W43 2026 in Riga: summer time ends on Sunday 25 October, a 25-hour day.
    let riga = TimeZone(identifier: "Europe/Riga")!
    let calendar = Calendar.iso8601(in: riga)
    let date = { (d: Int) in
      calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }
    let week = Overview(workspace: Workspace(timeZone: riga), now: date(21)).week()
    #expect(week.days.map(\.day.start) == (19...25).map(date))
    let sunday = try #require(week.days.last).day
    #expect(sunday.end == date(26))
    #expect(sunday.end.timeIntervalSince(sunday.start) == 25 * 3600)
  }

  // MARK: S5-1b, another week (owner, 2026-11-28)

  @Test func weekIsTheWeekContainingNow() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Tuesday", line: violin, planned: W.date(2026, 9, 29, 9))
    let overview = Overview(workspace: world.workspace, now: now)
    #expect(overview.week() == overview.week(containing: now))
  }

  @Test func nextWeekPlacesItsTasksAndHasNoCompletions() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("This Tuesday", line: violin, planned: W.date(2026, 9, 29, 9))
    world.task("Next Tuesday", line: violin, planned: W.date(2026, 10, 6, 9))
    world.task("Next Sunday, due", line: violin, due: W.date(2026, 10, 11, 9))
    world.task("Done today", line: violin, completed: W.date(2026, 9, 30, 9))
    let week = Overview(workspace: world.workspace, now: now).week(
      containing: W.date(2026, 10, 7))
    #expect(week.week == ISOWeek(year: 2026, week: 41))
    #expect(week.days.first?.day.start == W.date(2026, 10, 5, 0))
    #expect(placement(week) == ["Next Tuesday": [1], "Next Sunday, due": [6]])
    #expect(
      week.days.flatMap(\.items).filter(\.hasDueBadge).map(\.task.title) == ["Next Sunday, due"])
  }

  @Test func lastWeekShowsItsCompletionsAndTheTasksStillOpenFromIt() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Done last Tuesday", line: violin, completed: W.date(2026, 9, 22, 10))
    world.task("Open from last Thursday", line: violin, planned: W.date(2026, 9, 24, 9))
    world.task("This Tuesday", line: violin, planned: W.date(2026, 9, 29, 9))
    let week = Overview(workspace: world.workspace, now: now).week(
      containing: W.date(2026, 9, 23))
    #expect(week.week == ISOWeek(year: 2026, week: 39))
    #expect(placement(week) == ["Done last Tuesday": [1], "Open from last Thursday": [3]])
  }

  @Test func aPastWeeksHeaderCountsThatWeekAgainstTheFourBeforeIt() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.session("Scales", line: violin, at: W.date(2026, 9, 22))
    world.task("Etude", line: violin, completed: W.date(2026, 9, 1))
    let header = Overview(workspace: world.workspace, now: now).week(
      containing: W.date(2026, 9, 23)
    ).header
    #expect(header.first?.thisWeek == WeekCounts(rhythm: 1))
    // W35–W38: one etude in W36.
    #expect(header.first?.previousAverage == WeekAverage(rhythm: 0, progress: 0.25))
  }

  /// A future week has no count: `■ 0` would read as a failure before the week starts. Its
  /// average is the four full weeks before the current one, the same for every future week.
  @Test func aFutureWeekHasNoCountAndTheAverageBeforeTheCurrentWeek() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    for day in [1, 8, 15, 22] {
      world.task("Etude \(day)", line: violin, completed: W.date(2026, 9, day))
    }
    world.session("Scales", line: violin, at: W.date(2026, 9, 29))
    let overview = Overview(workspace: world.workspace, now: now)
    let current = overview.week().header.first
    #expect(current?.thisWeek == WeekCounts(rhythm: 1))
    for date in [W.date(2026, 10, 7), W.date(2026, 10, 21)] {
      let future = overview.week(containing: date).header.first
      #expect(future?.thisWeek == nil)
      #expect(future?.previousAverage == WeekAverage(rhythm: 0, progress: 1))
      #expect(future?.previousAverage == current?.previousAverage)
    }
  }

  @Test(arguments: [Date.distantPast, Date.distantFuture])
  func anyDateGivesSevenDaysHoldingIt(date: Date) {
    let week = Overview(workspace: W().workspace, now: now).week(containing: date)
    #expect(week.days.count == 7)
    #expect(week.days.contains { $0.day.contains(date) })
  }
}
