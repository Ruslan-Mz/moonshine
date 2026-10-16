import Foundation

/// Where a line's thread ends: its artifact in the current year note, else its parent note.
public enum TraceTarget: Hashable, Sendable {
  case artifact(Artifact)
  case note(NoteRef)
}

/// task → project → line → artifact. A missing step is simply absent; never a warning.
public struct Trace: Hashable, Sendable {
  public let taskID: TaskItemID
  public let project: Project?
  public let line: LineAssignment
  /// The vault line; nil for Life ops.
  public let lineEntity: Line?
  public let target: TraceTarget?
}

/// Resolves traces (vault-contract §2.2) for the year containing `now`.
public struct Tracer: Sendable {
  private let projects: [ProjectID: Project]
  private let lines: [LineID: Line]
  private let targets: [LineID: TraceTarget]

  public init(workspace: Workspace, now: Date) {
    projects = Dictionary(
      workspace.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    lines = Dictionary(
      workspace.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // Artifacts of the year note(s) whose period contains `now`: open before done, then
    // priority, then in progress before planned, then vault order. Dropped never end a trace.
    let currentYearNotes = Set(
      workspace.notes.filter { $0.type == "year_artifacts" && $0.period?.contains(now) == true }
        .map(\.id))
    func rank(_ artifact: Artifact, _ vaultOrder: Int) -> (Int, Int, Int, Int) {
      let status: Int
      switch artifact.status {
      case .inProgress: status = 0
      case .planned: status = 1
      case .done, .dropped: status = 2
      }
      return (status == 2 ? 1 : 0, artifact.priority ? 0 : 1, status, vaultOrder)
    }
    let candidates = workspace.artifacts.enumerated()
      .filter { $0.element.status != .dropped }
      .filter { $0.element.noteID.map(currentYearNotes.contains) == true }
      .sorted { rank($0.element, $0.offset) < rank($1.element, $1.offset) }
      .map(\.element)
    var targets: [LineID: TraceTarget] = [:]
    for artifact in candidates {
      for lineID in artifact.lineIDs where targets[lineID] == nil {
        targets[lineID] = .artifact(artifact)
      }
    }
    let paths = workspace.notes.map(\.path)
    for line in workspace.lines where targets[line.id] == nil {
      // An unresolved parent ends the trace at the line, with no problem.
      if let index = line.parentLink.flatMap({ WikiLink.target(of: $0, in: paths)?.index }) {
        targets[line.id] = .note(workspace.notes[index])
      }
    }
    self.targets = targets
  }

  public func trace(_ task: TaskItem) -> Trace {
    let lineEntity: Line?
    if case .line(let id) = task.line { lineEntity = lines[id] } else { lineEntity = nil }
    return Trace(
      taskID: task.id, project: task.projectID.flatMap { projects[$0] }, line: task.line,
      lineEntity: lineEntity, target: lineEntity.flatMap { targets[$0.id] })
  }

}
