import Foundation
import Testing

@testable import MoonShineCore

@Suite struct TraceTests {
  typealias W = TestWorld
  let now = W.date(2026, 9, 30)

  @Test func fullChainEndsAtThePriorityArtifactOfTheCurrentYear() {
    var world = W()
    let violin = world.line("violin")
    let year = world.yearNote(2026)
    world.artifact("a26-07", lines: [violin.id], note: year.id)
    let partita = world.artifact("a26-02", lines: [violin.id], priority: true, note: year.id)
    let project = world.project("Partita", line: .line(violin.id))
    let task = world.task("Bars 1–16", line: .line(violin.id), project: project.id)
    let trace = Tracer(workspace: world.workspace, now: now).trace(task)
    #expect(trace.taskID == task.id)
    #expect(trace.project == project)
    #expect(trace.line == .line(violin.id))
    #expect(trace.lineEntity == violin)
    #expect(trace.target == .artifact(partita))
  }

  @Test func openArtifactBeatsADoneOneAndADroppedOneIsNeverChosen() {
    var world = W()
    let violin = world.line("violin")
    let piano = world.line("piano")
    let year = world.yearNote(2026)
    world.artifact("done", lines: [violin.id], status: .done, priority: true, note: year.id)
    let planned = world.artifact("planned", lines: [violin.id], status: .planned, note: year.id)
    world.artifact("dropped", lines: [piano.id], status: .dropped, priority: true, note: year.id)
    let tracer = Tracer(workspace: world.workspace, now: now)
    #expect(tracer.trace(world.task("A", line: .line(violin.id))).target == .artifact(planned))
    #expect(tracer.trace(world.task("B", line: .line(piano.id))).target == nil)
  }

  @Test func artifactsOfAnotherYearAreIgnored() {
    var world = W()
    let violin = world.line("violin")
    let lastYear = world.yearNote(2025)
    world.artifact("a25-01", lines: [violin.id], note: lastYear.id)
    let task = world.task("A", line: .line(violin.id))
    #expect(Tracer(workspace: world.workspace, now: now).trace(task).target == nil)
  }

  @Test func withoutAnArtifactTheParentNoteIsFoundByWikiLink() {
    var world = W()
    let research = world.line("research", parent: "[[Corridor_2026-2030|Corridor]]")
    let corridor = world.note("00_Strategy/Years/Corridor_2026-2030.md")
    let task = world.task("Read paper", line: .line(research.id))
    #expect(
      Tracer(workspace: world.workspace, now: now).trace(task).target == .note(corridor))
  }

  /// Resolved by `WikiLink`, not by file name only: a qualified link, the shortest path.
  @Test func aPathQualifiedParentEndsAtTheShortestMatchingNote() {
    var world = W()
    let research = world.line("research", parent: "[[Years/Plan]]")
    world.note("Archive/Years/Plan.md")
    let plan = world.note("Years/Plan.md")
    world.note("Plan.md")
    let task = world.task("Read paper", line: .line(research.id))
    #expect(Tracer(workspace: world.workspace, now: now).trace(task).target == .note(plan))
  }

  @Test func withNeitherTheTraceEndsAtTheLine() {
    var world = W()
    let math = world.line("math", parent: "[[Missing note]]")
    let task = world.task("Exercise 3", line: .line(math.id))
    let trace = Tracer(workspace: world.workspace, now: now).trace(task)
    #expect(trace.lineEntity == math)
    #expect(trace.target == nil)
  }

  @Test func lifeOpsTaskEndsAtLifeOps() {
    var world = W()
    world.line("violin")
    let project = world.project("Household", line: .lifeOps)
    let task = world.task("Pay rent", line: .lifeOps, project: project.id)
    let trace = Tracer(workspace: world.workspace, now: now).trace(task)
    #expect(trace.project == project)
    #expect(trace.line == .lifeOps)
    #expect(trace.lineEntity == nil)
    #expect(trace.target == nil)
  }

  @Test func taskWithoutAProjectTracesStraightToItsLine() {
    var world = W()
    let violin = world.line("violin")
    let year = world.yearNote(2026)
    let artifact = world.artifact("a26-02", lines: [violin.id], note: year.id)
    let task = world.task("Rosin", line: .line(violin.id))
    let trace = Tracer(workspace: world.workspace, now: now).trace(task)
    #expect(trace.project == nil)
    #expect(trace.lineEntity == violin)
    #expect(trace.target == .artifact(artifact))
  }
}
