import Foundation
import Testing

@testable import MoonShineCore

@Suite struct StoredWorkspaceTests {
  let first = TestWorld.date(2026, 9, 1)
  let second = TestWorld.date(2026, 9, 8)
  let third = TestWorld.date(2026, 9, 15)

  func empty() -> StoredWorkspace { StoredWorkspace(timeZone: TestWorld.timeZone) }

  func without(_ task: TaskItem, in workspace: Workspace) -> Workspace {
    var copy = workspace
    copy.tasks.removeAll { $0.id == task.id }
    return copy
  }

  @Test func firstImportKeepsEverythingInImportOrder() {
    var world = TestWorld()
    let line = world.line("violin")
    world.project("Technique", line: .line(line.id))
    world.task("Scales", line: .line(line.id))
    world.task("Etude", line: .lifeOps, completed: first)
    world.note("Years/Artifacts_2026.md")

    let stored = empty().merging(world.workspace, at: first)

    #expect(stored.tasks.allSatisfy { !$0.isRemoved })
    #expect(stored.workspace.tasks == world.workspace.tasks)
    #expect(stored.workspace.lines == world.workspace.lines)
    #expect(stored.workspace.projects == world.workspace.projects)
    #expect(stored.workspace.notes == world.workspace.notes)
  }

  @Test func completedTaskMissingFromTheNextImportStaysInHistory() {
    var world = TestWorld()
    let done = world.task("Etude", line: .lifeOps, completed: first)
    world.task("Scales", line: .lifeOps)

    let stored = empty().merging(world.workspace, at: first)
      .merging(without(done, in: world.workspace), at: second)

    #expect(stored.tasks.first { $0.entity.id == done.id }?.removedAt == nil)
    #expect(stored.workspace.tasks.map(\.id).contains(done.id))
  }

  @Test func openTaskMissingFromTheNextImportIsSoftDeleted() {
    var world = TestWorld()
    let open = world.task("Scales", line: .lifeOps)
    world.task("Etude", line: .lifeOps)

    let stored = empty().merging(world.workspace, at: first)
      .merging(without(open, in: world.workspace), at: second)

    #expect(stored.tasks.first { $0.entity.id == open.id }?.removedAt == second)
    #expect(!stored.workspace.tasks.map(\.id).contains(open.id))
    #expect(stored.workspace.tasks.count == 1)
  }

  @Test func staysRemovedSinceTheFirstImportItWentMissingFrom() {
    var world = TestWorld()
    let open = world.task("Scales", line: .lifeOps)

    let stored = empty().merging(world.workspace, at: first)
      .merging(without(open, in: world.workspace), at: second)
      .merging(without(open, in: world.workspace), at: third)

    #expect(stored.tasks.first { $0.entity.id == open.id }?.removedAt == second)
  }

  @Test func removedTaskThatReappearsIsRestoredWithItsIDAndImportPosition() {
    var world = TestWorld()
    let open = world.task("Scales", line: .lifeOps)
    world.task("Etude", line: .lifeOps)

    let stored = empty().merging(world.workspace, at: first)
      .merging(without(open, in: world.workspace), at: second)
      .merging(world.workspace, at: third)

    #expect(stored.tasks.allSatisfy { !$0.isRemoved })
    #expect(stored.workspace.tasks.map(\.id) == world.workspace.tasks.map(\.id))
  }

  @Test func everyOtherKindMissingFromTheNextImportIsSoftDeleted() {
    var world = TestWorld()
    let line = world.line("violin")
    let note = world.yearNote(2026)
    world.artifact("a26-01", lines: [line.id], note: note.id)
    world.project("Technique", line: .line(line.id))
    world.workspace.tags = [
      Tag(id: .generate(), refs: [], name: "violin", parentID: nil, isMeta: false)
    ]

    let stored = empty().merging(world.workspace, at: first)
      .merging(Workspace(timeZone: TestWorld.timeZone), at: second)

    #expect(stored.lines.map(\.removedAt) == [second])
    #expect(stored.notes.map(\.removedAt) == [second])
    #expect(stored.artifacts.map(\.removedAt) == [second])
    #expect(stored.projects.map(\.removedAt) == [second])
    #expect(stored.tags.map(\.removedAt) == [second])
    let visible = stored.workspace
    #expect(visible.lines.isEmpty && visible.notes.isEmpty && visible.artifacts.isEmpty)
    #expect(visible.projects.isEmpty && visible.tags.isEmpty)
  }

  @Test func incomingReplacesFieldsTimeZoneAndIssuesAndRetainedFollowInStoredOrder() {
    var world = TestWorld()
    let a = world.task("A", line: .lifeOps, completed: first)
    let b = world.task("B", line: .lifeOps, completed: first)
    let c = world.task("C", line: .lifeOps)
    let stored = empty().merging(world.workspace, at: first)

    let renamed = TaskItem(
      id: c.id, refs: c.refs, title: "C2", projectID: nil, parentTaskID: nil, tagIDs: [],
      status: .completed, flagged: false, plannedAt: nil, deferUntil: nil, dueAt: nil,
      estimateMinutes: nil, completedAt: second, modifiedAt: second, occurrenceOf: nil,
      line: .lifeOps)
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let next = stored.merging(
      Workspace(
        timeZone: tokyo, tasks: [renamed], issues: [.unknownLineKey("cello", in: "a26-09")]),
      at: second)

    #expect(next.workspace.tasks.map(\.id) == [c.id, a.id, b.id])
    #expect(next.workspace.tasks.first?.title == "C2")
    #expect(next.timeZone == tokyo)
    #expect(next.issues == [.unknownLineKey("cello", in: "a26-09")])
  }
}
