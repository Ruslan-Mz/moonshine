import Foundation
import Testing

@testable import MoonShineCore

/// `design/screens/line-detail.md` § Data, on invented data.
@Suite struct LineDetailTests {
  typealias W = TestWorld
  /// Wednesday of ISO week 40.
  let now = W.date(2026, 9, 30)

  func detail(_ line: Line, _ world: W, at now: Date? = nil) throws -> LineDetail {
    try #require(Overview(workspace: world.workspace, now: now ?? self.now).lineDetail(line.id))
  }

  // MARK: The line

  @Test func anUnknownIdHasNoDetail() {
    var world = W()
    world.line("violin")
    var other = W()
    let foreign = other.line("violin")
    #expect(Overview(workspace: world.workspace, now: now).lineDetail(foreign.id) == nil)
  }

  @Test func anEmptyLineHasEmptyListsAndZeroWeeks() throws {
    var world = W()
    let violin = world.line("violin")
    let detail = try detail(violin, world)
    #expect(detail.line == violin)
    #expect(detail.projects.isEmpty)
    #expect(detail.nextActions.isEmpty)
    #expect(detail.completions.isEmpty)
    #expect(detail.weeks.count == Overview.sparklineWeeks)
    #expect(detail.weeks.allSatisfy { $0.counts == .zero })
    #expect(detail.weeks.last?.isPartial == true)
    #expect(detail.average == WeekAverage(rhythm: 0, progress: 0))
  }

  /// Lines and Line detail read one helper, so they cannot disagree.
  @Test func lastActivityIsTheValueLinesShows() throws {
    var world = W()
    let violin = world.line("violin")
    let italian = world.line("italian")
    let calligraphy = world.line("calligraphy", state: .paused)
    let piano = world.line("piano", state: .maintenance)
    world.task("Scales", line: .line(violin.id), completed: W.date(2026, 9, 30, 9))
    world.task("Lesson", line: .line(italian.id), completed: W.date(2026, 9, 2))
    world.task("Brush", line: .line(calligraphy.id), completed: W.date(2026, 7, 14))
    let rows = Overview(workspace: world.workspace, now: now).lines().tiers.flatMap(\.rows)
    for line in [violin, italian, calligraphy, piano] {
      let lines = try #require(rows.first { $0.line.id == line.id }).activity.last
      #expect(try detail(line, world).last == lines)
    }
    #expect(try detail(italian, world).last == .quiet(days: 28))
    #expect(try detail(calligraphy, world).last == .paused(last: W.date(2026, 7, 14)))
  }

  // MARK: Projects

  @Test func projectsAreTheLinesActiveAndOnHoldOnesInSourceOrder() throws {
    var world = W()
    let violin = world.line("violin")
    let piano = world.line("piano")
    world.project("Recital", line: .line(violin.id))
    world.project("Old études", line: .line(violin.id), status: .done)
    world.project("Bach", line: .line(violin.id), status: .onHold)
    world.project("Sonata", line: .line(piano.id))
    world.project("Quartet", line: .line(violin.id), status: .dropped)
    #expect(try detail(violin, world).projects.map(\.project.title) == ["Recital", "Bach"])
  }

  @Test func aProjectIsRepeatingOnlyWhenAnOpenTaskHasACompletedOccurrence() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    let daily = world.project("Daily technique", line: line)
    let scales = world.task("Scales", line: line, project: daily.id)
    world.task("Scales", line: line, completed: W.date(2026, 9, 29), occurrenceOf: scales.id)
    let recital = world.project("Recital", line: line)
    world.task("Book the hall", line: line, project: recital.id)
    world.task("Programme", line: line, project: recital.id, completed: W.date(2026, 9, 28))
    // A repeating task never completed in the store reads one-off: the stated limit.
    let etudes = world.project("Études", line: line)
    world.task("Étude 3", line: line, project: etudes.id)
    let kinds = try detail(violin, world).projects.map(\.kind)
    #expect(kinds == [.repeatingSessions, .oneOffTasks, .oneOffTasks])
  }

  @Test func nextActionsAndRemainingCountTheOpenLeavesWithSaturation() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    let recital = world.project("Recital", line: line)
    let group = world.task("Programme", line: line, project: recital.id, estimate: 500)
    world.task("Pick pieces", line: line, project: recital.id, parent: group.id, estimate: 30)
    world.task("Book the hall", line: line, project: recital.id, status: .blocked, estimate: 15)
    world.task("Zero", line: line, project: recital.id, estimate: 0)
    world.task("Negative", line: line, project: recital.id, estimate: -20)
    world.task("Done", line: line, project: recital.id, estimate: 40, completed: now)
    world.task("Dropped", line: line, project: recital.id, status: .dropped, estimate: 50)
    let huge = world.project("Huge", line: line)
    world.task("A", line: line, project: huge.id, estimate: .max - 1)
    world.task("B", line: line, project: huge.id, estimate: 5)
    let rows = try detail(violin, world).projects
    try #require(rows.count == 2)
    // Available leaves: Pick pieces, Zero, Negative; the group is a parent, Book is blocked.
    #expect(rows[0].nextActions == 3)
    #expect(rows[0].remainingMinutes == 45)
    #expect(rows[1].remainingMinutes == .max)
  }

  /// Owner, 2026-11-16: a project row counts only this line's own tasks, both ways.
  @Test func aProjectRowCountsOnlyTheLinesOwnTasks() throws {
    var world = W()
    let violin = world.line("violin")
    let piano = world.line("piano")
    let recital = world.project("Recital", line: .line(violin.id))
    world.task("Bow", line: .line(violin.id), project: recital.id, estimate: 20)
    let accompany = world.task(
      "Accompaniment", line: .line(piano.id), project: recital.id, estimate: 60)
    let scales = world.task("Scales", line: .line(piano.id), project: recital.id)
    world.task("Scales", line: .line(piano.id), completed: now, occurrenceOf: scales.id)
    let row = try #require(try detail(violin, world).projects.first)
    #expect(row.nextActions == 1)
    #expect(row.remainingMinutes == 20)
    #expect(row.kind == .oneOffTasks)
    // The piano task is piano's next action, under a project piano's table does not list.
    let pianoDetail = try detail(piano, world)
    #expect(pianoDetail.projects.isEmpty)
    #expect(pianoDetail.nextActions.map(\.task.id).contains(accompany.id))
    #expect(pianoDetail.nextActions.first?.project == recital)
  }

  // MARK: Next actions

  @Test func nextActionsAreTheLinesAvailableLeavesInSourceOrder() throws {
    var world = W()
    let violin = world.line("violin")
    let piano = world.line("piano")
    let line = LineAssignment.line(violin.id)
    world.task("First", line: line)
    let group = world.task("Group", line: line)
    world.task("Child", line: line, parent: group.id)
    world.task("Blocked", line: line, status: .blocked)
    world.task("Piano", line: .line(piano.id))
    world.task("Last", line: line)
    let titles = try detail(violin, world).nextActions.map(\.task.title)
    #expect(titles == ["First", "Child", "Last"])
  }

  @Test func placementIsPlannedThenDeferThenDueOnEffectiveDates() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    let friday = W.date(2026, 10, 2)
    let sunday = W.date(2026, 10, 4)
    let monday = W.date(2026, 10, 5)
    world.task("Planned", line: line, planned: friday, defer: sunday, due: monday)
    world.task("Deferred", line: line, defer: sunday, due: monday)
    world.task("Due", line: line, due: monday)
    world.task("Inherited", line: line, inheritedPlanned: friday)
    world.task("None", line: line)
    let placements = try detail(violin, world).nextActions.map(\.placement)
    #expect(placements == [friday, sunday, monday, friday, nil])
  }

  /// Today's rule, flags aside: an old defer date does not make a task today's.
  @Test func todayAndUrgentFollowTodaysRule() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    world.task("Planned earlier", line: line, planned: W.date(2026, 9, 27))
    world.task("Deferred to today", line: line, defer: W.date(2026, 9, 30, 8))
    world.task("Deferred long ago", line: line, defer: W.date(2026, 9, 27))
    world.task("Due tonight", line: line, due: W.date(2026, 9, 30, 23, 59))
    world.task("Due tomorrow", line: line, due: W.date(2026, 10, 1, 0, 0))
    world.task("Flagged", line: line, flagged: true)
    world.task("Planned Friday", line: line, planned: W.date(2026, 10, 2))
    let items = try detail(violin, world).nextActions
    #expect(items.map(\.isToday) == [true, true, false, true, false, false, false])
    #expect(items.map(\.isUrgent) == [false, false, false, true, false, false, false])
  }

  // MARK: Completions

  @Test func theLastTenCompletionsMostRecentFirst() throws {
    var world = W()
    let violin = world.line("violin")
    let piano = world.line("piano")
    let line = LineAssignment.line(violin.id)
    for day in 1...12 {
      world.task("Task \(day)", line: line, completed: W.date(2026, 9, day))
    }
    world.task("Piano", line: .line(piano.id), completed: W.date(2026, 9, 29))
    world.task("Open", line: line)
    let completions = try detail(violin, world).completions
    #expect(completions.count == Overview.completionsShown)
    #expect(completions.map(\.task.title) == (3...12).reversed().map { "Task \($0)" })
    #expect(completions.allSatisfy { $0.kind == .oneOff })
  }

  @Test func aClonedGroupIsOneSessionAtItsFirstCompletion() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    let live = world.task("Practice", line: line)
    let root = world.task(
      "Practice", line: line, completed: W.date(2026, 9, 29, 18), occurrenceOf: live.id)
    for (index, hour) in [17, 19, 20].enumerated() {
      let child = world.task("Step \(index)", line: line)
      world.task(
        "Step \(index)", line: line, parent: root.id, completed: W.date(2026, 9, 29, hour),
        occurrenceOf: child.id)
    }
    world.task("Programme", line: line, completed: W.date(2026, 9, 28))
    let completions = try detail(violin, world).completions
    try #require(completions.count == 2)
    #expect(completions[0].task.id == root.id)
    #expect(completions.map(\.kind) == [.session, .oneOff])
    #expect(completions[0].completedAt == W.date(2026, 9, 29, 17))
    #expect(completions[1].task.title == "Programme")
  }

  @Test func sameTimeCompletionsKeepSourceOrder() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    world.task("A", line: line, completed: W.date(2026, 9, 29))
    world.task("B", line: line, completed: W.date(2026, 9, 29))
    #expect(try detail(violin, world).completions.map(\.task.title) == ["A", "B"])
  }

  // MARK: Weeks

  @Test func weeksAndAverageAreTheLinesStats() throws {
    var world = W()
    let violin = world.line("violin")
    let line = LineAssignment.line(violin.id)
    for day in [7, 8, 14, 21, 22, 23, 29] {
      world.session("Scales", line: line, at: W.date(2026, 9, day))
    }
    world.task("Programme", line: line, completed: W.date(2026, 9, 16))
    let overview = Overview(workspace: world.workspace, now: now)
    let detail = try #require(overview.lineDetail(violin.id))
    let stats = overview.stats
    #expect(detail.weeks == stats.series(line, endingAt: stats.currentWeek, count: 8))
    #expect(detail.average == stats.average(line, before: stats.currentWeek))
    #expect(detail.average == WeekAverage(rhythm: 1.5, progress: 0.25))
  }

  // MARK: Parent

  @Test func theTargetIsTheTracesAndItsNoteIsFound() throws {
    var world = W()
    let violin = world.line("violin")
    let research = world.line("research", parent: "[[Corridor_2026-2030|Corridor]]")
    let solo = world.line("solo")
    let year = world.yearNote(2026)
    let recital = world.artifact("a26-02", lines: [violin.id], note: year.id)
    let corridor = world.note("00_Strategy/Years/Corridor_2026-2030.md")
    let violinDetail = try detail(violin, world)
    #expect(violinDetail.target == .artifact(recital))
    #expect(violinDetail.targetNote == year)
    let researchDetail = try detail(research, world)
    #expect(researchDetail.target == .note(corridor))
    #expect(researchDetail.targetNote == corridor)
    let soloDetail = try detail(solo, world)
    #expect(soloDetail.target == nil)
    #expect(soloDetail.targetNote == nil)
  }
}
