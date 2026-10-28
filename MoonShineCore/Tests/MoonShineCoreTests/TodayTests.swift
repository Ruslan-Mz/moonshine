import Foundation
import Testing

@testable import MoonShineCore

@Suite struct TodayTests {
  typealias W = TestWorld
  // Wednesday 2026-09-30, noon in Moscow.
  let now = W.date(2026, 9, 30)

  /// Open items planned for today or undated, wherever Today shows them (strip, Top 3, lines).
  func titles(_ today: TodayOverview) -> Set<String> {
    Set(today.items.filter { !$0.isDone && $0.plannedDaysAgo == nil }.map(\.task.title))
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
    #expect(today.doneToday.map(\.task.title) == ["Done flagged"])
  }

  @Test func onlyARealDueDateIsUrgent() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Flagged", line: violin, flagged: true, planned: W.date(2026, 9, 30, 9))
    world.task("Due", line: violin, due: W.date(2026, 9, 30, 20))
    let items = Overview(workspace: world.workspace, now: now).today().items
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
    world.task("Pay rent", line: .lifeOps, planned: W.date(2026, 9, 30, 9))
    world.task("Chords", line: piano, planned: W.date(2026, 9, 30, 9))
    world.task("Scales", line: violin, planned: W.date(2026, 9, 30, 9))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.groups.map(\.line) == [violin, piano, .lifeOps])
  }

  @Test func eachItemCarriesItsTrace() throws {
    var world = W()
    let violin = world.line("violin")
    let project = world.project("Partita", line: .line(violin.id))
    let task = world.task("Bars 1–16", line: .line(violin.id), project: project.id, flagged: true)
    let item = try #require(Overview(workspace: world.workspace, now: now).today().items.first)
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
    world.task("Three days ago", line: violin, planned: W.date(2026, 9, 27, 10))
    world.task(
      "Five days ago, due today", line: violin, planned: W.date(2026, 9, 25, 10),
      due: W.date(2026, 9, 30, 18))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.groups.isEmpty)
    #expect(
      today.fromEarlier.map(\.task.title) == [
        "Five days ago, due today", "Three days ago",
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
    let foundation = world.line("core", foundation: true)
    let newFoundation = world.line("calisthenics", foundation: true)
    let last = world.task("A", line: .line(quiet.id), completed: W.date(2026, 9, 16, 22))
    world.task("B", line: .line(recent.id), completed: W.date(2026, 9, 17, 8))
    world.task("C", line: .line(maintenance.id), completed: W.date(2026, 8, 1))
    world.task("D", line: .lifeOps, completed: W.date(2026, 8, 1))
    world.task("E", line: .line(foundation.id), completed: W.date(2026, 8, 1))
    let first = world.task("Warm-up", line: .line(newFoundation.id))
    _ = (fresh, paused)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      today.quietLines == [
        QuietLine(line: quiet, reason: .quiet(days: 14, last: last), nextStep: nil),
        QuietLine(line: fresh, reason: .noActivityYet, nextStep: nil),
        QuietLine(line: newFoundation, reason: .noActivityYet, nextStep: first),
      ])
  }

  @Test func lastTaskIsTheLatestCompletionAndTheFirstInSourceOrderOnATie() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    world.task("Older", line: line, completed: W.date(2026, 9, 1, 9))
    let first = world.task("Same time, first", line: line, completed: W.date(2026, 9, 2, 9))
    world.task("Same time, second", line: line, completed: W.date(2026, 9, 2, 9))
    let today = Overview(workspace: world.workspace, now: now).today()
    let quiet = try #require(today.quietLines.first)
    #expect(quiet.reason == .quiet(days: 28, last: first))
  }

  @Test func nextStepIsTheFirstAvailableNextActionInSourceOrder() throws {
    var world = W()
    let violin = world.line("violin")
    let italian = world.line("italian")
    let japanese = world.line("japanese")
    let line = LineAssignment.line(violin.id)
    world.task("Lesson", line: line, completed: W.date(2026, 9, 1))
    world.task("Blocked", line: line, status: .blocked)
    world.task("Done", line: line, completed: W.date(2026, 8, 30))
    let parent = world.task("Parent with an open child", line: line)
    world.task("Dropped", line: line, status: .dropped)
    let child = world.task("Child", line: line, parent: parent.id)
    world.task("Later", line: line)
    // A parent whose children are all done is a next action itself.
    let italianLine = LineAssignment.line(italian.id)
    world.task("Old", line: italianLine, completed: W.date(2026, 9, 1))
    let review = world.task("Review", line: italianLine)
    world.task("Read", line: italianLine, parent: review.id, completed: W.date(2026, 9, 1))
    // No completions and no next action.
    world.task("Waiting", line: .line(japanese.id), status: .blocked)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.quietLines.map(\.nextStep) == [child, review, nil])
    #expect(today.quietLines.last?.reason == .noActivityYet)
  }

  @Test func nextStepAlsoComesWithNoActivityYet() throws {
    var world = W()
    let japanese = world.line("japanese")
    let first = world.task("Learn kana", line: .line(japanese.id))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      today.quietLines == [QuietLine(line: japanese, reason: .noActivityYet, nextStep: first)])
  }

  @Test func touchedTodayListsLinesWithACompletionTodayAndTheirCounts() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    let calligraphy = LineAssignment.line(world.line("calligraphy", state: .paused).id)
    world.task("Pay rent", line: .lifeOps, completed: W.date(2026, 9, 30, 9))
    world.session("Scales", line: violin, at: W.date(2026, 9, 30, 7))
    world.task("Chords", line: piano, completed: W.date(2026, 9, 29, 21))
    world.task("Ink", line: calligraphy, completed: W.date(2026, 9, 30, 10))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      today.touchedToday == [
        TouchedLine(line: violin, counts: WeekCounts(rhythm: 1)),
        TouchedLine(line: .lifeOps, counts: WeekCounts(progress: 1)),
      ])
  }

  @Test func aSessionThatStraddlesMidnightCountsOnBothDays() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let group = world.session("Evening practice", line: violin, at: W.date(2026, 9, 29, 23, 50))
    world.session("Etude", line: violin, at: W.date(2026, 9, 29, 23, 50), parent: group.id)
    world.session("Scales", line: violin, at: W.date(2026, 9, 30, 0, 10), parent: group.id)
    world.session("Open strings", line: violin, at: W.date(2026, 9, 30, 0, 20), parent: group.id)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.touchedToday == [TouchedLine(line: violin, counts: WeekCounts(rhythm: 1))])
    let yesterday = Overview(workspace: world.workspace, now: W.date(2026, 9, 29)).today()
    #expect(yesterday.touchedToday == [TouchedLine(line: violin, counts: WeekCounts(rhythm: 1))])
  }

  @Test func pausedLinesAreListedInVaultOrder() {
    var world = W()
    world.line("violin")
    let calligraphy = world.line("calligraphy", state: .paused)
    world.line("piano", state: .maintenance)
    let chess = world.line("chess", state: .paused)
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.pausedLines == [calligraphy, chess])
  }

  // MARK: Done today, order, anchors, Top 3, totals (S4-1b-1)

  @Test func everyTaskDoneTodayIsInDoneTodayMostRecentFirstAndNowhereElse() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task(
      "Planned today", line: violin, planned: W.date(2026, 9, 30, 8),
      completed: W.date(2026, 9, 30, 9))
    world.task("No date", line: .lifeOps, completed: W.date(2026, 9, 30, 15))
    world.task(
      "Planned Monday", line: violin, planned: W.date(2026, 9, 28, 10),
      completed: W.date(2026, 9, 30, 11))
    world.task(
      "Flagged, due today", line: violin, flagged: true, due: W.date(2026, 9, 30, 18),
      completed: W.date(2026, 9, 30, 11))
    world.task("Done yesterday", line: violin, completed: W.date(2026, 9, 29, 21))
    world.task("Dropped", line: violin, status: .dropped, planned: W.date(2026, 9, 30, 9))
    world.task("Open", line: violin, planned: W.date(2026, 9, 30, 9))
    let today = Overview(workspace: world.workspace, now: now).today()
    // Same completion time: source order.
    #expect(
      today.doneToday.map(\.task.title) == [
        "No date", "Planned Monday", "Flagged, due today", "Planned today",
      ])
    #expect(today.doneToday.allSatisfy { $0.isDone && !$0.isUrgent && $0.plannedDaysAgo == nil })
    let elsewhere = today.groups.flatMap(\.items) + today.fromEarlier + today.top
    #expect(elsewhere.map(\.task.title) == ["Open"])
    #expect(today.totals.done == 4)
    #expect(today.totals.open == 1)
  }

  @Test func foundationGroupsComeFirstThenVaultOrderThenLifeOps() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let core = LineAssignment.line(world.line("core", foundation: true).id)
    let piano = LineAssignment.line(world.line("piano").id)
    let gym = LineAssignment.line(world.line("gym", foundation: true).id)
    for line in [LineAssignment.lifeOps, piano, gym, violin, core] {
      world.task("Task", line: line, planned: W.date(2026, 9, 30, 9))
    }
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.groups.map(\.line) == [core, gym, violin, piano, .lifeOps])
  }

  @Test func leafTagMatchIsTrimmedAndCaseInsensitive() {
    func tag(_ name: String) -> MoonShineCore.Tag {
      Tag(id: .generate(), refs: [], name: name, parentID: nil, isMeta: false)
    }
    #expect(tag(" Anchor ").matchesLeafName("anchor"))
    #expect(tag("ANCHOR").matchesLeafName("  anchor\n"))
    #expect(tag("Якорь").matchesLeafName("якорь"))
    #expect(!tag("anchors").matchesLeafName("anchor"))
    #expect(!tag("deadline").matchesLeafName("anchor"))
  }

  @Test func anchorsAreOwnTagsAndOnlyTheFirstFiveShownLeaveTheirSections() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let rituals = world.tag("Rituals")
    let anchor = world.tag("Anchor", parent: rituals.id)
    let project = world.project("Daily", line: violin, tags: [anchor.id])
    world.task(
      "Done anchor", line: violin, planned: W.date(2026, 9, 30, 7),
      completed: W.date(2026, 9, 30, 8), tags: [anchor.id])
    for n in 1...6 {
      world.task("A\(n)", line: violin, planned: W.date(2026, 9, 30, 9), tags: [anchor.id])
    }
    world.task(
      "In an anchor project", line: violin, project: project.id,
      planned: W.date(2026, 9, 30, 9))
    world.task("Not today", line: violin, tags: [anchor.id])
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(
      today.anchors.map(\.task.title) == ["Done anchor", "A1", "A2", "A3", "A4", "A5", "A6"])
    #expect(Overview.anchorsShown == 5)
    let group = try #require(today.groups.first)
    #expect(group.items.map(\.task.title) == ["A5", "A6", "In an anchor project"])
    // A done anchor shown in the strip stays only there.
    #expect(today.doneToday.isEmpty)
    #expect(today.totals.done == 1)
  }

  /// Owner, 2026-10-26: a done anchor among the first five chips is only in the strip; a done
  /// anchor beyond them is in Done today; both count as done.
  @Test func aDoneAnchorBeyondTheFifthChipIsInDoneTodayAndBothCount() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let anchor = world.tag("anchor")
    for n in 1...4 {
      world.task("A\(n)", line: violin, planned: W.date(2026, 9, 30, 9), tags: [anchor.id])
    }
    world.task(
      "Fifth, done", line: violin, planned: W.date(2026, 9, 30, 9),
      completed: W.date(2026, 9, 30, 10), tags: [anchor.id])
    world.task(
      "Sixth, done", line: violin, planned: W.date(2026, 9, 30, 9),
      completed: W.date(2026, 9, 30, 11), tags: [anchor.id])
    world.task("Other, done", line: violin, completed: W.date(2026, 9, 30, 8))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.anchors.prefix(Overview.anchorsShown).last?.task.title == "Fifth, done")
    #expect(today.doneToday.map(\.task.title) == ["Sixth, done", "Other, done"])
    #expect(today.totals.done == 3)
  }

  @Test func topThreeIsOpenFlaggedDueFirstThenSourceOrderAndShowAllShowsEveryCandidate() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("F1", line: violin, flagged: true)
    world.task("F2", line: violin, flagged: true, due: W.date(2026, 9, 30, 18))
    world.task("F3", line: violin, flagged: true)
    world.task("F4", line: violin, flagged: true, due: W.date(2026, 9, 29, 18))
    world.task("F5", line: .lifeOps, flagged: true)
    world.task("Done", line: violin, flagged: true, completed: W.date(2026, 9, 30, 9))
    let overview = Overview(workspace: world.workspace, now: now)
    let today = overview.today()
    #expect(today.top.map(\.task.title) == ["F2", "F4", "F1"])
    #expect(today.flaggedCount == 5)
    #expect(today.groups.flatMap(\.items).map(\.task.title) == ["F3", "F5"])
    let all = overview.today(showAllFlagged: true)
    #expect(all.top.map(\.task.title) == ["F2", "F4", "F1", "F3", "F5"])
    #expect(all.flaggedCount == 5)
    #expect(all.groups.isEmpty)
  }

  @Test func aFlaggedAnchorInTheStripIsNoTopThreeCandidate() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let anchor = world.tag("anchor")
    world.task("Flagged anchor", line: violin, flagged: true, tags: [anchor.id])
    for n in 1...3 { world.task("F\(n)", line: violin, flagged: true) }
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.anchors.map(\.task.title) == ["Flagged anchor"])
    #expect(today.top.map(\.task.title) == ["F1", "F2", "F3"])
    #expect(today.flaggedCount == 3)
    #expect(today.groups.isEmpty)
  }

  @Test func stripTopGroupsFromEarlierAndDoneTodayAreDisjointAndCoverItems() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let anchor = world.tag("anchor")
    world.task("Anchor", line: violin, planned: W.date(2026, 9, 30, 9), tags: [anchor.id])
    world.task("Flagged", line: violin, flagged: true)
    world.task("Planned", line: violin, planned: W.date(2026, 9, 30, 9))
    world.task("Earlier", line: violin, planned: W.date(2026, 9, 27, 9))
    world.task("Errand", line: .lifeOps, due: W.date(2026, 9, 30, 20))
    world.task("Done", line: violin, completed: W.date(2026, 9, 30, 10))
    world.task(
      "Done anchor", line: violin, completed: W.date(2026, 9, 30, 11), tags: [anchor.id])
    let today = Overview(workspace: world.workspace, now: now).today()
    let strip = today.anchors.prefix(Overview.anchorsShown)
    let parts =
      strip + today.top + today.groups.flatMap(\.items) + today.fromEarlier + today.doneToday
    #expect(parts.count == today.items.count)
    #expect(Set(parts.map(\.task.id)) == Set(today.items.map(\.task.id)))
    #expect(
      today.items.map(\.task.title) == [
        "Anchor", "Flagged", "Planned", "Earlier", "Errand", "Done", "Done anchor",
      ])
  }

  @Test func totalsCountEveryItemOnceAndEstimateOnlyOpenOnes() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Planned", line: violin, planned: W.date(2026, 9, 30, 9), estimate: 45)
    world.task("Flagged", line: violin, flagged: true, estimate: 30)
    world.task("Earlier", line: violin, planned: W.date(2026, 9, 27, 9), estimate: 15)
    world.task("Errand", line: .lifeOps, flagged: true, estimate: -20)
    world.task("No estimate", line: .lifeOps, flagged: true)
    world.task("Done", line: violin, estimate: 60, completed: W.date(2026, 9, 30, 10))
    let today = Overview(workspace: world.workspace, now: now).today()
    #expect(today.totals == TodayTotals(open: 5, done: 1, estimateMinutes: 90))

    var huge = W()
    huge.task("Big", line: .lifeOps, flagged: true, estimate: .max)
    huge.task("Small", line: .lifeOps, flagged: true, estimate: 1)
    #expect(Overview(workspace: huge.workspace, now: now).today().totals.estimateMinutes == .max)
  }
}
