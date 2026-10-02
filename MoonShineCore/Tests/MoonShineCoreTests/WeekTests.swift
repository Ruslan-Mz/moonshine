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
    #expect(placement(week) == ["Sunday 23:30": [6]])
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
}
