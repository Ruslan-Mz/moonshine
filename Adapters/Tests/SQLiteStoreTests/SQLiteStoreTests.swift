import Foundation
import GRDB
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import SQLiteStore

@Suite struct SQLiteStoreTests {
  let first = Date(timeIntervalSince1970: 1_790_000_000)
  let second = Date(timeIntervalSince1970: 1_790_604_800)
  let third = Date(timeIntervalSince1970: 1_791_209_600)

  struct Change: Equatable {
    let kind: String
    let op: String
  }

  func changes(in store: SQLiteStore, after seq: Int = 0) async throws -> [Change] {
    try await store.writer.read { db in
      try Row.fetchAll(
        db, sql: "SELECT entity_kind, op FROM changes WHERE seq > ? ORDER BY seq",
        arguments: [seq]
      ).map { Change(kind: $0["entity_kind"], op: $0["op"]) }
    }
  }

  func lastSeq(in store: SQLiteStore) async throws -> Int {
    try await store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM changes") ?? 0
    }
  }

  func run(_ source: TaskSourceSnapshot, _ store: SQLiteStore, at now: Date) async throws {
    try await ImportService(
      tasks: FixedTaskProvider(source: source), notes: DemoVault(), store: store
    ).run(now: now)
  }

  @Test func vaultIssuesRoundTripWithTheirKindKeyAndLine() async throws {
    let issues: [ImportIssue] = [
      .vault(path: "Notes/a.md", line: 3, problem: VaultProblem(.malformedYAML)),
      .vault(path: "Notes/b.md", line: nil, problem: VaultProblem(.unreadable, key: "lines[2]")),
      .vaultWide(VaultProblem(.budgetNoteMissing)),
    ]
    let store = try SQLiteStore(path: temporaryDatabasePath())
    try await store.commit(
      Workspace(timeZone: .gmt, issues: issues), identities: IdentityMap(), expectedVersion: 0,
      at: first)
    #expect(try await store.workspace().issues == issues)
  }

  @Test func defaultTimesSurviveClosingAndReopeningTheFile() async throws {
    let path = temporaryDatabasePath()
    let times = DefaultTimeSettings(
      due: TimeOfDay(hour: 17, minute: 0), planned: TimeOfDay(hour: 9, minute: 30))
    try await SQLiteStore(path: path).commit(
      Workspace(timeZone: .gmt, defaultTimeSettings: times), identities: IdentityMap(),
      expectedVersion: 0, at: first)
    #expect(try await SQLiteStore(path: path).workspace().defaultTimeSettings == times)
  }

  @Test func allAbsentDefaultTimesHaveOneEncoding() throws {
    let record = WorkspaceRecord(
      StoredWorkspace(timeZone: .gmt, defaultTimeSettings: DefaultTimeSettings()),
      committedAt: 0, version: 1)
    #expect(record.attrs.defaultTimes == nil)
    let set = WorkspaceRecord(
      StoredWorkspace(
        timeZone: .gmt, defaultTimeSettings: DefaultTimeSettings(due: TimeOfDay(hour: 0, minute: 0))
      ), committedAt: 0, version: 1)
    #expect(set.attrs.defaultTimes == WorkspaceRecord.Times(due: 0))
  }

  @Test func aWorkspaceRowFromBeforeDefaultTimesReadsWithAllAbsent() throws {
    let attrs = Data(#"{"issues":[]}"#.utf8)
    var record = WorkspaceRecord(StoredWorkspace(timeZone: .gmt), committedAt: 0, version: 1)
    record.attrs = try JSONDecoder().decode(WorkspaceRecord.Attrs.self, from: attrs)
    #expect(try record.defaultTimeSettings() == DefaultTimeSettings())
  }

  @Test func aStoredMinuteOutOfRangeThrowsNamingOnlyItsKey() throws {
    var record = WorkspaceRecord(StoredWorkspace(timeZone: .gmt), committedAt: 0, version: 1)
    record.attrs.defaultTimes = WorkspaceRecord.Times(due: 1439, planned: 0)
    #expect(
      try record.defaultTimeSettings()
        == DefaultTimeSettings(
          due: TimeOfDay(hour: 23, minute: 59), planned: TimeOfDay(hour: 0, minute: 0)))
    for (times, key) in [
      (WorkspaceRecord.Times(due: 1440), "due"), (WorkspaceRecord.Times(defer: -1), "defer"),
      (WorkspaceRecord.Times(planned: Int.max), "planned"),
    ] {
      record.attrs.defaultTimes = times
      #expect(
        throws: SQLiteStoreError.outOfRange(column: "workspace.attrs.defaultTimes.\(key)")
      ) { try record.defaultTimeSettings() }
    }
  }

  @Test func anUnknownStoredValueThrowsNamingOnlyItsColumn() throws {
    let planted = "planted-secret-7f3a"
    let errors: [(any Error)?] = [
      #expect(throws: SQLiteStoreError.self) { let _: LineState = try decode(planted, "line.state") },
      #expect(throws: SQLiteStoreError.self) { try NoteRecord.decode(planted) },
    ]
    for (error, column) in zip(errors, ["line.state", "note.scale"]) {
      let error = try #require(error as? SQLiteStoreError)
      #expect(error == .unknownValue(column: column))
      #expect(!String(describing: error).contains(planted))
      #expect(!String(reflecting: error).contains(planted))
    }
  }

  @Test func aLineStoredBeforeTheVersionPointTwoKeysReadsWithoutThem() throws {
    let attrs = Data(#"{"parentLink":null,"tags":["a"],"folders":[],"projects":[]}"#.utf8)
    let decoded = try JSONDecoder().decode(LineRecord.Attrs.self, from: attrs)
    let stored = Line(
      id: LineID(uuid: UUID()), refs: [], key: "a", name: "A", emoji: nil, block: "B",
      state: .active, budgetHoursPerWeek: nil, parentLink: nil, taskRules: LineTaskRules(),
      foundation: true, floorHoursPerDay: 1, language: "de")
    var record = LineRecord(stored, ordinal: 0, removedAt: nil)
    record.attrs = decoded
    let line = try record.entity(refs: [])
    #expect(!line.foundation && line.floorHoursPerDay == nil && line.language == nil)
    #expect(line.taskRules.tags == ["a"])
  }

  @Test func migratesAnEmptyDatabaseOnceWithEveryTableAndEffectiveDateColumns() async throws {
    let path = temporaryDatabasePath()
    let store = try SQLiteStore(path: path)
    try await store.writer.read { db in
      #expect(try SQLiteStore.migrator.appliedIdentifiers(db) == ["v1", "v2"])
      for table in [
        "workspace", "external_ref", "line", "artifact", "note", "tag", "project", "task",
        "changes",
      ] {
        #expect(try db.tableExists(table), "\(table)")
      }
      let columns = try db.columns(in: "task").map(\.name)
      for column in [
        "effective_planned_at", "effective_defer_at", "effective_due_at", "removed_at", "attrs",
      ] {
        #expect(columns.contains(column), "\(column)")
      }
    }
    let reopened = try SQLiteStore(path: path)
    let (applied, completed) = try await reopened.writer.read { db in
      (
        try SQLiteStore.migrator.appliedIdentifiers(db),
        try SQLiteStore.migrator.hasCompletedMigrations(db)
      )
    }
    #expect(applied == ["v1", "v2"])
    #expect(completed)
  }

  /// `v2`: the identity kinds were Swift type names; they become the written `EntityKind`
  /// names in place, and every MoonShine id stays.
  @Test func migrationTwoRenamesTheStoredIdentityKindsAndKeepsEveryId() async throws {
    let queue = try DatabaseQueue()
    try SQLiteStore.migrator.migrate(queue, upTo: "v1")
    // A project and its root task share one external id, as in OmniFocus.
    let old = [
      ("Line", "obsidian", "violin"), ("NoteRef", "obsidian", "Years/A.md"),
      ("Artifact", "obsidian", "a1"), ("Tag", "omnifocus", "t1"), ("Project", "omnifocus", "p1"),
      ("TaskItem", "omnifocus", "p1"), ("Other", "omnifocus", "p1"),
    ]
    let ids = old.map { _ in UUID() }
    try await queue.write { db in
      for ((kind, provider, externalId), id) in zip(old, ids) {
        try db.execute(
          sql: """
            INSERT INTO external_ref (kind, provider, external_id, entity_id, last_seen)
            VALUES (?, ?, ?, ?, 7)
            """, arguments: [kind, provider, externalId, id])
      }
    }
    let store = try SQLiteStore(writer: queue, timeZone: .gmt)
    let (kinds, entityIDs, seen) = try await queue.read { db in
      let rows = try Row.fetchAll(
        db, sql: "SELECT kind, entity_id, last_seen FROM external_ref ORDER BY rowid")
      return (
        rows.map { $0["kind"] as String }, rows.map { $0["entity_id"] as UUID },
        rows.map { $0["last_seen"] as Int }
      )
    }
    #expect(kinds == ["line", "note", "artifact", "tag", "project", "task", "Other"])
    #expect(entityIDs == ids)
    #expect(seen.allSatisfy { $0 == 7 })

    // The migrated identities are the ones an import finds.
    var identities = try await store.identityMap()
    let now = Date(timeIntervalSince1970: 0)
    let ref = ExternalRef(provider: .omnifocus, externalId: "p1", lastSeen: now)
    let project: ProjectID = identities.map.id(for: ref, now: now)
    let task: TaskItemID = identities.map.id(for: ref, now: now)
    #expect(project.uuid == ids[4] && task.uuid == ids[5])
  }

  @Test func anImportStoresOnlyTheWrittenKindNames() async throws {
    let store = try SQLiteStore()
    try await ImportService(
      tasks: FixedTaskProvider(source: try fixtureSnapshot()), notes: DemoVault(), store: store
    ).run(now: first)
    let kinds = try await store.writer.read { db in
      try String.fetchSet(db, sql: "SELECT DISTINCT kind FROM external_ref")
    }
    #expect(kinds == ["line", "note", "artifact", "tag", "project", "task"])
  }

  @Test func workspaceSurvivesClosingAndReopeningTheFile() async throws {
    let path = temporaryDatabasePath()
    let committed = try await ImportService(
      tasks: FixedTaskProvider(source: try fixtureSnapshot()), notes: DemoVault(),
      store: try SQLiteStore(path: path)
    ).run(now: first)
    expectSame(try await SQLiteStore(path: path).workspace(), committed)
  }

  @Test func changeLogRecordsInsertsUpdatesAndDeletesButNotUnchangedRows() async throws {
    let store = try SQLiteStore()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    let done = try #require(source.tasks.first { $0.status == .completed })

    try await run(source, store, at: first)
    let inserted = try await changes(in: store)
    let workspace = try await store.workspace()
    let entityCount =
      workspace.lines.count + workspace.artifacts.count + workspace.notes.count
      + workspace.projects.count + workspace.tasks.count + workspace.tags.count
    #expect(inserted.count == entityCount)
    #expect(inserted.allSatisfy { $0.op == "insert" })

    var seq = try await lastSeq(in: store)
    try await run(source, store, at: second)
    #expect(try await changes(in: store, after: seq).isEmpty)

    try await run(source.renaming(open.externalId, to: "Renamed"), store, at: second)
    #expect(try await changes(in: store, after: seq) == [Change(kind: "task", op: "update")])

    seq = try await lastSeq(in: store)
    try await run(source.dropping(open.externalId), store, at: third)
    #expect(try await changes(in: store, after: seq) == [Change(kind: "task", op: "delete")])

    seq = try await lastSeq(in: store)
    try await run(source, store, at: third)
    #expect(try await changes(in: store, after: seq) == [Change(kind: "task", op: "update")])

    seq = try await lastSeq(in: store)
    try await run(source.dropping(done.externalId), store, at: third)
    #expect(try await changes(in: store, after: seq).isEmpty)
  }

  @Test func softDeletedRowStaysInTheDatabaseWithRemovedAt() async throws {
    let store = try SQLiteStore()
    let source = try fixtureSnapshot()
    let open = try source.plainOpenTask()
    try await run(source, store, at: first)
    try await run(source.dropping(open.externalId), store, at: second)

    let removed = try await store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE removed_at IS NOT NULL")
    }
    #expect(removed == 1)
  }

  @Test func changesTableIsAppendOnly() async throws {
    let store = try SQLiteStore()
    try await run(try fixtureSnapshot(), store, at: first)
    let (exists, before) = try await store.writer.read { db in
      (try db.tableExists("changes"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM changes"))
    }
    #expect(exists)

    try await store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO changes (at, entity_kind, entity_id, op) VALUES (0, 'task', x'00', 'insert')"
      )
    }
    let afterInsert = try await store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM changes")
    }
    #expect(afterInsert == before.map { $0 + 1 })

    for sql in ["UPDATE changes SET op = 'x'", "DELETE FROM changes"] {
      let error = await #expect(throws: DatabaseError.self, "\(sql)") {
        try await store.writer.write { db in try db.execute(sql: sql) }
      }
      #expect(error?.resultCode == .SQLITE_CONSTRAINT, "\(sql)")
      #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_TRIGGER, "\(sql)")
      #expect(error?.message == "changes is append-only", "\(sql)")
    }
    let afterAttempts = try await store.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM changes")
    }
    #expect(afterAttempts == afterInsert)
  }

  /// The fixture ×20 (~3k tasks) committed to a file in one transaction. Logged target < 1 s;
  /// the assertion is a 3 s regression guard so slower CI runners do not flake.
  @Test func bulkImportOfTheFixtureTimesTwentyInOneTransaction() async throws {
    let source = try fixtureSnapshot().scaled(20)
    let vault = try await DemoVault().vault()
    let store = try SQLiteStore(path: temporaryDatabasePath())
    let clock = ContinuousClock()

    var identities = IdentityMap()
    var workspace = Workspace(timeZone: .gmt)
    let build = clock.measure {
      workspace = Importer().makeWorkspace(
        tasks: source, vault: vault, stored: Workspace(timeZone: .gmt), identities: &identities,
        now: first)
    }
    let commit = try await clock.measure {
      try await store.commit(workspace, identities: identities, expectedVersion: 0, at: first)
    }
    let recommit = try await clock.measure {
      try await store.commit(workspace, identities: identities, expectedVersion: 1, at: second)
    }
    var read = Workspace(timeZone: .gmt)
    let readTime = try await clock.measure { read = try await store.workspace() }

    print(
      "S2 bulk ×20: \(workspace.tasks.count) tasks, \(workspace.projects.count) projects,"
        + " \(workspace.tags.count) tags · build \(build) · commit \(commit)"
        + " · re-commit \(recommit) · read \(readTime)")
    #expect(workspace.tasks.count == source.tasks.count)
    #expect(read.tasks.count == workspace.tasks.count)
    #expect(commit < .seconds(3))
  }
}
