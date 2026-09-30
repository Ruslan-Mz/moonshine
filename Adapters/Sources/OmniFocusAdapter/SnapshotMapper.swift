import Foundation
import MoonShineCore

public enum SnapshotError: Error, Equatable {
  case unsupportedSchema(Int)
  case invalid([String])
  case badValue(field: String, value: String)
}

/// Checks the contract invariants (snapshot-contract §Invariants). Returns readable violations.
public enum SnapshotValidator {
  public static func violations(in document: SnapshotDocument) -> [String] {
    let folders = Set(document.folders.map(\.id))
    let tags = Set(document.tags.map(\.id))
    let projects = Set(document.projects.map(\.id))
    let tasks = Set(document.tasks.map(\.id))
    var found: [String] = []

    func check(_ owner: String, _ field: String, _ id: String?, in known: Set<String>) {
      if let id, !known.contains(id) { found.append("\(owner): \(field) \(id) does not resolve") }
    }
    func checkOffset(_ owner: String, _ date: String) {
      if date.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) == nil {
        found.append("\(owner): date without offset \(date)")
      }
    }

    checkOffset("document", document.generatedAt)
    for folder in document.folders {
      check("folder \(folder.id)", "parentId", folder.parentId, in: folders)
    }
    for tag in document.tags { check("tag \(tag.id)", "parentId", tag.parentId, in: tags) }
    for project in document.projects {
      check("project \(project.id)", "folderId", project.folderId, in: folders)
      for tag in project.tagIds { check("project \(project.id)", "tagId", tag, in: tags) }
    }
    for task in document.tasks {
      let owner = "task \(task.id)"
      check(owner, "projectId", task.projectId, in: projects)
      check(owner, "parentTaskId", task.parentTaskId, in: tasks)
      check(owner, "repeatOf", task.repeatOf, in: tasks)
      for tag in task.tagIds { check(owner, "tagId", tag, in: tags) }
      for date in task.dates { checkOffset(owner, date) }
      if (task.status == "completed") != (task.completionDate != nil) {
        found.append(
          task.status == "completed"
            ? "\(owner): completed without completionDate"
            : "\(owner): completionDate but not completed")
      }
      if let completed = task.completionDate, completed.prefix(10) < document.window.completedSince
      {
        found.append("\(owner): completed before the window")
      }
    }
    return found
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
      throw SnapshotError.badValue(field: "timeZone", value: document.timeZone)
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
      provider: .omnifocus, generatedAt: try date(document.generatedAt), timeZone: timeZone,
      tags: document.tags.map {
        SourceTag(externalId: $0.id, name: $0.name, parentExternalId: $0.parentId)
      },
      projects: try document.projects.map {
        SourceProject(
          externalId: $0.id, name: $0.name,
          status: try value(ProjectStatus.self, "project.status", $0.status),
          tagExternalIds: $0.tagIds, folderPath: folderPath($0.folderId))
      },
      tasks: try document.tasks.map {
        SourceTask(
          externalId: $0.id, name: $0.name, projectExternalId: $0.projectId,
          parentExternalId: $0.parentTaskId, tagExternalIds: $0.tagIds,
          status: try value(TaskItemStatus.self, "task.status", $0.status),
          flagged: $0.effectiveFlagged, plannedAt: try $0.plannedDate.map(date),
          deferUntil: try ($0.effectiveDeferDate ?? $0.deferDate).map(date),
          dueAt: try ($0.effectiveDueDate ?? $0.dueDate).map(date),
          estimateMinutes: $0.estimatedMinutes, completedAt: try $0.completionDate.map(date),
          modifiedAt: try date($0.modified), repeatOfExternalId: $0.repeatOf)
      })
  }

  static func date(_ string: String) throws -> Date {
    do {
      return try Date.ISO8601FormatStyle().parse(string)
    } catch {
      throw SnapshotError.badValue(field: "date", value: string)
    }
  }

  private static func value<T: RawRepresentable>(_: T.Type, _ field: String, _ raw: String) throws
    -> T where T.RawValue == String
  {
    guard let value = T(rawValue: raw) else {
      throw SnapshotError.badValue(field: field, value: raw)
    }
    return value
  }
}

/// Reads a snapshot JSON file: the Demo fixture now, the bridge's output from S3 on.
public struct SnapshotFileTaskProvider: TaskProvider {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// A file is always a full snapshot; `modifiedSince` is honoured by the live bridge (S3).
  public func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
    let data = try Data(contentsOf: url)
    return try SnapshotMapper.map(try JSONDecoder().decode(SnapshotDocument.self, from: data))
  }
}
