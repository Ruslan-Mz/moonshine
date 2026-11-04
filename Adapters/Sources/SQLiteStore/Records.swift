import Foundation
import GRDB
import MoonShineCore

/// Every instant in the database: Unix milliseconds, UTC.
typealias Millis = Int64

extension Date {
  var millis: Millis { Millis((timeIntervalSince1970 * 1000).rounded()) }
  init(millis: Millis) { self.init(timeIntervalSince1970: Double(millis) / 1000) }
}

enum SQLiteStoreError: Error, Equatable {
  /// A stored text that names no known case; the value is left out.
  case unknownValue(column: String)
  /// A stored number outside its range; the value is left out.
  case outOfRange(column: String)
}

func decode<Value: RawRepresentable>(_ raw: String, _ column: String) throws -> Value
where Value.RawValue == String {
  guard let value = Value(rawValue: raw) else {
    throw SQLiteStoreError.unknownValue(column: column)
  }
  return value
}

/// A row of an entity table: core columns, `attrs` JSON, source order and soft delete.
protocol EntityRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
  associatedtype Entity: Hashable & Sendable
  var id: UUID { get }
  var ordinal: Int { get set }
  var removedAt: Millis? { get }
  init(_ entity: Entity, ordinal: Int, removedAt: Millis?)
  func entity(refs: [ExternalRef]) throws -> Entity
}

extension EntityRecord {
  static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy {
    .convertFromSnakeCase
  }
  static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

  init(_ stored: Stored<Entity>, ordinal: Int) {
    self.init(stored.entity, ordinal: ordinal, removedAt: stored.removedAt?.millis)
  }

  func stored(refs: [UUID: [ExternalRef]]) throws -> Stored<Entity> {
    Stored(try entity(refs: refs[id] ?? []), removedAt: removedAt.map(Date.init(millis:)))
  }
}

extension LineAssignment {
  var lineId: UUID? {
    if case .line(let id) = self { id.uuid } else { nil }
  }

  init(lineId: UUID?) {
    self = lineId.map { .line(LineID(uuid: $0)) } ?? .lifeOps
  }
}

struct LineRecord: EntityRecord {
  static let databaseTableName = "line"
  struct Attrs: Codable, Equatable, Sendable {
    var parentLink: String?
    var tags, folders, projects: [String]
    /// Absent in rows stored before the v0.2 keys; `foundation` is kept only when true.
    var foundation: Bool?
    var floorHoursPerDay: Double?
    var language: String?
  }
  var id: UUID
  var ordinal: Int
  var key, name: String
  var emoji: String?
  var block, state: String
  var budgetHoursPerWeek: Double?
  var removedAt: Millis?
  var attrs: Attrs

  init(_ line: Line, ordinal: Int, removedAt: Millis?) {
    id = line.id.uuid
    self.ordinal = ordinal
    key = line.key.rawValue
    name = line.name
    emoji = line.emoji
    block = line.block
    state = line.state.rawValue
    budgetHoursPerWeek = line.budgetHoursPerWeek
    self.removedAt = removedAt
    attrs = Attrs(
      parentLink: line.parentLink, tags: line.taskRules.tags, folders: line.taskRules.folders,
      projects: line.taskRules.projects, foundation: line.foundation ? true : nil,
      floorHoursPerDay: line.floorHoursPerDay, language: line.language)
  }

  func entity(refs: [ExternalRef]) throws -> Line {
    Line(
      id: LineID(uuid: id), refs: refs, key: LineKey(key), name: name, emoji: emoji,
      block: block, state: try decode(state, "line.state"),
      budgetHoursPerWeek: budgetHoursPerWeek, parentLink: attrs.parentLink,
      taskRules: LineTaskRules(
        tags: attrs.tags, folders: attrs.folders, projects: attrs.projects),
      foundation: attrs.foundation ?? false, floorHoursPerDay: attrs.floorHoursPerDay,
      language: attrs.language)
  }
}

struct NoteRecord: EntityRecord {
  static let databaseTableName = "note"
  struct Period: Codable, Equatable, Sendable {
    var scale: String
    var start, end: Millis
  }
  struct Attrs: Codable, Equatable, Sendable {
    var scale: String?
    var period: Period?
    var parentLink: String?
  }
  var id: UUID
  var ordinal: Int
  var path, title: String
  var type, status, lineKey: String?
  var removedAt: Millis?
  var attrs: Attrs

  init(_ note: NoteRef, ordinal: Int, removedAt: Millis?) {
    id = note.id.uuid
    self.ordinal = ordinal
    path = note.path
    title = note.title
    type = note.type
    status = note.status
    lineKey = note.lineKey?.rawValue
    self.removedAt = removedAt
    attrs = Attrs(
      scale: note.scale.map(Self.encode),
      period: note.period.map {
        Period(scale: Self.encode($0.scale), start: $0.start.millis, end: $0.end.millis)
      },
      parentLink: note.parentLink)
  }

  func entity(refs: [ExternalRef]) throws -> NoteRef {
    NoteRef(
      id: NoteID(uuid: id), refs: refs, path: path, title: title, type: type,
      scale: try attrs.scale.map(Self.decode),
      period: try attrs.period.map {
        Horizon(
          scale: try Self.decode($0.scale), start: Date(millis: $0.start),
          end: Date(millis: $0.end))
      },
      parentLink: attrs.parentLink, lineKey: lineKey.map { LineKey($0) }, status: status)
  }

  static func encode(_ scale: Scale) -> String {
    switch scale {
    case .years(let count): "years:\(count)"
    default: "\(scale)"
    }
  }

  static func decode(_ raw: String) throws -> Scale {
    let fixed: [String: Scale] = [
      "day": .day, "week": .week, "month": .month, "quarter": .quarter, "year": .year,
      "lifetime": .lifetime,
    ]
    if let scale = fixed[raw] { return scale }
    if raw.hasPrefix("years:"), let count = Int(raw.dropFirst("years:".count)) {
      return .years(count)
    }
    throw SQLiteStoreError.unknownValue(column: "note.scale")
  }
}

struct ArtifactRecord: EntityRecord {
  static let databaseTableName = "artifact"
  struct Attrs: Codable, Equatable, Sendable {
    var lineIds: [UUID]
  }
  var id: UUID
  var ordinal: Int
  var key, title, status: String
  var priority: Bool
  var noteId: UUID?
  var removedAt: Millis?
  var attrs: Attrs

  init(_ artifact: Artifact, ordinal: Int, removedAt: Millis?) {
    id = artifact.id.uuid
    self.ordinal = ordinal
    key = artifact.key
    title = artifact.title
    status = artifact.status.rawValue
    priority = artifact.priority
    noteId = artifact.noteID?.uuid
    self.removedAt = removedAt
    attrs = Attrs(lineIds: artifact.lineIDs.map(\.uuid))
  }

  func entity(refs: [ExternalRef]) throws -> Artifact {
    Artifact(
      id: ArtifactID(uuid: id), refs: refs, key: key, title: title,
      lineIDs: attrs.lineIds.map(LineID.init), status: try decode(status, "artifact.status"),
      priority: priority, noteID: noteId.map(NoteID.init))
  }
}

struct TagRecord: EntityRecord {
  static let databaseTableName = "tag"
  struct Attrs: Codable, Equatable, Sendable {}
  var id: UUID
  var ordinal: Int
  var name: String
  var parentId: UUID?
  var isMeta: Bool
  var removedAt: Millis?
  var attrs = Attrs()

  init(_ tag: Tag, ordinal: Int, removedAt: Millis?) {
    id = tag.id.uuid
    self.ordinal = ordinal
    name = tag.name
    parentId = tag.parentID?.uuid
    isMeta = tag.isMeta
    self.removedAt = removedAt
  }

  func entity(refs: [ExternalRef]) throws -> Tag {
    Tag(
      id: TagID(uuid: id), refs: refs, name: name, parentID: parentId.map(TagID.init),
      isMeta: isMeta)
  }
}

struct ProjectRecord: EntityRecord {
  static let databaseTableName = "project"
  struct Attrs: Codable, Equatable, Sendable {
    var tagIds: [UUID]
  }
  var id: UUID
  var ordinal: Int
  var title, status: String
  var lineId: UUID?
  var removedAt: Millis?
  var attrs: Attrs

  init(_ project: Project, ordinal: Int, removedAt: Millis?) {
    id = project.id.uuid
    self.ordinal = ordinal
    title = project.title
    status = project.status.rawValue
    lineId = project.line.lineId
    self.removedAt = removedAt
    attrs = Attrs(tagIds: project.tagIDs.map(\.uuid))
  }

  func entity(refs: [ExternalRef]) throws -> Project {
    Project(
      id: ProjectID(uuid: id), refs: refs, title: title,
      status: try decode(status, "project.status"), tagIDs: attrs.tagIds.map(TagID.init),
      line: LineAssignment(lineId: lineId))
  }
}

struct TaskRecord: EntityRecord {
  static let databaseTableName = "task"
  struct Attrs: Codable, Equatable, Sendable {
    var tagIds: [UUID]
  }
  var id: UUID
  var ordinal: Int
  var title: String
  var projectId, parentTaskId, lineId: UUID?
  var status: String
  var flagged: Bool
  var plannedAt, deferAt, dueAt: Millis?
  var effectivePlannedAt, effectiveDeferAt, effectiveDueAt: Millis?
  var estimateMinutes: Int?
  var completedAt, modifiedAt: Millis?
  var occurrenceOf: UUID?
  var removedAt: Millis?
  var attrs: Attrs

  init(_ task: TaskItem, ordinal: Int, removedAt: Millis?) {
    id = task.id.uuid
    self.ordinal = ordinal
    title = task.title
    projectId = task.projectID?.uuid
    parentTaskId = task.parentTaskID?.uuid
    lineId = task.line.lineId
    status = task.status.rawValue
    flagged = task.flagged
    plannedAt = task.plannedAt?.millis
    deferAt = task.deferUntil?.millis
    dueAt = task.dueAt?.millis
    effectivePlannedAt = task.effectivePlannedAt?.millis
    effectiveDeferAt = task.effectiveDeferUntil?.millis
    effectiveDueAt = task.effectiveDueAt?.millis
    estimateMinutes = task.estimateMinutes
    completedAt = task.completedAt?.millis
    modifiedAt = task.modifiedAt?.millis
    occurrenceOf = task.occurrenceOf?.uuid
    self.removedAt = removedAt
    attrs = Attrs(tagIds: task.tagIDs.map(\.uuid))
  }

  func entity(refs: [ExternalRef]) throws -> TaskItem {
    TaskItem(
      id: TaskItemID(uuid: id), refs: refs, title: title,
      projectID: projectId.map(ProjectID.init), parentTaskID: parentTaskId.map(TaskItemID.init),
      tagIDs: attrs.tagIds.map(TagID.init), status: try decode(status, "task.status"),
      flagged: flagged, plannedAt: plannedAt.map(Date.init(millis:)),
      deferUntil: deferAt.map(Date.init(millis:)), dueAt: dueAt.map(Date.init(millis:)),
      effectivePlannedAt: effectivePlannedAt.map(Date.init(millis:)),
      effectiveDeferUntil: effectiveDeferAt.map(Date.init(millis:)),
      effectiveDueAt: effectiveDueAt.map(Date.init(millis:)),
      estimateMinutes: estimateMinutes, completedAt: completedAt.map(Date.init(millis:)),
      modifiedAt: modifiedAt.map(Date.init(millis:)),
      occurrenceOf: occurrenceOf.map(TaskItemID.init),
      line: LineAssignment(lineId: lineId))
  }
}

/// The single `workspace` row: time zone as data, OmniFocus' default times and the issues of
/// the last import.
struct WorkspaceRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "workspace"
  static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
  static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

  enum Issue: Codable, Equatable {
    case ruleClaimedTwice(rule: String, kept: String, ignored: String)
    case unknownLineKey(key: String, in: String)
    case vault(path: String, line: Int?, kind: VaultProblem.Kind, key: String?)
    case vaultWide(kind: VaultProblem.Kind, key: String?)
    case defaultTimesNotRead
  }
  /// Minutes from midnight, read in the row's time zone. Absent from a row written before
  /// S4-3a.
  struct Times: Codable, Equatable {
    var due: Int?
    var `defer`: Int?
    var planned: Int?
  }
  struct Attrs: Codable, Equatable {
    var issues: [Issue]
    /// nil when every time is absent: one encoding for that state.
    var defaultTimes: Times?
  }
  var id = 1
  var timeZone: String
  var committedAt: Millis
  var version: Int
  var attrs: Attrs

  init(_ stored: StoredWorkspace, committedAt: Millis, version: Int) {
    timeZone = stored.timeZone.identifier
    self.committedAt = committedAt
    self.version = version
    attrs = Attrs(
      issues: stored.issues.map { issue in
        switch issue {
        case .ruleClaimedTwice(let rule, let kept, let ignored):
          .ruleClaimedTwice(rule: rule, kept: kept.rawValue, ignored: ignored.rawValue)
        case .unknownLineKey(let key, let artifact):
          .unknownLineKey(key: key.rawValue, in: artifact)
        case .vault(let path, let line, let problem):
          .vault(path: path, line: line, kind: problem.kind, key: problem.key)
        case .vaultWide(let problem):
          .vaultWide(kind: problem.kind, key: problem.key)
        case .defaultTimesNotRead: .defaultTimesNotRead
        }
      },
      defaultTimes: Self.times(stored.defaultTimeSettings))
  }

  private static func times(_ settings: DefaultTimeSettings) -> Times? {
    func minutes(_ time: TimeOfDay?) -> Int? { time.map { $0.hour * 60 + $0.minute } }
    let times = Times(
      due: minutes(settings.due), defer: minutes(settings.defer),
      planned: minutes(settings.planned))
    return times == Times() ? nil : times
  }

  /// Every stored minute is checked: one outside 0..<1440 throws, naming only its key.
  func defaultTimeSettings() throws -> DefaultTimeSettings {
    func time(_ minutes: Int?, _ key: String) throws -> TimeOfDay? {
      guard let minutes else { return nil }
      guard let time = TimeOfDay(hour: minutes / 60, minute: minutes % 60) else {
        throw SQLiteStoreError.outOfRange(column: "workspace.attrs.defaultTimes.\(key)")
      }
      return time
    }
    guard let times = attrs.defaultTimes else { return DefaultTimeSettings() }
    return DefaultTimeSettings(
      due: try time(times.due, "due"), defer: try time(times.defer, "defer"),
      planned: try time(times.planned, "planned"))
  }

  var issues: [ImportIssue] {
    attrs.issues.map { issue in
      switch issue {
      case .ruleClaimedTwice(let rule, let kept, let ignored):
        .ruleClaimedTwice(rule: rule, kept: LineKey(kept), ignored: LineKey(ignored))
      case .unknownLineKey(let key, let artifact):
        .unknownLineKey(LineKey(key), in: artifact)
      case .vault(let path, let line, let kind, let key):
        .vault(path: path, line: line, problem: VaultProblem(kind, key: key))
      case .vaultWide(let kind, let key):
        .vaultWide(VaultProblem(kind, key: key))
      case .defaultTimesNotRead: .defaultTimesNotRead
      }
    }
  }
}

/// A row of `imports`: one recorded import (ADR-0011). Durations in ms, NULL when not measured.
struct ImportRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "imports"
  static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
  static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
  static let committed = "committed"

  /// The row counts.
  struct Attrs: Codable, Equatable {
    var lines: Int
    var notes: Int
    var artifacts: Int
    var projects: Int
    var tasks: Int
    var tags: Int
  }
  var id: Int64?
  var trigger: String
  var startedAt: Millis
  var finishedAt: Millis
  var waitedMs: Int64?
  var durationMs: Int64?
  var heldMs: Int64?
  var outcome: String
  var attrs: Attrs

  init(_ run: ImportRun) {
    let counts: ImportCounts
    switch run.outcome {
    case .committed(let committed): counts = committed
    }
    trigger = run.trigger.rawValue
    startedAt = run.startedAt.millis
    finishedAt = run.finishedAt.millis
    waitedMs = run.waited.map(Self.millis)
    durationMs = run.duration.map(Self.millis)
    heldMs = run.providerHeld.map(Self.millis)
    outcome = Self.committed
    attrs = Attrs(
      lines: counts.lines, notes: counts.notes, artifacts: counts.artifacts,
      projects: counts.projects, tasks: counts.tasks, tags: counts.tags)
  }

  private static func millis(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
  }

  /// Every column is checked: an unknown text, a negative number or an end before the start
  /// throws, naming only its column. An instant is not checked against the clock: a future end
  /// cannot be told from a clock set back, and the status bar reads both as just now.
  func run() throws -> ImportRun {
    func duration(_ ms: Int64?, _ column: String) throws -> Duration? {
      guard let ms else { return nil }
      guard ms >= 0 else { throw SQLiteStoreError.outOfRange(column: "imports.\(column)") }
      return .milliseconds(ms)
    }
    guard outcome == Self.committed else {
      throw SQLiteStoreError.unknownValue(column: "imports.outcome")
    }
    let counts = [
      attrs.lines, attrs.notes, attrs.artifacts, attrs.projects, attrs.tasks, attrs.tags,
    ]
    guard counts.allSatisfy({ $0 >= 0 }) else {
      throw SQLiteStoreError.outOfRange(column: "imports.attrs")
    }
    guard finishedAt >= startedAt else {
      throw SQLiteStoreError.outOfRange(column: "imports.finished_at")
    }
    return ImportRun(
      trigger: try decode(trigger, "imports.trigger"), startedAt: Date(millis: startedAt),
      finishedAt: Date(millis: finishedAt), waited: try duration(waitedMs, "waited_ms"),
      duration: try duration(durationMs, "duration_ms"),
      providerHeld: try duration(heldMs, "held_ms"),
      outcome: .committed(
        ImportCounts(
          lines: attrs.lines, notes: attrs.notes, artifacts: attrs.artifacts,
          projects: attrs.projects, tasks: attrs.tasks, tags: attrs.tags)))
  }
}
