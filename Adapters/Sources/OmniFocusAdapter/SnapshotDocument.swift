import Foundation

/// OmniFocus snapshot contract v0.2 (`docs/discovery/snapshot-contract.md`), as decoded.
/// Produced by the JXA bridge (S3), the future plug-in export and the Demo fixture.
/// Dates stay strings here so the validator can check their offsets.
public struct SnapshotDocument: Decodable, Sendable {
  public struct Window: Decodable, Sendable {
    public var completedSince: String
  }

  /// OmniFocus' default times of day, `HH:mm`; `planned` is nil when the setting does not exist.
  public struct DefaultTimes: Decodable, Sendable {
    public var due: String
    public var `defer`: String
    public var planned: String?
  }

  public struct Folder: Decodable, Sendable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var status: String
  }

  public struct Tag: Decodable, Sendable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var status: String
  }

  public struct Project: Decodable, Sendable {
    public var id: String
    public var name: String
    public var folderId: String?
    public var status: String
    public var tagIds: [String]
    public var completionDate: String?
  }

  public struct Task: Decodable, Sendable {
    public var id: String
    public var name: String
    public var projectId: String?
    public var parentTaskId: String?
    public var tagIds: [String]
    public var status: String
    public var flagged: Bool
    public var effectiveFlagged: Bool
    public var deferDate: String?
    public var plannedDate: String?
    public var dueDate: String?
    public var effectiveDeferDate: String?
    public var effectiveDueDate: String?
    /// Absent before OmniFocus 4.7.1; consumers then use `plannedDate`.
    public var effectivePlannedDate: String?
    public var estimatedMinutes: Int?
    public var completionDate: String?
    public var added: String
    public var modified: String
    public var repeatOf: String?
    public var noteLength: Int
  }

  public var schemaVersion: Int
  public var source: String
  /// `full` (nil in v0.1 documents) or `incremental`.
  public var mode: String?
  /// Set iff `mode == "incremental"`: tasks changed since this instant.
  public var modifiedSince: String?
  public var generatedAt: String
  public var timeZone: String
  public var defaultTimes: DefaultTimes?
  public var window: Window
  public var folders: [Folder]
  public var tags: [Tag]
  public var projects: [Project]
  public var tasks: [Task]
}

extension SnapshotDocument.Task {
  /// Every date field that is set, by contract name, in contract order.
  var dates: [(field: String, value: String)] {
    [
      ("deferDate", deferDate), ("plannedDate", plannedDate), ("dueDate", dueDate),
      ("effectiveDeferDate", effectiveDeferDate), ("effectiveDueDate", effectiveDueDate),
      ("effectivePlannedDate", effectivePlannedDate), ("completionDate", completionDate),
      ("added", added), ("modified", modified),
    ].compactMap { field, value in value.map { (field, $0) } }
  }
}

/// The change probe (contract §Change probe): no titles, only enough to tell whether
/// anything changed since the last import.
public struct ChangeProbe: Decodable, Sendable {
  public var schemaVersion: Int
  public var source: String
  public var mode: String
  public var generatedAt: String
  public var taskCount: Int
  /// The latest `modified` of any task (project root tasks included); nil for an empty database.
  public var latestModified: String?
}
