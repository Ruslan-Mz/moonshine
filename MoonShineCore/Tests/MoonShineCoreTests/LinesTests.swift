import Foundation
import Testing

@testable import MoonShineCore

@Suite struct LinesTests {
  typealias W = TestWorld
  /// Wednesday of ISO week 40.
  let now = W.date(2026, 9, 30)

  func rows(_ world: W, at now: Date? = nil) -> [LineRow] {
    Overview(workspace: world.workspace, now: now ?? self.now).lines().tiers.flatMap(\.rows)
  }

  func activity(_ key: LineKey, _ world: W, at now: Date? = nil) throws -> LineActivity {
    try #require(rows(world, at: now).first { $0.line.key == key }).activity
  }

  // MARK: Tiers

  @Test func tiersFoundationActiveMaintenancePausedWithVaultOrderInside() {
    var world = W()
    world.line("calligraphy", state: .paused)
    world.line("italian", block: "Languages")
    world.line("core", block: "Foundation", foundation: true)
    world.line("piano", state: .maintenance)
    world.line("violin")
    world.line("pullups", block: "Foundation", foundation: true)
    let tiers = Overview(workspace: world.workspace, now: now).lines().tiers
    #expect(tiers.map(\.kind) == [.foundation, .active, .maintenance, .paused])
    #expect(
      tiers.map { $0.rows.map(\.line.key.rawValue) } == [
        ["core", "pullups"], ["italian", "violin"], ["piano"], ["calligraphy"],
      ])
  }

  @Test func emptyTiersAreLeftOutAndAPausedFoundationLineIsPaused() {
    var world = W()
    world.line("core", state: .paused, foundation: true)
    world.line("violin")
    let tiers = Overview(workspace: world.workspace, now: now).lines().tiers
    #expect(tiers.map(\.kind) == [.active, .paused])
    #expect(tiers.last?.rows.map(\.line.key.rawValue) == ["core"])
  }

  @Test func tierSumsBudgetsAndOnlyFoundationFloors() {
    var world = W()
    world.line("core", foundation: true, floor: 3)
    world.line("pullups", foundation: true, floor: 1)
    world.line("violin", budget: 6, floor: 0.5)
    world.line("math", budget: 4)
    world.line("family")
    world.line("piano", state: .maintenance)
    world.line("chess", state: .paused, budget: 0)
    let tiers = Overview(workspace: world.workspace, now: now).lines().tiers
    let byKind = Dictionary(uniqueKeysWithValues: tiers.map { ($0.kind, $0) })
    #expect(byKind[.foundation]?.dailyFloorHours == 4)
    #expect(byKind[.foundation]?.weeklyBudgetHours == nil)
    #expect(byKind[.active]?.weeklyBudgetHours == 10)
    #expect(byKind[.active]?.dailyFloorHours == nil)
    #expect(byKind[.maintenance]?.weeklyBudgetHours == nil)
    // An owner-set 0 is a budget.
    #expect(byKind[.paused]?.weeklyBudgetHours == 0)
  }

  @Test func countsFollowTheTiers() {
    var world = W()
    world.line("core", foundation: true)
    world.line("pullups", foundation: true)
    world.line("violin")
    world.line("piano", state: .maintenance)
    world.line("calligraphy", state: .paused)
    world.line("chess", state: .paused, foundation: true)
    let counts = Overview(workspace: world.workspace, now: now).lines().counts
    #expect(
      counts == LineCounts(lines: 6, foundation: 2, active: 1, maintenance: 1, paused: 2))
  }

  @Test func sparklineIsEightWeeksEndingWithTheCurrentPartialWeek() throws {
    var world = W()
    let violin = world.line("violin")
    world.task("Etude", line: .line(violin.id), completed: W.date(2026, 9, 15))  // W38
    let sparkline = try activity("violin", world).sparkline
    #expect(sparkline.count == 8)
    #expect(sparkline.first?.week == ISOWeek(year: 2026, week: 33))
    #expect(sparkline.last?.week == ISOWeek(year: 2026, week: 40))
    #expect(sparkline.map(\.isPartial) == [false, false, false, false, false, false, false, true])
    #expect(sparkline.map(\.counts.progress) == [0, 0, 0, 0, 0, 1, 0, 0])
  }

  @Test func nextActionsCountAvailableLeavesNotTheirGroups() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let group = world.task("Partita", line: violin)
    world.task("Bars 1–16", line: violin, parent: group.id)
    world.task("Bars 17–32", line: violin, parent: group.id)
    let finished = world.task("Rosin", line: violin)
    world.task("Buy rosin", line: violin, parent: finished.id, completed: W.date(2026, 9, 20))
    world.task("Blocked", line: violin, status: .blocked)
    world.task("Done", line: violin, completed: W.date(2026, 9, 29))
    // Bars 1–16, Bars 17–32, and Rosin (its only child is done).
    #expect(try activity("violin", world).nextActions == 3)
  }

  // MARK: Last activity

  @Test(arguments: [
    (W.date(2026, 9, 30, 9), LastActivity.today),
    // Later than now on the same day, and a day later (a clock set back): today, never -1.
    (W.date(2026, 9, 30, 23), .today),
    (W.date(2026, 10, 1, 10), .today),
    (W.date(2026, 9, 29, 23, 59), .yesterday),
    (W.date(2026, 9, 28), .daysAgo(2)),
    (W.date(2026, 9, 17), .daysAgo(13)),
    (W.date(2026, 9, 16), .quiet(days: 14)),
  ])
  func lastActivityOfAnActiveLine(completed: Date, expected: LastActivity) throws {
    var world = W()
    let violin = world.line("violin")
    world.task("Etude", line: .line(violin.id), completed: completed)
    #expect(try activity("violin", world).last == expected)
  }

  /// Just after midnight in the workspace zone (Moscow, UTC+3), when UTC still has the
  /// previous day: the day count follows the zone.
  @Test(arguments: [
    (W.date(2026, 9, 30, 0, 10), LastActivity.today),
    (W.date(2026, 9, 29, 23, 50), .yesterday),
    (W.date(2026, 9, 28, 23, 30), .daysAgo(2)),
  ])
  func lastActivityJustAfterMidnightInTheZone(completed: Date, expected: LastActivity) throws {
    var world = W()
    let violin = world.line("violin")
    world.task("Etude", line: .line(violin.id), completed: completed)
    #expect(try activity("violin", world, at: W.date(2026, 9, 30, 0, 30)).last == expected)
  }

  @Test func maintenanceAndFoundationLinesAreNeverQuiet() throws {
    var world = W()
    let piano = world.line("piano", state: .maintenance)
    let core = world.line("core", foundation: true)
    world.task("Scales", line: .line(piano.id), completed: W.date(2026, 9, 1))
    world.task("Sit", line: .line(core.id), completed: W.date(2026, 9, 1))
    #expect(try activity("piano", world).last == .daysAgo(29))
    #expect(try activity("core", world).last == .daysAgo(29))
  }

  @Test func noCompletionsNamesTheWindowStartWhenKnown() throws {
    var world = W()
    world.line("japanese")
    world.line("core", foundation: true)
    #expect(try activity("japanese", world).last == .noCompletions(since: nil))
    let since = W.date(2026, 7, 6, 0)
    world.workspace.completedSince = since
    #expect(try activity("japanese", world).last == .noCompletions(since: since))
    #expect(try activity("core", world).last == .noCompletions(since: since))
  }

  @Test func aPausedLineShowsItsLastCompletionOrNone() throws {
    var world = W()
    let calligraphy = world.line("calligraphy", state: .paused)
    world.line("chess", state: .paused)
    world.workspace.completedSince = W.date(2026, 7, 6, 0)
    world.task("Strokes", line: .line(calligraphy.id), completed: W.date(2026, 7, 14))
    #expect(try activity("calligraphy", world).last == .paused(last: W.date(2026, 7, 14)))
    #expect(try activity("chess", world).last == .paused(last: nil))
  }

  /// Today and Lines read one rule, so a line is quiet on both or on neither.
  @Test func todaysQuietLinesAreQuietOnLines() {
    var world = W()
    world.workspace.completedSince = W.date(2026, 7, 6, 0)
    let lines = [
      world.line("violin"), world.line("italian"), world.line("japanese"),
      world.line("core", foundation: true), world.line("piano", state: .maintenance),
      world.line("chess", state: .paused),
    ]
    let september1 = W.date(2026, 9, 1)
    let completed = [W.date(2026, 9, 29), september1, nil, september1, september1, september1]
    for (line, date) in zip(lines, completed) {
      if let date { world.task("Done", line: .line(line.id), completed: date) }
    }
    let overview = Overview(workspace: world.workspace, now: now)
    let today = overview.today().quietLines
    var quietOnToday: Set<LineKey> = []
    var noneOnToday: Set<LineKey> = []
    for quiet in today {
      switch quiet.reason {
      case .quiet: quietOnToday.insert(quiet.line.key)
      case .noActivity: noneOnToday.insert(quiet.line.key)
      }
    }
    let rows = overview.lines().tiers.flatMap(\.rows)
    let quietOnLines = Set(
      rows.filter { if case .quiet = $0.activity.last { true } else { false } }.map(\.line.key))
    let activeNone = Set(
      rows.filter {
        guard $0.line.state == .active, case .noCompletions = $0.activity.last else { return false }
        return true
      }.map(\.line.key))
    #expect(quietOnToday == ["italian"])
    #expect(quietOnLines == quietOnToday)
    #expect(noneOnToday == ["japanese"])
    #expect(activeNone == noneOnToday)
  }

  // MARK: Estimated this week

  /// Thursday of week 40, 12:00 in the workspace zone (Moscow).
  let thursday = W.date(2026, 10, 1)

  @Test func estimatedThisWeekCountsTasksPlacedInTheCurrentWeek() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Planned Friday", line: violin, planned: W.date(2026, 10, 2), estimate: 30)
    world.task("Due Sunday", line: violin, due: W.date(2026, 10, 4, 18), estimate: 20)
    world.task("Planned today", line: violin, planned: W.date(2026, 10, 1, 9), estimate: 10)
    // OmniFocus blocks a task deferred to a later day: it still counts this week.
    world.task(
      "Deferred to Saturday", line: violin, status: .blocked, defer: W.date(2026, 10, 3, 9),
      estimate: 15)
    // Deferred with its action group or project: inherited, it counts the same.
    world.task(
      "Group deferred", line: violin, status: .blocked, inheritedDefer: W.date(2026, 10, 3, 9),
      estimate: 5)
    // Effective planned and due dates count as the task's own.
    world.task(
      "Inherits planned", line: violin, inheritedPlanned: W.date(2026, 10, 2), estimate: 100)
    world.task("Inherits due", line: violin, inheritedDue: W.date(2026, 10, 3), estimate: 200)
    // Planned first: planned this week and due next week counts.
    world.task(
      "Planned Friday, due next week", line: violin, planned: W.date(2026, 10, 2),
      due: W.date(2026, 10, 7), estimate: 400)
    // A group whose only child is done is a leaf among the open tasks.
    let group = world.task("Group", line: violin, planned: W.date(2026, 10, 2), estimate: 800)
    world.task("Its done child", line: violin, parent: group.id, completed: W.date(2026, 9, 29))
    #expect(try activity("violin", world, at: thursday).estimatedThisWeekMinutes == 1580)
  }

  @Test func estimatedThisWeekLeavesOutWhatIsNotPlacedThisWeek() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    // Blocked without a future defer date: a sequential project's later task.
    world.task(
      "Sequential, planned Friday", line: violin, status: .blocked,
      planned: W.date(2026, 10, 2), estimate: 40)
    world.task(
      "Sequential, deferred earlier", line: violin, status: .blocked,
      defer: W.date(2026, 9, 29), estimate: 40)
    world.task("Planned last week", line: violin, planned: W.date(2026, 9, 25), estimate: 40)
    world.task("Planned next week", line: violin, planned: W.date(2026, 10, 6), estimate: 40)
    // Planned first: planned next week and due this week does not count; nor does a task
    // deferred to before this week and due in it.
    world.task(
      "Planned next week, due Sunday", line: violin, planned: W.date(2026, 10, 6),
      due: W.date(2026, 10, 4), estimate: 40)
    world.task(
      "Deferred last week, due Sunday", line: violin, defer: W.date(2026, 9, 25),
      due: W.date(2026, 10, 4), estimate: 40)
    world.task("No date", line: violin, estimate: 40)
    world.task("Zero", line: violin, planned: W.date(2026, 10, 2), estimate: 0)
    world.task("Negative", line: violin, planned: W.date(2026, 10, 2), estimate: -5)
    world.task("Unestimated", line: violin, planned: W.date(2026, 10, 2))
    let group = world.task("Group", line: violin, planned: W.date(2026, 10, 2), estimate: 40)
    world.task("Child", line: violin, parent: group.id, planned: W.date(2026, 10, 2), estimate: 7)
    world.task(
      "Done", line: violin, planned: W.date(2026, 10, 2), estimate: 40,
      completed: W.date(2026, 10, 1, 9))
    #expect(try activity("violin", world, at: thursday).estimatedThisWeekMinutes == 7)
  }

  /// An on-hold project's work is paused on purpose (owner, 2026-11-13): none of its tasks
  /// counts; the same task in an active project does.
  @Test func estimatedThisWeekLeavesOutOnHoldProjects() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let held = world.project("Held", line: violin, status: .onHold)
    let active = world.project("Active", line: violin)
    for project in [held, active] {
      world.task(
        "Deferred to Saturday", line: violin, project: project.id, status: .blocked,
        defer: W.date(2026, 10, 3, 9), estimate: 15)
      world.task(
        "Planned Friday", line: violin, project: project.id, planned: W.date(2026, 10, 2),
        estimate: 30)
    }
    #expect(try activity("violin", world, at: thursday).estimatedThisWeekMinutes == 45)
  }

  @Test func theWeekRunsFromMondayMidnightToTheNextInTheWorkspaceZone() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Monday 00:00", line: violin, planned: W.date(2026, 9, 28, 0), estimate: 1)
    world.task("Sunday 23:59", line: violin, planned: W.date(2026, 10, 4, 23, 59), estimate: 2)
    world.task("Next Monday 00:00", line: violin, planned: W.date(2026, 10, 5, 0), estimate: 4)
    world.task("Sunday before", line: violin, planned: W.date(2026, 9, 27, 23, 59), estimate: 8)
    #expect(try activity("violin", world, at: thursday).estimatedThisWeekMinutes == 3)
  }

  @Test func estimatedThisWeekSaturates() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("A", line: violin, planned: W.date(2026, 10, 2), estimate: .max - 1)
    world.task("B", line: violin, planned: W.date(2026, 10, 2), estimate: 2)
    #expect(try activity("violin", world, at: thursday).estimatedThisWeekMinutes == .max)
  }

  @Test func lifeOpsHasItsOwnActivityOutsideTheTiers() {
    var world = W()
    world.line("violin")
    world.task("Pay rent", line: .lifeOps, planned: W.date(2026, 9, 30), estimate: 10)
    world.session("Dishes", line: .lifeOps, at: W.date(2026, 9, 29))
    let lines = Overview(workspace: world.workspace, now: now).lines()
    #expect(lines.tiers.flatMap(\.rows).count == 1)
    #expect(lines.lifeOps.nextActions == 2)  // Pay rent + the live Dishes task
    #expect(lines.lifeOps.estimatedThisWeekMinutes == 10)
    #expect(lines.lifeOps.sparkline.last?.counts == WeekCounts(rhythm: 1))
    #expect(lines.lifeOps.last == .yesterday)
  }
}
