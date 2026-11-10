import Foundation

/// An entity as a store keeps it: still in its provider (`removedAt == nil`) or gone from it.
public struct Stored<Entity: Hashable & Sendable>: Hashable, Sendable {
  public let entity: Entity
  /// When the entity first went missing from an import; nil while its provider still has it.
  public let removedAt: Date?

  public init(_ entity: Entity, removedAt: Date? = nil) {
    self.entity = entity
    self.removedAt = removedAt
  }

  public var isRemoved: Bool { removedAt != nil }
}

/// Everything a store keeps, including history its providers no longer return (ADR-0002).
/// Every `Store` commits through `merging(_:at:)`, so all stores share one retention rule.
public struct StoredWorkspace: Hashable, Sendable {
  public var timeZone: TimeZone
  public var defaultTimeSettings: DefaultTimeSettings
  public var lines: [Stored<Line>]
  public var artifacts: [Stored<Artifact>]
  public var notes: [Stored<NoteRef>]
  public var projects: [Stored<Project>]
  public var tasks: [Stored<TaskItem>]
  public var tags: [Stored<Tag>]
  public var issues: [ImportIssue]
  public var completedSince: Date?

  public init(
    timeZone: TimeZone, defaultTimeSettings: DefaultTimeSettings = DefaultTimeSettings(),
    lines: [Stored<Line>] = [], artifacts: [Stored<Artifact>] = [],
    notes: [Stored<NoteRef>] = [], projects: [Stored<Project>] = [],
    tasks: [Stored<TaskItem>] = [], tags: [Stored<Tag>] = [], issues: [ImportIssue] = [],
    completedSince: Date? = nil
  ) {
    self.timeZone = timeZone
    self.completedSince = completedSince
    self.defaultTimeSettings = defaultTimeSettings
    self.lines = lines
    self.artifacts = artifacts
    self.notes = notes
    self.projects = projects
    self.tasks = tasks
    self.tags = tags
    self.issues = issues
  }

  /// What services read: every entity not removed, in stored order.
  public var workspace: Workspace {
    Workspace(
      timeZone: timeZone, defaultTimeSettings: defaultTimeSettings, lines: Self.visible(lines),
      artifacts: Self.visible(artifacts), notes: Self.visible(notes),
      projects: Self.visible(projects), tasks: Self.visible(tasks), tags: Self.visible(tags),
      issues: issues, completedSince: completedSince)
  }

  /// Applies a full import. Incoming entities replace stored ones by id, in import order.
  /// A stored entity missing from the import is kept after them: a completed task stays as it
  /// is (the snapshot only covers a recent window, so it has aged out), anything else is
  /// soft-deleted with `removedAt = now`. An entity that comes back is restored with its id.
  public func merging(_ incoming: Workspace, at now: Date) -> StoredWorkspace {
    func merge<Entity: Identifiable>(
      _ stored: [Stored<Entity>], _ incoming: [Entity],
      keepsWhenMissing: (Entity) -> Bool = { _ in false }
    ) -> [Stored<Entity>] {
      let incomingIDs = Set(incoming.map(\.id))
      let retained = stored.filter { !incomingIDs.contains($0.entity.id) }.map { old in
        old.isRemoved || keepsWhenMissing(old.entity) ? old : Stored(old.entity, removedAt: now)
      }
      return incoming.map { Stored($0) } + retained
    }
    return StoredWorkspace(
      timeZone: incoming.timeZone, defaultTimeSettings: incoming.defaultTimeSettings,
      lines: merge(lines, incoming.lines),
      artifacts: merge(artifacts, incoming.artifacts), notes: merge(notes, incoming.notes),
      projects: merge(projects, incoming.projects),
      tasks: merge(tasks, incoming.tasks) { $0.status == .completed },
      tags: merge(tags, incoming.tags), issues: incoming.issues,
      completedSince: incoming.completedSince)
  }

  private static func visible<Entity>(_ stored: [Stored<Entity>]) -> [Entity] {
    stored.filter { !$0.isRemoved }.map(\.entity)
  }
}
