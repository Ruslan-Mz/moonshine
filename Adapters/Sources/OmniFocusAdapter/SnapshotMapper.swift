import Foundation
import MoonShineCore

/// Snapshot errors name a JSON path and a rule, never a value: the document carries the
/// owner's titles and ids, and these errors may end up in logs.
public enum SnapshotError: Error, Equatable {
  case unsupportedSchema(Int)
  case invalid([SnapshotViolation])
  /// The value at `path` (e.g. `tasks[3].status`) is not one the contract allows.
  case badValue(path: String)
  /// The JSON does not decode at `path` (`document` for malformed JSON). Replaces
  /// Foundation's `DecodingError`, whose descriptions can quote the payload.
  case undecodable(path: String)
}

extension SnapshotError: ImportFailureKind {
  public var importFailure: ImportFailure { .invalidSnapshot }
}

extension SnapshotDocument {
  /// The only way to decode a snapshot: errors carry a path, never payload text.
  public static func decode(_ data: Data) throws -> SnapshotDocument {
    try decodeWithoutValues(SnapshotDocument.self, data)
  }
}

extension ChangeProbe {
  /// The only way to decode a change probe: errors carry a path, never payload text.
  public static func decode(_ data: Data) throws -> ChangeProbe {
    try decodeWithoutValues(ChangeProbe.self, data)
  }
}

func decodeWithoutValues<T: Decodable>(_: T.Type, _ data: Data) throws -> T {
  do {
    return try JSONDecoder().decode(T.self, from: data)
  } catch let error as DecodingError {
    let context: DecodingError.Context? =
      switch error {
      case .typeMismatch(_, let context), .valueNotFound(_, let context),
        .dataCorrupted(let context):
        context
      case .keyNotFound(let key, let context):
        DecodingError.Context(codingPath: context.codingPath + [key], debugDescription: "")
      @unknown default: nil
      }
    let path = (context?.codingPath ?? []).enumerated().map { index, key in
      key.intValue.map { "[\($0)]" } ?? (index == 0 ? key.stringValue : ".\(key.stringValue)")
    }.joined()
    throw SnapshotError.undecodable(path: path.isEmpty ? "document" : path)
  }
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
  /// A task estimate in minutes: none below zero, at most a year, so sums never overflow.
  public static let estimateRange = 0...525_600

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
    if document.source != "omnifocus" { found.append(.init("source", "is not omnifocus")) }
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
      where time.map({ $0.wholeMatch(of: SnapshotMapper.timeShape) == nil }) == true {
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
      if let minutes = task.estimatedMinutes, !estimateRange.contains(minutes) {
        found.append(.init("\(path).estimatedMinutes", "is outside 0…\(estimateRange.upperBound)"))
      }
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
    // A probe has no mapping step that would parse its dates later, so parse them here.
    func checkDate(_ path: String, _ date: String) {
      if !hasOffset(date) || (try? SnapshotMapper.date(date, at: path)) == nil {
        found.append(.init(path, "is not an ISO 8601 date with offset"))
      }
    }
    checkDate("generatedAt", probe.generatedAt)
    if probe.taskCount < 0 { found.append(.init("taskCount", "is negative")) }
    if let latest = probe.latestModified { checkDate("latestModified", latest) }
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
      defaultTimes: try document.defaultTimes.map { times in
        DefaultTimeSettings(
          due: try timeOfDay(times.due, at: "defaultTimes.due"),
          defer: try timeOfDay(times.defer, at: "defaultTimes.defer"),
          planned: try times.planned.map { try timeOfDay($0, at: "defaultTimes.planned") })
      },
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

  /// The ISO 8601 shape with every field in range. Built once: a snapshot holds ~10 000
  /// dates (building it per call cost 0.7 s per import). `Regex` is not Sendable; this one
  /// is immutable and only matched against.
  nonisolated(unsafe) static let dateShape =
    /\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?(Z|[+-]([01]\d|2[0-3]):?[0-5]\d)/

  /// `HH:mm` from 00:00 to 23:59, ASCII digits only: `\d` would also match `٩` or `０`, which
  /// `Int` does not parse.
  nonisolated(unsafe) static let timeShape = /([01][0-9]|2[0-3]):[0-5][0-9]/

  /// The validator has already checked the shape; this throw is the defence behind it.
  static func timeOfDay(_ string: String, at path: String) throws -> TimeOfDay {
    guard string.wholeMatch(of: timeShape) != nil,
      let hour = Int(string.prefix(2)), let minute = Int(string.suffix(2)),
      let time = TimeOfDay(hour: hour, minute: minute)
    else { throw SnapshotError.badValue(path: path) }
    return time
  }

  /// `Date.ISO8601FormatStyle` rolls over out-of-range fields (`25:61` parses), so the
  /// shape and ranges are checked first.
  static func date(_ string: String, at path: String) throws -> Date {
    guard string.wholeMatch(of: dateShape) != nil,
      let date = try? Date.ISO8601FormatStyle().parse(string)
    else { throw SnapshotError.badValue(path: path) }
    return date
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
    return try SnapshotMapper.map(try SnapshotDocument.decode(data))
  }
}
