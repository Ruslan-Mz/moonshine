import Foundation

/// OmniFocus snapshot contract v0.1 (`docs/discovery/snapshot-contract.md`), as decoded.
/// Produced by the JXA bridge (S3), the future plug-in export and the Demo fixture.
/// Dates stay strings here so the validator can check their offsets.
public struct SnapshotDocument: Decodable, Sendable {
  public struct Window: Decodable, Sendable {
    public var completedSince: String
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
    public var estimatedMinutes: Int?
    public var completionDate: String?
    public var added: String
    public var modified: String
    public var repeatOf: String?
    public var noteLength: Int
  }

  public var schemaVersion: Int
  public var source: String
  public var generatedAt: String
  public var timeZone: String
  public var window: Window
  public var folders: [Folder]
  public var tags: [Tag]
  public var projects: [Project]
  public var tasks: [Task]
}

extension SnapshotDocument.Task {
  /// Every date field that is set, in contract order.
  var dates: [String] {
    [
      deferDate, plannedDate, dueDate, effectiveDeferDate, effectiveDueDate, completionDate,
      added, modified,
    ].compactMap { $0 }
  }
}
