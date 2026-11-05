import Foundation
import GRDB
import MoonShineCore

/// The local store on SQLite (ADR-0002). A commit is one transaction: the version is checked
/// (optimistic concurrency), the identity map is upserted by `ExternalRef`, the import is
/// merged by Core's retention rule, and only rows that changed are written, each with an
/// entry in the append-only `changes` log.
public struct SQLiteStore: Store {
  let writer: any DatabaseWriter
  let fallbackTimeZone: TimeZone

  /// A database file in WAL mode, so views keep reading while an import writes.
  public init(path: String, timeZone: TimeZone = .current) throws {
    try self.init(writer: DatabasePool(path: path), timeZone: timeZone)
  }

  /// An in-memory database, for tests and previews.
  public init(timeZone: TimeZone = .current) throws {
    try self.init(writer: DatabaseQueue(), timeZone: timeZone)
  }

  init(writer: any DatabaseWriter, timeZone: TimeZone) throws {
    self.writer = writer
    fallbackTimeZone = timeZone
    try Self.migrator.migrate(writer)
  }

  public func identityMap() async throws -> VersionedIdentityMap {
    try await writer.read { db in
      var entries: [IdentityMap.Key: UUID] = [:]
      let rows = try Row.fetchCursor(
        db, sql: "SELECT kind, provider, external_id, entity_id FROM external_ref")
      while let row = try rows.next() {
        let key = IdentityMap.Key(
          kind: row["kind"], provider: ProviderID(rawValue: row["provider"]),
          externalId: row["external_id"])
        entries[key] = row["entity_id"]
      }
      return VersionedIdentityMap(
        map: IdentityMap(entries: entries), version: try WorkspaceRecord.fetchOne(db)?.version ?? 0)
    }
  }

  public func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
    run: PendingImportRun?
  ) async throws {
    let fallback = fallbackTimeZone
    try await writer.write { db in
      let version = try WorkspaceRecord.fetchOne(db)?.version ?? 0
      guard version == expectedVersion else {
        throw IdentityConflict(expectedVersion: expectedVersion, actualVersion: version)
      }
      try Self.saveIdentities(identities, seenIn: workspace, db)
      let merged = try Self.load(db, includeRemoved: true, fallback: fallback)
        .merging(workspace, at: now)
      let at = now.millis
      try Self.sync(merged.lines, as: LineRecord.self, db, at: at)
      try Self.sync(merged.notes, as: NoteRecord.self, db, at: at)
      try Self.sync(merged.artifacts, as: ArtifactRecord.self, db, at: at)
      try Self.sync(merged.tags, as: TagRecord.self, db, at: at)
      try Self.sync(merged.projects, as: ProjectRecord.self, db, at: at)
      try Self.sync(merged.tasks, as: TaskRecord.self, db, at: at)
      try WorkspaceRecord(merged, committedAt: at, version: version + 1).save(db)
      // Read the clocks last: only this insert and the transaction's commit fall outside.
      if let run { try ImportRecord(run.finished()).insert(db) }
    }
  }

  public func lastCommittedImport() async throws -> ImportRun? {
    try await writer.read { db in
      try ImportRecord.filter(Column("outcome") == ImportRecord.committed)
        .order(Column("id").desc).fetchOne(db)?.run()
    }
  }

  public func workspace() async throws -> Workspace {
    let fallback = fallbackTimeZone
    return try await writer.read { db in
      try Self.load(db, includeRemoved: false, fallback: fallback).workspace
    }
  }

  public func stored() async throws -> StoredWorkspace {
    let fallback = fallbackTimeZone
    return try await writer.read { db in
      try Self.load(db, includeRemoved: true, fallback: fallback)
    }
  }

  // MARK: - Tested query functions

  static func load(_ db: Database, includeRemoved: Bool, fallback: TimeZone) throws
    -> StoredWorkspace
  {
    let refs = try entityRefs(db)
    func rows<Record: EntityRecord>(_: Record.Type) throws -> [Stored<Record.Entity>] {
      var request = Record.order(Column("ordinal"))
      if !includeRemoved { request = request.filter(Column("removed_at") == nil) }
      return try request.fetchAll(db).map { try $0.stored(refs: refs) }
    }
    let record = try WorkspaceRecord.fetchOne(db)
    return StoredWorkspace(
      timeZone: record.flatMap { TimeZone(identifier: $0.timeZone) } ?? fallback,
      defaultTimeSettings: try record?.defaultTimeSettings() ?? DefaultTimeSettings(),
      lines: try rows(LineRecord.self), artifacts: try rows(ArtifactRecord.self),
      notes: try rows(NoteRecord.self), projects: try rows(ProjectRecord.self),
      tasks: try rows(TaskRecord.self), tags: try rows(TagRecord.self),
      issues: record?.issues ?? [])
  }

  /// The refs entities carry (those with `last_seen`), grouped by MoonShine id.
  static func entityRefs(_ db: Database) throws -> [UUID: [ExternalRef]] {
    var refs: [UUID: [ExternalRef]] = [:]
    let rows = try Row.fetchCursor(
      db,
      sql: """
        SELECT entity_id, provider, external_id, last_seen FROM external_ref
        WHERE last_seen IS NOT NULL ORDER BY provider, external_id
        """)
    while let row = try rows.next() {
      let ref = ExternalRef(
        provider: ProviderID(rawValue: row["provider"]), externalId: row["external_id"],
        lastSeen: Date(millis: row["last_seen"]))
      refs[row["entity_id"], default: []].append(ref)
    }
    return refs
  }

  /// Upserts by `ExternalRef`: every identity-map entry, then `last_seen` of every ref the
  /// imported entities carry. The identity table is kind-scoped, like `IdentityMap`.
  static func saveIdentities(_ identities: IdentityMap, seenIn workspace: Workspace, _ db: Database)
    throws
  {
    let entry = try db.cachedStatement(
      sql: """
        INSERT INTO external_ref (kind, provider, external_id, entity_id) VALUES (?, ?, ?, ?)
        ON CONFLICT (kind, provider, external_id) DO UPDATE SET entity_id = excluded.entity_id
        """)
    for (key, uuid) in identities.entries {
      try entry.execute(arguments: [key.kind, key.provider.rawValue, key.externalId, uuid])
    }
    let seen = try db.cachedStatement(
      sql: """
        INSERT INTO external_ref (kind, provider, external_id, entity_id, last_seen)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (kind, provider, external_id)
        DO UPDATE SET entity_id = excluded.entity_id, last_seen = excluded.last_seen
        """)
    func markSeen<Entity: Identifiable>(_ entities: [Entity], refs: (Entity) -> [ExternalRef])
      throws where Entity: KindedEntity, Entity.ID == EntityID<Entity>
    {
      let kind = Entity.kind.rawValue
      for entity in entities {
        for ref in refs(entity) {
          try seen.execute(arguments: [
            kind, ref.provider.rawValue, ref.externalId, entity.id.uuid, ref.lastSeen.millis,
          ])
        }
      }
    }
    try markSeen(workspace.lines, refs: \.refs)
    try markSeen(workspace.notes, refs: \.refs)
    try markSeen(workspace.artifacts, refs: \.refs)
    try markSeen(workspace.tags, refs: \.refs)
    try markSeen(workspace.projects, refs: \.refs)
    try markSeen(workspace.tasks, refs: \.refs)
  }

  /// Writes only rows that differ. Logs `insert` for new rows, `delete` when `removed_at` gets
  /// set, `update` for any other change; a pure reorder (`ordinal` only) is written, not logged.
  static func sync<Record: EntityRecord>(
    _ stored: [Stored<Record.Entity>], as _: Record.Type, _ db: Database, at: Millis
  ) throws {
    let existing = Dictionary(
      try Record.fetchAll(db).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let log = try db.cachedStatement(
      sql: "INSERT INTO changes (at, entity_kind, entity_id, op) VALUES (?, ?, ?, ?)")
    for (ordinal, item) in stored.enumerated() {
      let record = Record(item, ordinal: ordinal)
      let op: String?
      if var previous = existing[record.id] {
        guard previous != record else { continue }
        try record.update(db)
        let wasRemoved = previous.removedAt != nil
        previous.ordinal = ordinal
        op =
          previous == record ? nil : !wasRemoved && record.removedAt != nil ? "delete" : "update"
      } else {
        try record.insert(db)
        op = "insert"
      }
      if let op {
        try log.execute(arguments: [at, Record.databaseTableName, record.id, op])
      }
    }
  }
}
