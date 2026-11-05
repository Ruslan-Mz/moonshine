import GRDB

extension SQLiteStore {
  /// Numbered migrations; a shipped migration is never edited, only followed by a new one.
  /// Instants are INTEGER Unix milliseconds (UTC); the workspace time zone is a column.
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "workspace") { t in
        t.primaryKey("id", .integer)
        t.column("time_zone", .text).notNull()
        t.column("committed_at", .integer).notNull()
        // Optimistic concurrency: +1 per commit; a commit names the version it was built on.
        t.column("version", .integer).notNull()
        t.column("attrs", .jsonText).notNull()
      }
      // The identity map: one MoonShine id per provider ref. `last_seen` is set for refs an
      // entity carries, null for ids allocated only for a reference.
      try db.create(table: "external_ref") { t in
        t.column("kind", .text).notNull()
        t.column("provider", .text).notNull()
        t.column("external_id", .text).notNull()
        t.column("entity_id", .blob).notNull().indexed()
        t.column("last_seen", .integer)
        t.primaryKey(["kind", "provider", "external_id"])
      }

      func entityTable(_ name: String, columns: (TableDefinition) -> Void) throws {
        try db.create(table: name) { t in
          t.primaryKey("id", .blob)
          t.column("ordinal", .integer).notNull()
          columns(t)
          t.column("removed_at", .integer)
          t.column("attrs", .jsonText).notNull()
        }
      }
      try entityTable("line") { t in
        t.column("key", .text).notNull()
        t.column("name", .text).notNull()
        t.column("emoji", .text)
        t.column("block", .text).notNull()
        t.column("state", .text).notNull()
        t.column("budget_hours_per_week", .double)
      }
      try entityTable("note") { t in
        t.column("path", .text).notNull()
        t.column("title", .text).notNull()
        t.column("type", .text)
        t.column("status", .text)
        t.column("line_key", .text)
      }
      try entityTable("artifact") { t in
        t.column("key", .text).notNull()
        t.column("title", .text).notNull()
        t.column("status", .text).notNull()
        t.column("priority", .boolean).notNull()
        t.column("note_id", .blob)
      }
      try entityTable("tag") { t in
        t.column("name", .text).notNull()
        t.column("parent_id", .blob)
        t.column("is_meta", .boolean).notNull()
      }
      try entityTable("project") { t in
        t.column("title", .text).notNull()
        t.column("status", .text).notNull()
        t.column("line_id", .blob)
      }
      // `line_id` null = Life ops. Effective dates arrive with the live bridge (S3).
      try entityTable("task") { t in
        t.column("title", .text).notNull()
        t.column("project_id", .blob).indexed()
        t.column("parent_task_id", .blob)
        t.column("line_id", .blob).indexed()
        t.column("status", .text).notNull().indexed()
        t.column("flagged", .boolean).notNull()
        t.column("planned_at", .integer)
        t.column("defer_at", .integer)
        t.column("due_at", .integer)
        t.column("effective_planned_at", .integer)
        t.column("effective_defer_at", .integer)
        t.column("effective_due_at", .integer)
        t.column("estimate_minutes", .integer)
        t.column("completed_at", .integer).indexed()
        t.column("modified_at", .integer)
        t.column("occurrence_of", .blob)
      }

      try db.create(table: "changes") { t in
        t.autoIncrementedPrimaryKey("seq")
        t.column("at", .integer).notNull()
        t.column("entity_kind", .text).notNull()
        t.column("entity_id", .blob).notNull()
        t.column("op", .text).notNull()
      }
      for event in ["UPDATE", "DELETE"] {
        try db.execute(
          sql: """
            CREATE TRIGGER changes_append_only_\(event.lowercased()) BEFORE \(event) ON changes
            BEGIN SELECT RAISE(ABORT, 'changes is append-only'); END
            """)
      }
    }
    // Identity kinds were Swift type names; they are the written `EntityKind` names now, so
    // renaming a type can no longer orphan an identity. In place: only `kind` changes, every
    // MoonShine id stays. A row of any other kind is left as it is.
    migrator.registerMigration("v2") { db in
      let renamed = [
        ("Line", "line"), ("NoteRef", "note"), ("Artifact", "artifact"), ("Tag", "tag"),
        ("Project", "project"), ("TaskItem", "task"),
      ]
      for (old, new) in renamed {
        try db.execute(
          sql: "UPDATE external_ref SET kind = ? WHERE kind = ?", arguments: [new, old])
      }
    }
    // One row per recorded import (ADR-0011): times in ms, a duration NULL when it could not be
    // measured. `outcome` is `committed` until failed attempts are recorded too (S4-4c).
    migrator.registerMigration("v3") { db in
      try db.create(table: "imports") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("trigger", .text).notNull()
        t.column("started_at", .integer).notNull()
        t.column("finished_at", .integer).notNull()
        t.column("waited_ms", .integer)
        t.column("duration_ms", .integer)
        t.column("held_ms", .integer)
        t.column("outcome", .text).notNull()
        t.column("attrs", .jsonText).notNull()
      }
    }
    return migrator
  }
}
