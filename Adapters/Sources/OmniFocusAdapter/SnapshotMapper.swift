import Foundation
import MoonShineCore

/// Snapshot errors name a JSON path and a rule, never a value: the document carries the
/// owner's titles and ids, and these errors may end up in logs.
public enum SnapshotError: Error, Equatable {
  case unsupportedSchema(Int)
  case invalid([SnapshotViolation])
  /// The value at `path` (e.g. `tasks[3].status`) is not one the contract allows.
  case badValue(path: String)
}

/// A broken contract invariant: where (array indices, not ids) and which rule.
public struct SnapshotViolation: Equatable, Sendable, CustomStringConvertible {
  public let path: String
  public let rule: String

  public init(_ path: String, _ rule: String) {
    self.path = path
    self.rule = rule
  }

  public var description: String { "\(path): \(rule)" }
}

/// Checks the contract invariants (snapshot-contract §Invariants).
public enum SnapshotValidator {
  public static func violations(in document: SnapshotDocument) -> [SnapshotViolation] {
    let folders = Set(document.folders.map(\.id))
    let tags = Set(document.tags.map(\.id))
    let projects = Set(document.projects.map(\.id))
    let tasks = Set(document.tasks.map(\.id))
    var found: [SnapshotViolation] = []

    func check(_ path: String, _ id: String?, in known: Set<String>) {
      if let id, !known.contains(id) { found.append(.init(path, "does not resolve")) }
    }
    func checkOffset(_ path: String, _ date: String) {
      if !hasOffset(date) { found.append(.init(path, "date without offset")) }
    }

    let isIncremental = document.mode == "incremental"
    checkOffset("generatedAt", document.generatedAt)
    if let mode = document.mode, mode != "full", !isIncremental {
      found.append(.init("mode", "is neither full nor incremental"))
    }
    switch (isIncremental, document.modifiedSince) {
    case (true, nil): found.append(.init("modifiedSince", "missing in an incremental snapshot"))
    case (false, .some): found.append(.init("modifiedSince", "set in a full snapshot"))
    case (true, .some(let since)): checkOffset("modifiedSince", since)
    case (false, nil): break
    }
    if let times = document.defaultTimes {
      for (name, time) in [("due", times.due), ("defer", times.defer), ("planned", times.planned)]
      where time.map({ $0.wholeMatch(of: /([01]\d|2[0-3]):[0-5]\d/) == nil }) == true {
        found.append(.init("defaultTimes.\(name)", "is not HH:mm"))
      }
    }
    for (i, folder) in document.folders.enumerated() {
      check("folders[\(i)].parentId", folder.parentId, in: folders)
    }
    for (i, tag) in document.tags.enumerated() {
      check("tags[\(i)].parentId", tag.parentId, in: tags)
    }
    for (i, project) in document.projects.enumerated() {
      check("projects[\(i)].folderId", project.folderId, in: folders)
      for (j, tag) in project.tagIds.enumerated() {
        check("projects[\(i)].tagIds[\(j)]", tag, in: tags)
      }
    }
    for (i, task) in document.tasks.enumerated() {
      let path = "tasks[\(i)]"
      check("\(path).projectId", task.projectId, in: projects)
      // An incremental snapshot reports dropped tasks (a full one may still hold a dropped
      // project, as the container of in-window completions); its task references may point
      // to tasks from earlier imports.
      if !isIncremental {
        check("\(path).parentTaskId", task.parentTaskId, in: tasks)
        check("\(path).repeatOf", task.repeatOf, in: tasks)
        if task.status == "dropped" {
          found.append(.init("\(path).status", "dropped in a full snapshot"))
        }
      }
      for (j, tag) in task.tagIds.enumerated() { check("\(path).tagIds[\(j)]", tag, in: tags) }
      for (field, date) in task.dates { checkOffset("\(path).\(field)", date) }
      if (task.status == "completed") != (task.completionDate != nil) {
        found.append(
          .init(
            "\(path).completionDate",
            task.status == "completed" ? "missing on a completed task" : "set but not completed"))
      }
      if let completed = task.completionDate, completed.prefix(10) < document.window.completedSince
      {
        found.append(.init("\(path).completionDate", "before the window"))
      }
    }
    return found
  }

  /// Checks a change probe (snapshot-contract §Modes).
  public static func violations(in probe: ChangeProbe) -> [SnapshotViolation] {
    var found: [SnapshotViolation] = []
    if probe.schemaVersion != 1 { found.append(.init("schemaVersion", "unsupported")) }
    if probe.source != "omnifocus" { found.append(.init("source", "is not omnifocus")) }
    if probe.mode != "probe" { found.append(.init("mode", "is not probe")) }
    if !hasOffset(probe.generatedAt) { found.append(.init("generatedAt", "date without offset")) }
    if probe.taskCount < 0 { found.append(.init("taskCount", "is negative")) }
    if let latest = probe.latestModified, !hasOffset(latest) {
      found.append(.init("latestModified", "date without offset"))
    }
    return found
  }

  static func hasOffset(_ date: String) -> Bool {
    date.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil
  }
}

/// Maps a validated snapshot document to provider-neutral source records.
public enum SnapshotMapper {
  public static func map(_ document: SnapshotDocument) throws -> TaskSourceSnapshot {
    guard document.schemaVersion == 1 else {
      throw SnapshotError.unsupportedSchema(document.schemaVersion)
    }
    let violations = SnapshotValidator.violations(in: document)
    guard violations.isEmpty else { throw SnapshotError.invalid(violations) }
    guard let timeZone = TimeZone(identifier: document.timeZone) else {
      throw SnapshotError.badValue(path: "timeZone")
    }

    let folders = Dictionary(uniqueKeysWithValues: document.folders.map { ($0.id, $0) })
    func folderPath(_ id: String?) -> [String] {
      var path: [String] = []
      var current = id.flatMap { folders[$0] }
      while let folder = current {
        path.insert(folder.name, at: 0)
        current = folder.parentId.flatMap { folders[$0] }
      }
      return path
    }

    return TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: try date(document.generatedAt, at: "generatedAt"),
      timeZone: timeZone,
      modifiedSince: try document.modifiedSince.map { try date($0, at: "modifiedSince") },
      tags: document.tags.map {
        SourceTag(externalId: $0.id, name: $0.name, parentExternalId: $0.parentId)
      },
      projects: try document.projects.enumerated().map { i, project in
        SourceProject(
          externalId: project.id, name: project.name,
          status: try value(ProjectStatus.self, project.status, at: "projects[\(i)].status"),
          tagExternalIds: project.tagIds, folderPath: folderPath(project.folderId))
      },
      tasks: try document.tasks.enumerated().map { i, task in
        func at(_ field: String) -> String { "tasks[\(i)].\(field)" }
        func optional(_ string: String?, _ field: String) throws -> Date? {
          try string.map { try date($0, at: at(field)) }
        }
        return SourceTask(
          externalId: task.id, name: task.name, projectExternalId: task.projectId,
          parentExternalId: task.parentTaskId, tagExternalIds: task.tagIds,
          status: try value(TaskItemStatus.self, task.status, at: at("status")),
          flagged: task.effectiveFlagged,
          plannedAt: try optional(task.plannedDate, "plannedDate"),
          deferUntil: try optional(task.deferDate, "deferDate"),
          dueAt: try optional(task.dueDate, "dueDate"),
          effectivePlannedAt: try optional(task.effectivePlannedDate, "effectivePlannedDate"),
          effectiveDeferUntil: try optional(task.effectiveDeferDate, "effectiveDeferDate"),
          effectiveDueAt: try optional(task.effectiveDueDate, "effectiveDueDate"),
          estimateMinutes: task.estimatedMinutes,
          completedAt: try optional(task.completionDate, "completionDate"),
          modifiedAt: try date(task.modified, at: at("modified")),
          repeatOfExternalId: task.repeatOf)
      })
  }

  static func date(_ string: String, at path: String) throws -> Date {
    do {
      return try Date.ISO8601FormatStyle().parse(string)
    } catch {
      throw SnapshotError.badValue(path: path)
    }
  }

  private static func value<T: RawRepresentable>(_: T.Type, _ raw: String, at path: String) throws
    -> T where T.RawValue == String
  {
    guard let value = T(rawValue: raw) else { throw SnapshotError.badValue(path: path) }
    return value
  }
}

/// Reads a snapshot JSON file: the Demo fixture, or a saved bridge output.
public struct SnapshotFileTaskProvider: TaskProvider {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// A file is whatever snapshot it holds; `modifiedSince` is honoured by the live bridge.
  public func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
    let data = try Data(contentsOf: url)
    return try SnapshotMapper.map(try JSONDecoder().decode(SnapshotDocument.self, from: data))
  }
}
