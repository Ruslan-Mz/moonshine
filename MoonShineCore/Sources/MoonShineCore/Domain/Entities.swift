import Foundation

/// The vault slug of a line (`violin`). Stable across renames of the display name.
public struct LineKey: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
}

public enum LineState: String, Hashable, Sendable {
  case active, maintenance, paused
}

/// How task-manager items map to a line (vault `lines[*].omnifocus`). Names, exact match.
public struct LineTaskRules: Hashable, Sendable {
  public let tags: [String]
  public let folders: [String]
  public let projects: [String]

  public init(tags: [String] = [], folders: [String] = [], projects: [String] = []) {
    self.tags = tags
    self.folders = folders
    self.projects = projects
  }
}

public struct Line: Hashable, Sendable, Identifiable {
  public let id: LineID
  public let refs: [ExternalRef]
  public let key: LineKey
  public let name: String
  public let emoji: String?
  public let block: String
  public let state: LineState
  /// From the vault budget only; nil = no weekly budget.
  public let budgetHoursPerWeek: Double?
  public let parentLink: String?
  public let taskRules: LineTaskRules

  public init(
    id: LineID, refs: [ExternalRef], key: LineKey, name: String, emoji: String?, block: String,
    state: LineState, budgetHoursPerWeek: Double?, parentLink: String?, taskRules: LineTaskRules
  ) {
    self.id = id
    self.refs = refs
    self.key = key
    self.name = name
    self.emoji = emoji
    self.block = block
    self.state = state
    self.budgetHoursPerWeek = budgetHoursPerWeek
    self.parentLink = parentLink
    self.taskRules = taskRules
  }
}

/// Every project and task belongs to exactly one line, or to Life ops — a fixed bucket
/// for household, admin, routines and the inbox. Life ops is not a line: no budget, never quiet.
public enum LineAssignment: Hashable, Sendable {
  case line(LineID)
  case lifeOps
}

public enum ArtifactStatus: String, Hashable, Sendable {
  case planned
  case inProgress = "in_progress"
  case done, dropped
}

public struct Artifact: Hashable, Sendable, Identifiable {
  public let id: ArtifactID
  public let refs: [ExternalRef]
  /// Vault id, e.g. `a26-01`.
  public let key: String
  public let title: String
  public let lineIDs: [LineID]
  public let status: ArtifactStatus
  public let priority: Bool
  public let noteID: NoteID?

  public init(
    id: ArtifactID, refs: [ExternalRef], key: String, title: String, lineIDs: [LineID],
    status: ArtifactStatus, priority: Bool, noteID: NoteID?
  ) {
    self.id = id
    self.refs = refs
    self.key = key
    self.title = title
    self.lineIDs = lineIDs
    self.status = status
    self.priority = priority
    self.noteID = noteID
  }
}

public enum ProjectStatus: String, Hashable, Sendable {
  case active, onHold, done, dropped
}

public struct Project: Hashable, Sendable, Identifiable {
  public let id: ProjectID
  public let refs: [ExternalRef]
  public let title: String
  public let status: ProjectStatus
  public let tagIDs: [TagID]
  public let line: LineAssignment

  public init(
    id: ProjectID, refs: [ExternalRef], title: String, status: ProjectStatus, tagIDs: [TagID],
    line: LineAssignment
  ) {
    self.id = id
    self.refs = refs
    self.title = title
    self.status = status
    self.tagIDs = tagIDs
    self.line = line
  }
}

public enum TaskItemStatus: String, Hashable, Sendable {
  case available, blocked, completed, dropped
}

/// A task from a task manager. Named `TaskItem` so it never shadows Swift Concurrency's `Task`.
public struct TaskItem: Hashable, Sendable, Identifiable {
  public let id: TaskItemID
  public let refs: [ExternalRef]
  public let title: String
  public let projectID: ProjectID?
  public let parentTaskID: TaskItemID?
  public let tagIDs: [TagID]
  public let status: TaskItemStatus
  public let flagged: Bool
  /// The task's own dates, as set on the task itself.
  public let plannedAt: Date?
  public let deferUntil: Date?
  public let dueAt: Date?
  /// The dates the task manager computes from the task, its parents and its project.
  /// Placement and urgency use these: an inherited project due date is a real due date,
  /// the only reason a task may use the urgent colour.
  public let effectivePlannedAt: Date?
  public let effectiveDeferUntil: Date?
  public let effectiveDueAt: Date?
  public let estimateMinutes: Int?
  public let completedAt: Date?
  public let modifiedAt: Date?
  /// The live repeating task this completed occurrence came from; nil for one-off tasks.
  public let occurrenceOf: TaskItemID?
  public let line: LineAssignment

  public init(
    id: TaskItemID, refs: [ExternalRef], title: String, projectID: ProjectID?,
    parentTaskID: TaskItemID?, tagIDs: [TagID], status: TaskItemStatus, flagged: Bool,
    plannedAt: Date?, deferUntil: Date?, dueAt: Date?, effectivePlannedAt: Date?,
    effectiveDeferUntil: Date?, effectiveDueAt: Date?, estimateMinutes: Int?,
    completedAt: Date?, modifiedAt: Date?, occurrenceOf: TaskItemID?, line: LineAssignment
  ) {
    self.id = id
    self.refs = refs
    self.title = title
    self.projectID = projectID
    self.parentTaskID = parentTaskID
    self.tagIDs = tagIDs
    self.status = status
    self.flagged = flagged
    self.plannedAt = plannedAt
    self.deferUntil = deferUntil
    self.dueAt = dueAt
    self.effectivePlannedAt = effectivePlannedAt
    self.effectiveDeferUntil = effectiveDeferUntil
    self.effectiveDueAt = effectiveDueAt
    self.estimateMinutes = estimateMinutes
    self.completedAt = completedAt
    self.modifiedAt = modifiedAt
    self.occurrenceOf = occurrenceOf
    self.line = line
  }

  /// Occurrences of repeating tasks count as rhythm (sessions); everything else as progress.
  public var isOccurrence: Bool { occurrenceOf != nil }
}

public struct Tag: Hashable, Sendable, Identifiable {
  public let id: TagID
  public let refs: [ExternalRef]
  public let name: String
  public let parentID: TagID?
  /// Meta tags (energy, context, time…) are task attributes and never map a line.
  public let isMeta: Bool

  public init(id: TagID, refs: [ExternalRef], name: String, parentID: TagID?, isMeta: Bool) {
    self.id = id
    self.refs = refs
    self.name = name
    self.parentID = parentID
    self.isMeta = isMeta
  }
}

public struct NoteRef: Hashable, Sendable, Identifiable {
  public let id: NoteID
  public let refs: [ExternalRef]
  /// Vault-relative path.
  public let path: String
  public let title: String
  public let type: String?
  public let scale: Scale?
  public let period: Horizon?
  public let parentLink: String?
  public let lineKey: LineKey?
  public let status: String?

  public init(
    id: NoteID, refs: [ExternalRef], path: String, title: String, type: String?,
    scale: Scale?, period: Horizon?, parentLink: String?, lineKey: LineKey?, status: String?
  ) {
    self.id = id
    self.refs = refs
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

/// Everything the store holds for phase 1. Services read only this.
public struct Workspace: Sendable {
  public var timeZone: TimeZone
  public var lines: [Line]
  public var artifacts: [Artifact]
  public var notes: [NoteRef]
  public var projects: [Project]
  public var tasks: [TaskItem]
  public var tags: [Tag]
  public var issues: [ImportIssue]

  public init(
    timeZone: TimeZone, lines: [Line] = [], artifacts: [Artifact] = [], notes: [NoteRef] = [],
    projects: [Project] = [], tasks: [TaskItem] = [], tags: [Tag] = [], issues: [ImportIssue] = []
  ) {
    self.timeZone = timeZone
    self.lines = lines
    self.artifacts = artifacts
    self.notes = notes
    self.projects = projects
    self.tasks = tasks
    self.tags = tags
    self.issues = issues
  }
}

/// A calm, non-fatal problem found while importing; shown as a banner, never a crash.
public enum ImportIssue: Hashable, Sendable {
  case ruleClaimedTwice(rule: String, kept: LineKey, ignored: LineKey)
  case unknownLineKey(LineKey, in: String)
  /// `path` is vault-relative; `line` is the note's line number, when known.
  case vault(path: String, line: Int?, problem: VaultProblem)
  /// A problem of the whole vault that belongs to no note (`budgetNoteMissing`).
  case vaultWide(VaultProblem)
}

/// What went wrong with one vault note. Never carries note content: `key` is a contract key
/// name set by the reader (`lines[3].budget_h_week`), never a value from the note.
public struct VaultProblem: Hashable, Sendable, CustomStringConvertible {
  public enum Kind: String, Hashable, Sendable, Codable {
    /// The note, or a folder of notes, could not be opened or read.
    case unreadable
    /// The frontmatter is not UTF-8 text.
    case notUTF8
    /// The frontmatter does not close within the reader's size limit.
    case frontmatterTooLarge
    /// The frontmatter is not valid YAML, or never closes.
    case malformedYAML
    /// Too many YAML nodes or too deep a nesting.
    case yamlTooComplex
    /// A YAML anchor (`&name`) together with an alias (`*name`). Yams expands aliases while
    /// parsing, so the reader rejects the pair before parsing; counted on its own to spot false
    /// positives.
    case yamlAnchor
    /// A YAML directive (`%YAML`, `%TAG`): a `%TAG` prefix is copied into every tag that uses
    /// it, so the reader rejects directives before parsing.
    case yamlDirective
    /// A symbolic link; the reader never follows one.
    case symlinkSkipped
    /// The resolved file lies outside the vault folder.
    case outsideVault
    /// No note has `moonshine: budget` (vault-wide). A rejected note may be the budget note.
    case budgetNoteMissing
    /// Another note has `moonshine: budget`; the first by path is the budget note.
    case budgetNoteDuplicate
  }

  public let kind: Kind
  public let key: String?

  public init(_ kind: Kind, key: String? = nil) {
    self.kind = kind
    self.key = key
  }

  public var description: String { key.map { "\(kind.rawValue) (\($0))" } ?? kind.rawValue }
}
