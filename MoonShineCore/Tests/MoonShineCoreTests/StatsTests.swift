import Foundation
import Testing

@testable import MoonShineCore

@Suite struct StatsTests {
  typealias W = TestWorld
  // Wednesday of ISO week 2026-W40.
  let now = W.date(2026, 9, 30)
  let w40 = ISOWeek(year: 2026, week: 40)
  let w39 = ISOWeek(year: 2026, week: 39)

  @Test func repeatOccurrencesAreRhythmAndOneOffsAreProgress() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.session("Scales", line: violin, at: W.date(2026, 9, 28))
    world.session("Scales", line: violin, at: W.date(2026, 9, 29))
    world.task("Book a lesson", line: violin, completed: W.date(2026, 9, 29))
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.counts(violin, in: w40) == WeekCounts(rhythm: 2, progress: 1))
  }

  @Test func weekBoundaryFollowsTheWorkspaceTimeZone() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    // Sunday 23:30 Moscow = 20:30 UTC Sunday; Monday 00:10 Moscow = 21:10 UTC Sunday.
    world.task("Sunday late", line: violin, completed: W.date(2026, 9, 27, 23, 30))
    world.task("Monday early", line: violin, completed: W.date(2026, 9, 28, 0, 10))
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.counts(violin, in: w39) == WeekCounts(progress: 1))
    #expect(stats.counts(violin, in: w40) == WeekCounts(progress: 1))
  }

  @Test func clonedGroupIsOneSessionPerLine() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let walk = LineAssignment.line(world.line("walk").id)
    let at = W.date(2026, 9, 29, 8)
    // "Morning anchors" (walk) cloned with two violin children and one walk child.
    let group = world.session("Morning anchors", line: walk, at: at)
    world.session("Open strings", line: violin, at: at, parent: group.id)
    world.session("Scales", line: violin, at: at, parent: group.id)
    world.session("Walk 20 min", line: walk, at: at, parent: group.id)
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.counts(walk, in: w40) == WeekCounts(rhythm: 1))
    #expect(stats.counts(violin, in: w40) == WeekCounts(rhythm: 1))
  }

  @Test func onlyCompletedTasksWithADateCount() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Open", line: violin)
    world.task("Dropped", line: violin, status: .dropped)
    world.task("Completed, no date", line: violin, status: .completed)
    world.task("Done", line: violin, completed: W.date(2026, 9, 29))
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.counts(violin, in: w40) == WeekCounts(progress: 1))
  }

  @Test func dayCountsIncludeTheDayStartAndExcludeItsEnd() throws {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("At midnight", line: violin, completed: W.date(2026, 9, 30, 0))
    world.task("Next midnight", line: violin, completed: W.date(2026, 10, 1, 0))
    world.session("Scales", line: violin, at: W.date(2026, 9, 30, 23, 59))
    let stats = Stats(workspace: world.workspace, now: now)
    let day = try #require(Horizon.containing(now, scale: .day, calendar: W.calendar))
    #expect(stats.counts(violin, in: day) == WeekCounts(rhythm: 1, progress: 1))
  }

  @Test func lifeOpsIsItsOwnBucket() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Pay rent", line: .lifeOps, completed: W.date(2026, 9, 29))
    world.session("Dishes", line: .lifeOps, at: W.date(2026, 9, 29))
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.counts(.lifeOps, in: w40) == WeekCounts(rhythm: 1, progress: 1))
    #expect(stats.counts(violin, in: w40) == .zero)
  }

  @Test func seriesIsZeroFilledAcrossTheISOYearAndMarksTheCurrentWeekPartial() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Late December", line: violin, completed: W.date(2026, 12, 30))
    world.session("Scales", line: violin, at: W.date(2027, 1, 5))
    let stats = Stats(workspace: world.workspace, now: W.date(2027, 1, 6))
    let series = stats.series(violin, endingAt: ISOWeek(year: 2027, week: 1), count: 3)
    #expect(series.map(\.week.description) == ["2026-W52", "2026-W53", "2027-W01"])
    #expect(series.map(\.counts) == [.zero, WeekCounts(progress: 1), WeekCounts(rhythm: 1)])
    #expect(series.map(\.isPartial) == [false, false, true])
  }

  @Test func averageCoversTheFourWeeksBeforeAndExcludesTheCurrentWeek() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.session("Scales", line: violin, at: W.date(2026, 9, 1))  // W36
    world.session("Scales", line: violin, at: W.date(2026, 9, 8))  // W37
    world.session("Scales", line: violin, at: W.date(2026, 9, 9))  // W37
    world.task("Rosin", line: violin, completed: W.date(2026, 9, 22))  // W39
    world.task("Strings", line: violin, completed: W.date(2026, 8, 25))  // W35, outside
    world.task("Today", line: violin, completed: W.date(2026, 9, 30))  // W40, current
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.average(violin, before: w40) == WeekAverage(rhythm: 0.75, progress: 0.25))
  }

  @Test func lastCompletionPerLine() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let piano = LineAssignment.line(world.line("piano").id)
    world.task("A", line: violin, completed: W.date(2026, 9, 2))
    world.session("B", line: violin, at: W.date(2026, 9, 20))
    world.task("C", line: violin, completed: W.date(2026, 9, 10))
    let stats = Stats(workspace: world.workspace, now: now)
    #expect(stats.lastCompletion(violin) == W.date(2026, 9, 20))
    #expect(stats.lastCompletion(piano) == nil)
  }
}
