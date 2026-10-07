import Foundation

/// A task manager (OmniFocus today). Read-only until the Act phase.
public protocol TaskProvider: Sendable {
  /// All items, or only those modified since the given date (incremental refresh).
  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot
}

/// A notes vault (Obsidian today): lines, artifacts and horizon notes. Read-only until the Act phase.
public protocol NoteProvider: Sendable {
  func vault() async throws -> VaultSnapshot
}

/// The local store. The UI and services read only from here.
public protocol Store: Sendable {
  /// The identity map and the store version it was read at.
  func identityMap() async throws -> VersionedIdentityMap
  /// Applies a full import through `StoredWorkspace.merging(_:at:)` and saves the identities.
  /// Optimistic concurrency: throws `IdentityConflict` unless the store is still at
  /// `expectedVersion` (the version `identityMap()` returned); every commit bumps the version.
  func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date
  ) async throws
  /// What services read: everything not removed from its provider.
  func workspace() async throws -> Workspace
  /// Everything kept, including history its providers no longer return.
  func stored() async throws -> StoredWorkspace
}

public struct VersionedIdentityMap: Sendable {
  public var map: IdentityMap
  /// 0 for an empty store; +1 on every commit.
  public let version: Int

  public init(map: IdentityMap, version: Int) {
    self.map = map
    self.version = version
  }
}

/// A commit built from an identity map another commit has since replaced. Its ids may
/// disagree with the stored ones, so it is rejected instead of merged.
public struct IdentityConflict: Error, Equatable, Sendable {
  public let expectedVersion: Int
  public let actualVersion: Int

  public init(expectedVersion: Int, actualVersion: Int) {
    self.expectedVersion = expectedVersion
    self.actualVersion = actualVersion
  }
}

// MARK: - Task-manager records, keyed by the provider's own ids

public struct TaskSourceSnapshot: Sendable {
  public let provider: ProviderID
  public let generatedAt: Date
  public let timeZone: TimeZone
  /// nil = a complete snapshot; otherwise only tasks changed since this date. Only a
  /// complete snapshot may be merged as a full import (its absences soft-delete).
  public let modifiedSince: Date?
  public let tags: [SourceTag]
  public let projects: [SourceProject]
  public let tasks: [SourceTask]

  public init(
    provider: ProviderID, generatedAt: Date, timeZone: TimeZone, modifiedSince: Date? = nil,
    tags: [SourceTag], projects: [SourceProject], tasks: [SourceTask]
  ) {
    self.provider = provider
    self.generatedAt = generatedAt
    self.timeZone = timeZone
    self.modifiedSince = modifiedSince
    self.tags = tags
    self.projects = projects
    self.tasks = tasks
  }
}

public struct SourceTag: Sendable {
  public let externalId: String
  public let name: String
  public let parentExternalId: String?

  public init(externalId: String, name: String, parentExternalId: String? = nil) {
    self.externalId = externalId
    self.name = name
    self.parentExternalId = parentExternalId
  }
}

public struct SourceProject: Sendable {
  public let externalId: String
  public let name: String
  public let status: ProjectStatus
  public let tagExternalIds: [String]
  /// Folder names from the top level down; the first one drives folder mapping.
  public let folderPath: [String]

  public init(
    externalId: String, name: String, status: ProjectStatus = .active,
    tagExternalIds: [String] = [], folderPath: [String] = []
  ) {
    self.externalId = externalId
    self.name = name
    self.status = status
    self.tagExternalIds = tagExternalIds
    self.folderPath = folderPath
  }
}

public struct SourceTask: Sendable {
  public let externalId: String
  public let name: String
  public let projectExternalId: String?
  public let parentExternalId: String?
  public let tagExternalIds: [String]
  public let status: TaskItemStatus
  public let flagged: Bool
  public let plannedAt: Date?
  public let deferUntil: Date?
  public let dueAt: Date?
  /// Computed by the provider from parents and project; nil = the own date.
  public let effectivePlannedAt: Date?
  public let effectiveDeferUntil: Date?
  public let effectiveDueAt: Date?
  public let estimateMinutes: Int?
  public let completedAt: Date?
  public let modifiedAt: Date?
  public let repeatOfExternalId: String?

  public init(
    externalId: String, name: String, projectExternalId: String? = nil,
    parentExternalId: String? = nil, tagExternalIds: [String] = [],
    status: TaskItemStatus = .available, flagged: Bool = false, plannedAt: Date? = nil,
    deferUntil: Date? = nil, dueAt: Date? = nil, effectivePlannedAt: Date? = nil,
    effectiveDeferUntil: Date? = nil, effectiveDueAt: Date? = nil, estimateMinutes: Int? = nil,
    completedAt: Date? = nil, modifiedAt: Date? = nil, repeatOfExternalId: String? = nil
  ) {
    self.externalId = externalId
    self.name = name
    self.projectExternalId = projectExternalId
    self.parentExternalId = parentExternalId
    self.tagExternalIds = tagExternalIds
    self.status = status
    self.flagged = flagged
    self.plannedAt = plannedAt
    self.deferUntil = deferUntil
    self.dueAt = dueAt
    self.effectivePlannedAt = effectivePlannedAt ?? plannedAt
    self.effectiveDeferUntil = effectiveDeferUntil ?? deferUntil
    self.effectiveDueAt = effectiveDueAt ?? dueAt
    self.estimateMinutes = estimateMinutes
    self.completedAt = completedAt
    self.modifiedAt = modifiedAt
    self.repeatOfExternalId = repeatOfExternalId
  }
}

// MARK: - Vault records

public struct VaultSnapshot: Sendable {
  public let lines: VaultLines
  public let artifacts: [SourceArtifact]
  public let notes: [SourceNote]
  public let issues: [ImportIssue]

  public init(
    lines: VaultLines, artifacts: [SourceArtifact], notes: [SourceNote],
    issues: [ImportIssue] = []
  ) {
    self.lines = lines
    self.artifacts = artifacts
    self.notes = notes
    self.issues = issues
  }
}

/// What the vault said about its lines. "Could not read the lines" is not "there are no lines":
/// only a clean read may soft-delete a stored line (`Importer.makeWorkspace`).
public enum VaultLines: Equatable, Sendable {
  /// The budget note is missing or rejected, or its `lines:` is missing or not a list.
  case unavailable
  /// `complete` is false when any `lines:` item was skipped.
  case read([SourceLine], complete: Bool)

  /// The lines that were read; none when unavailable.
  public var read: [SourceLine] {
    if case .read(let lines, _) = self { lines } else { [] }
  }

  /// A clean read: the budget note was found, `lines:` parsed and no item skipped.
  public var isComplete: Bool {
    if case .read(_, complete: true) = self { true } else { false }
  }
}

public struct SourceLine: Equatable, Sendable {
  public let key: LineKey
  public let name: String
  public let emoji: String?
  public let block: String
  public let state: LineState
  public let budgetHoursPerWeek: Double?
  public let parentLink: String?
  public let taskRules: LineTaskRules

  public init(
    key: LineKey, name: String, emoji: String? = nil, block: String, state: LineState,
    budgetHoursPerWeek: Double? = nil, parentLink: String? = nil,
    tags: [String] = [], folders: [String] = [], projects: [String] = []
  ) {
    self.key = key
    self.name = name
    self.emoji = emoji
    self.block = block
    self.state = state
    self.budgetHoursPerWeek = budgetHoursPerWeek
    self.parentLink = parentLink
    self.taskRules = LineTaskRules(tags: tags, folders: folders, projects: projects)
  }
}

public struct SourceArtifact: Sendable {
  public let key: String
  public let title: String
  public let lineKeys: [LineKey]
  public let status: ArtifactStatus
  public let priority: Bool
  public let notePath: String

  public init(
    key: String, title: String, lineKeys: [LineKey], status: ArtifactStatus,
    priority: Bool = false, notePath: String
  ) {
    self.key = key
    self.title = title
    self.lineKeys = lineKeys
    self.status = status
    self.priority = priority
    self.notePath = notePath
  }
}

public struct SourceNote: Sendable {
  public let path: String
  public let title: String
  public let type: String?
  public let scale: Scale?
  public let period: Horizon?
  public let parentLink: String?
  public let lineKey: LineKey?
  public let status: String?

  public init(
    path: String, title: String, type: String? = nil, scale: Scale? = nil,
    period: Horizon? = nil, parentLink: String? = nil, lineKey: LineKey? = nil,
    status: String? = nil
  ) {
    self.path = path
    self.title = title
    self.type = type
    self.scale = scale
    self.period = period
    self.parentLink = parentLink
    self.lineKey = lineKey
    self.status = status
  }
}
