import Foundation
import Testing

@testable import MoonShineCore

@Suite struct LinesTests {
  typealias W = TestWorld
  let now = W.date(2026, 9, 30)

  @Test func blocksInVaultOrderAndRowsActiveThenMaintenanceThenPaused() {
    var world = W()
    world.line("calligraphy", block: "Creative", state: .paused)
    world.line("italian", block: "Languages")
    world.line("violin", block: "Creative")
    world.line("piano", block: "Creative", state: .maintenance)
    world.line("guitar", block: "Creative")
    let blocks = Overview(workspace: world.workspace, now: now).lines().blocks
    #expect(blocks.map(\.name) == ["Creative", "Languages"])
    #expect(
      blocks.first?.rows.map(\.line.key.rawValue) == ["violin", "guitar", "piano", "calligraphy"])
  }

  @Test func sparklineIsEightWeeksEndingWithTheCurrentPartialWeek() throws {
    var world = W()
    let violin = world.line("violin")
    world.task("Etude", line: .line(violin.id), completed: W.date(2026, 9, 15))  // W38
    let row = try #require(
      Overview(workspace: world.workspace, now: now).lines().blocks.first?.rows.first)
    let sparkline = row.activity.sparkline
    #expect(sparkline.count == 8)
    #expect(sparkline.first?.week == ISOWeek(year: 2026, week: 33))
    #expect(sparkline.last?.week == ISOWeek(year: 2026, week: 40))
    #expect(sparkline.map(\.isPartial) == [false, false, false, false, false, false, false, true])
    #expect(sparkline.map(\.counts.progress) == [0, 0, 0, 0, 0, 1, 0, 0])
    #expect(row.activity.lastActivity == W.date(2026, 9, 15))
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
    let row = try #require(
      Overview(workspace: world.workspace, now: now).lines().blocks.first?.rows.first)
    // Bars 1–16, Bars 17–32, and Rosin (its only child is done).
    #expect(row.activity.nextActions == 3)
  }

  @Test func plannedEffortSumsEstimatesAndCountsHowManyHaveOne() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("A", line: violin, estimate: 30)
    world.task("B", line: violin, estimate: 45)
    world.task("C", line: violin)
    world.task("Done", line: violin, estimate: 60, completed: W.date(2026, 9, 29))
    let activity = try #require(
      Overview(workspace: world.workspace, now: now).lines().blocks.first?.rows.first?.activity)
    #expect(activity.nextActions == 3)
    #expect(activity.estimatedMinutes == 75)
    #expect(activity.estimatedTasks == 2)
  }

  @Test func lifeOpsHasItsOwnActivityOutsideTheBlocks() {
    var world = W()
    world.line("violin")
    world.task("Pay rent", line: .lifeOps, estimate: 10)
    world.session("Dishes", line: .lifeOps, at: W.date(2026, 9, 29))
    let lines = Overview(workspace: world.workspace, now: now).lines()
    #expect(lines.blocks.flatMap(\.rows).count == 1)
    #expect(lines.lifeOps.nextActions == 2)  // Pay rent + the live Dishes task
    #expect(lines.lifeOps.estimatedMinutes == 10)
    #expect(lines.lifeOps.sparkline.last?.counts == WeekCounts(rhythm: 1))
    #expect(lines.lifeOps.lastActivity == W.date(2026, 9, 29))
  }
}
