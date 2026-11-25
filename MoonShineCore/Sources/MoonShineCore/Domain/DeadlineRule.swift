import Foundation

/// Which due dates are deadlines, the only ones that may use the urgent colour
/// (`docs/specs/phase-1-see.md` § Deadline rule; `design/screens/settings.md` § Deadlines).
public struct DeadlineRule: Hashable, Sendable {
  /// The raw values are stored (`deadlineMode`): explicit, so a renamed case keeps reading them.
  public enum Mode: String, Hashable, Sendable {
    case allDueDates = "allDueDates"
    case dueDateAndTag = "dueDateAndTag"
  }

  public static let defaultTag = "deadline"
  /// The spec's default: every due date is a deadline.
  public static let allDueDates = DeadlineRule(mode: .allDueDates, tag: defaultTag)

  public let mode: Mode
  /// Trimmed; an empty or blank value reverts to `deadline`. Kept in both modes, so switching
  /// back to the tag keeps its name.
  public let tag: String

  public init(mode: Mode, tag: String) {
    self.mode = mode
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    self.tag = trimmed.isEmpty ? Self.defaultTag : trimmed
  }

  /// Nil when every due date counts; otherwise the tasks that carry the tag themselves, on a
  /// parent task or on their project, matched by leaf name (`Tag.matchesLeafName`). The walk up
  /// the parents stops at a repeat or a missing parent, so a damaged store's chain ends.
  public func deadlineTasks(in workspace: Workspace) -> Set<TaskItemID>? {
    guard mode == .dueDateAndTag else { return nil }
    let tags = Set(workspace.tags.filter { $0.matchesLeafName(tag) }.map(\.id))
    guard !tags.isEmpty else { return [] }
    let tasks = Dictionary(
      workspace.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let projects = Set(
      workspace.projects.filter { $0.tagIDs.contains(where: tags.contains) }.map(\.id))
    let carries = { (task: TaskItem) in
      task.tagIDs.contains(where: tags.contains)
        || task.projectID.map(projects.contains) == true
    }
    return Set(
      workspace.tasks.filter { task in
        var seen: Set<TaskItemID> = []
        var next: TaskItem? = task
        while let current = next, seen.insert(current.id).inserted {
          if carries(current) { return true }
          next = current.parentTaskID.flatMap { tasks[$0] }
        }
        return false
      }.map(\.id))
  }

  /// Whether a tag of the workspace has the rule's leaf name; the Settings caption says so
  /// when none has (owner, 2026-11-25). Always true for all due dates.
  public func tagFound(in workspace: Workspace) -> Bool {
    mode == .allDueDates || workspace.tags.contains { $0.matchesLeafName(tag) }
  }
}
