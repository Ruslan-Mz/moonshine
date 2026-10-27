import Foundation

@testable import MoonShineCore

/// Builds a `Workspace` by hand for service tests. Moscow time; invented data only.
struct TestWorld {
  static let timeZone = TimeZone(identifier: "Europe/Moscow")!
  static let calendar = Calendar.iso8601(in: timeZone)

  static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
  }

  var workspace = Workspace(timeZone: TestWorld.timeZone)

  @discardableResult
  mutating func line(
    _ key: LineKey, block: String = "Creative", state: LineState = .active,
    budget: Double? = nil, parent: String? = nil, emoji: String? = nil, foundation: Bool = false
  ) -> Line {
    let line = Line(
      id: .generate(), refs: [], key: key, name: key.rawValue.capitalized, emoji: emoji,
      block: block, state: state, budgetHoursPerWeek: budget, parentLink: parent,
      taskRules: LineTaskRules(), foundation: foundation)
    workspace.lines.append(line)
    return line
  }

  @discardableResult
  mutating func project(_ title: String, line: LineAssignment, tags: [TagID] = []) -> Project {
    let project = Project(
      id: .generate(), refs: [], title: title, status: .active, tagIDs: tags, line: line)
    workspace.projects.append(project)
    return project
  }

  @discardableResult
  mutating func task(
    _ title: String, line: LineAssignment, project: ProjectID? = nil,
    parent: TaskItemID? = nil, status: TaskItemStatus = .available, flagged: Bool = false,
    planned: Date? = nil, defer deferUntil: Date? = nil, due: Date? = nil,
    inheritedPlanned: Date? = nil, inheritedDefer: Date? = nil, inheritedDue: Date? = nil,
    estimate: Int? = nil, completed: Date? = nil, occurrenceOf: TaskItemID? = nil,
    tags: [TagID] = []
  ) -> TaskItem {
    let task = TaskItem(
      id: .generate(), refs: [], title: title, projectID: project, parentTaskID: parent,
      tagIDs: tags, status: completed == nil ? status : .completed, flagged: flagged,
      plannedAt: planned, deferUntil: deferUntil, dueAt: due,
      effectivePlannedAt: planned ?? inheritedPlanned,
      effectiveDeferUntil: deferUntil ?? inheritedDefer, effectiveDueAt: due ?? inheritedDue,
      estimateMinutes: estimate,
      completedAt: completed, modifiedAt: nil, occurrenceOf: occurrenceOf, line: line)
    workspace.tasks.append(task)
    return task
  }

  /// A completed occurrence of a fresh live repeating task.
  @discardableResult
  mutating func session(
    _ title: String, line: LineAssignment, at date: Date, parent: TaskItemID? = nil
  ) -> TaskItem {
    let live = task(title, line: line)
    return task(title, line: line, parent: parent, completed: date, occurrenceOf: live.id)
  }

  @discardableResult
  mutating func tag(_ name: String, parent: TagID? = nil) -> Tag {
    let tag = Tag(id: .generate(), refs: [], name: name, parentID: parent, isMeta: false)
    workspace.tags.append(tag)
    return tag
  }

  @discardableResult
  mutating func note(
    _ path: String, type: String? = nil, scale: Scale? = nil, period: Horizon? = nil
  ) -> NoteRef {
    let note = NoteRef(
      id: .generate(), refs: [], path: path, title: path, type: type, scale: scale,
      period: period, parentLink: nil, lineKey: nil, status: nil)
    workspace.notes.append(note)
    return note
  }

  @discardableResult
  mutating func yearNote(_ year: Int) -> NoteRef {
    note(
      "Years/Artifacts_\(year).md", type: "year_artifacts", scale: .year,
      period: Horizon.containing(
        TestWorld.date(year, 6, 1), scale: .year, calendar: TestWorld.calendar))
  }

  @discardableResult
  mutating func artifact(
    _ key: String, lines: [LineID], status: ArtifactStatus = .inProgress,
    priority: Bool = false, note: NoteID?
  ) -> Artifact {
    let artifact = Artifact(
      id: .generate(), refs: [], key: key, title: key, lineIDs: lines, status: status,
      priority: priority, noteID: note)
    workspace.artifacts.append(artifact)
    return artifact
  }
}
