import Foundation
import Testing

@testable import MoonShineCore

@Suite struct TodayTests {
  typealias W = TestWorld
  // Wednesday 2026-09-30, noon in Moscow.
  let now = W.date(2026, 9, 30)

  func titles(_ today: TodayOverview) -> Set<String> {
    Set(today.groups.flatMap(\.items).map(\.task.title))
  }

  @Test func includesPlannedDeferredFlaggedAndDueUpToToday() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Planned today", line: violin, planned: W.date(2026, 9, 30, 18))
    world.task("Deferred to today", line: violin, defer: W.date(2026, 9, 30, 9))
    world.task("Flagged", line: violin, flagged: true)
    world.task("Due today", line: violin, due: W.date(2026, 9, 30, 20))
    world.task("Due yesterday", line: violin, due: W.date(2026, 9, 29, 20))
    world.task("Planned tomorrow", line: violin, planned: W.date(2026, 10, 1, 9))
    world.task("Due tomorrow", line: violin, due: W.date(2026, 10, 1, 9))
    world.task("Deferred yesterday", line: violin, defer: W.date(2026, 9, 29, 9))
    world.task("No dates", line: violin)
    world.task("Blocked flagged", line: violin, status: .blocked, flagged: true)
    world.task("Done flagged", line: violin, flagged: true, completed: W.date(2026, 9, 30, 8))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      titles(today) == [
        "Planned today", "Deferred to today", "Flagged", "Due today", "Due yesterday",
      ])
  }

  @Test func onlyARealDueDateIsUrgent() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Flagged", line: violin, flagged: true, planned: W.date(2026, 9, 30, 9))
    world.task("Due", line: violin, due: W.date(2026, 9, 30, 20))
    let items = Overview(workspace: world.workspace, now: now).today().groups.flatMap(\.items)
    let flagged = try #require(items.first { $0.task.title == "Flagged" })
    let due = try #require(items.first { $0.task.title == "Due" })
    #expect(flagged.reasons == [.flagged, .planned])
    #expect(!flagged.isUrgent)
    #expect(due.reasons == [.due])
    #expect(due.isUrgent)
  }

  @Test func inheritedDatesPlaceTasksAndAnInheritedDueDateIsUrgent() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Project due today", line: violin, inheritedDue: W.date(2026, 9, 30, 18))
    world.task("Group planned today", line: violin, inheritedPlanned: W.date(2026, 9, 30, 9))
    world.task("Project deferred to today", line: violin, inheritedDefer: W.date(2026, 9, 30, 6))
    world.task("Group planned Monday", line: violin, inheritedPlanned: W.date(2026, 9, 28, 9))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      titles(today) == ["Project due today", "Group planned today", "Project deferred to today"])
    let due = try #require(
      today.groups.flatMap(\.items).first { $0.task.title == "Project due today" })
    #expect(due.reasons == [.due])
    #expect(due.isUrgent)
    #expect(today.fromEarlier.map(\.task.title) == ["Group planned Monday"])
    #expect(today.fromEarlier.first?.plannedDaysAgo == 2)
  }

  @Test func groupsFollowVaultLineOrderWithLifeOpsLast() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    world.line("math")
    world.task("Pay rent", line: .lifeOps, flagged: true)
    world.task("Chords", line: piano, flagged: true)
    world.task("Scales", line: violin, flagged: true)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.groups.map(\.line) == [violin, piano, .lifeOps])
  }

  @Test func eachItemCarriesItsTrace() throws {
    var world = W()
    let violin = world.line("violin")
    let project = world.project("Partita", line: .line(violin.id))
    let task = world.task("Bars 1–16", line: .line(violin.id), project: project.id, flagged: true)
    let item = try #require(
      Overview(workspace: world.workspace, now: now).today().groups.first?.items.first)
    #expect(item.trace == Tracer(workspace: world.workspace, now: now).trace(task))
    #expect(item.trace.project == project)
  }

  @Test func dayBoundsAreLocalMidnights() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Late tonight", line: violin, planned: W.date(2026, 9, 30, 23, 30))
    world.task("Late last night", line: violin, planned: W.date(2026, 9, 29, 23, 30))
    // 00:30 Moscow is still the 29th in UTC.
    let today = Overview(workspace: world.workspace, now: W.date(2026, 9, 30, 0, 30)).today()
    #expect(today.day.start == W.date(2026, 9, 30, 0))
    #expect(today.day.end == W.date(2026, 10, 1, 0))
    #expect(titles(today) == ["Late tonight"])
    #expect(today.fromEarlier.map(\.task.title) == ["Late last night"])
    #expect(today.fromEarlier.first?.plannedDaysAgo == 1)
  }

  @Test func plannedEarlierIsCarriedOverOnceOldestFirstAndUrgentOnlyWhenDue() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Three days ago, flagged", line: violin, flagged: true, planned: W.date(2026, 9, 27, 10))
    world.task(
      "Five days ago, due today", line: violin, planned: W.date(2026, 9, 25, 10),
      due: W.date(2026, 9, 30, 18))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.groups.isEmpty)
    #expect(
      today.fromEarlier.map(\.task.title) == [
        "Five days ago, due today", "Three days ago, flagged",
      ])
    #expect(today.fromEarlier.map(\.plannedDaysAgo) == [5, 3])
    #expect(today.fromEarlier.map(\.isUrgent) == [true, false])
  }

  @Test func quietLinesAreActiveOnlyAndNoActivityYetIsItsOwnCase() {
    var world = W()
    let quiet = world.line("violin")
    let recent = world.line("piano")
    let fresh = world.line("italian")
    let paused = world.line("calligraphy", state: .paused)
    let maintenance = world.line("math", state: .maintenance)
    world.task("A", line: .line(quiet.id), completed: W.date(2026, 9, 16, 22))
    world.task("B", line: .line(recent.id), completed: W.date(2026, 9, 17, 8))
    world.task("C", line: .line(maintenance.id), completed: W.date(2026, 8, 1))
    world.task("D", line: .lifeOps, completed: W.date(2026, 8, 1))
    _ = (fresh, paused)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      today.quietLines == [
        QuietLine(line: quiet, reason: .lastActivity(W.date(2026, 9, 16, 22))),
        QuietLine(line: fresh, reason: .noActivityYet),
      ])
  }

  @Test func touchedTodayListsLinesWithACompletionToday() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    world.task("Pay rent", line: .lifeOps, completed: W.date(2026, 9, 30, 9))
    world.session("Scales", line: violin, at: W.date(2026, 9, 30, 7))
    world.task("Chords", line: piano, completed: W.date(2026, 9, 29, 21))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.touchedToday == [violin, .lifeOps])
  }
}
