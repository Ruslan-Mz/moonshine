import Foundation

/// Turns provider snapshots into a `Workspace`: assigns MoonShine ids, resolves references,
/// maps lines and marks repeat occurrences. Pure; the store persists the result.
public struct Importer: Sendable {
  /// Top-level tag groups whose children are task attributes, not lines (snapshot-contract).
  public static let defaultMetaTagGroups: Set<String> = [
    "Тип работы", "Контекст", "Время", "Энергия", "Цикл", "Локация",
  ]

  public let metaTagGroups: Set<String>

  public init(metaTagGroups: Set<String> = Importer.defaultMetaTagGroups) {
    self.metaTagGroups = metaTagGroups
  }

  /// `stored` is what the store holds now, in stored order. Its lines stand in for the lines
  /// the vault could not read (`VaultLines`), and its notes and artifacts for those the read
  /// saw and could not use (`VaultUnread`), so an unclean read never drops anything. No
  /// default: leaving it out would drop every stored line, note and artifact.
  public func makeWorkspace(
    tasks source: TaskSourceSnapshot, vault: VaultSnapshot, stored: Workspace,
    identities: inout IdentityMap, now: Date
  ) -> Workspace {
    func ref(_ provider: ProviderID, _ externalId: String) -> ExternalRef {
      ExternalRef(provider: provider, externalId: externalId, lastSeen: now)
    }
    func taskRef(_ externalId: String) -> ExternalRef { ref(source.provider, externalId) }
    var issues = vault.issues

    // Vault: notes, lines, artifacts.
    let readNotes = vault.notes.map { note in
      NoteRef(
        id: identities.id(for: ref(.obsidian, note.path), now: now),
        refs: [ref(.obsidian, note.path)], path: note.path, title: note.title, type: note.type,
        scale: note.scale, period: note.period, parentLink: note.parentLink,
        lineKey: note.lineKey, status: note.status)
    }
    // A stored note leaves only when its file is gone. One the read saw and could not use
    // stays as it was: unread (the reader has reported why) or no longer recognised (reported
    // here, since only the store knows it was a note).
    let readNoteIDs = Set(readNotes.map(\.id))
    var carriedNotes: [NoteRef] = []
    for note in stored.notes where !readNoteIDs.contains(note.id) {
      if !vault.isRead || vault.unread.covers(note.path) {
        carriedNotes.append(note)
      } else if vault.unread.notRecognised.contains(note.path) {
        carriedNotes.append(note)
        issues.append(
          .vault(path: note.path, line: nil, problem: VaultProblem(.noteNotRecognised)))
      }
    }
    let notes =
      carriedNotes.isEmpty ? readNotes : (readNotes + carriedNotes).sorted { $0.path < $1.path }
    let read = vault.lines.read.map { line in
      Line(
        id: identities.id(for: ref(.obsidian, line.key.rawValue), now: now),
        refs: [ref(.obsidian, line.key.rawValue)], key: line.key, name: line.name,
        emoji: line.emoji, block: line.block, state: line.state,
        budgetHoursPerWeek: line.budgetHoursPerWeek, parentLink: line.parentLink,
        taskRules: line.taskRules, foundation: line.foundation,
        floorHoursPerDay: line.floorHoursPerDay, language: line.language)
    }
    // Only a clean read may drop a line, and it takes the order from the note. Otherwise every
    // stored line keeps its position (updated when read, as it was when not, so it still maps
    // tasks and the merge never soft-deletes it); lines new to the store follow in note order.
    let readByID = Dictionary(read.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let storedLines = stored.lines
    let storedIDs = Set(storedLines.map(\.id))
    let lines =
      vault.lines.isComplete
      ? read
      : storedLines.map { readByID[$0.id] ?? $0 } + read.filter { !storedIDs.contains($0.id) }
    let lineByKey = Dictionary(
      lines.map { ($0.key, $0.id) }, uniquingKeysWith: { first, _ in first })
    let noteByPath = Dictionary(
      notes.map { ($0.path, $0.id) }, uniquingKeysWith: { first, _ in first })
    let readArtifacts = vault.artifacts.map { artifact in
      for key in artifact.lineKeys where lineByKey[key] == nil {
        issues.append(.unknownLineKey(key, in: artifact.key))
      }
      // One identity per appearance: an artifact carried into a later period keeps its key.
      let appearance = ref(.obsidian, "\(artifact.key)@\(artifact.periodKey)")
      return Artifact(
        id: identities.id(for: appearance, now: now), refs: [appearance], key: artifact.key,
        title: artifact.title, lineIDs: artifact.lineKeys.compactMap { lineByKey[$0] },
        status: artifact.status, priority: artifact.priority,
        noteID: noteByPath[artifact.notePath])
    }
    let artifacts = Self.artifacts(
      read: readArtifacts, stored: stored, notes: notes, carriedNotes: carriedNotes, vault: vault)

    // Tags: meta = a group from `metaTagGroups` or any tag under one.
    let sourceTags = Dictionary(
      source.tags.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
    func isMeta(_ tag: SourceTag) -> Bool {
      var current: SourceTag? = tag
      while let tag = current {
        if tag.parentExternalId == nil && metaTagGroups.contains(tag.name) { return true }
        current = tag.parentExternalId.flatMap { sourceTags[$0] }
      }
      return false
    }
    let tags = source.tags.map { tag in
      Tag(
        id: identities.id(for: taskRef(tag.externalId), now: now),
        refs: [taskRef(tag.externalId)], name: tag.name,
        parentID: tag.parentExternalId.map { identities.id(for: taskRef($0), now: now) },
        isMeta: isMeta(tag))
    }
    func lineTagNames(_ externalIds: [String]) -> [String] {
      externalIds.compactMap { sourceTags[$0] }.filter { !isMeta($0) }.map(\.name)
    }

    // Projects and tasks.
    let mapper = LineMapper(lines: lines)
    issues += mapper.issues
    var contexts: [String: ProjectContext] = [:]
    let projects = source.projects.map { project in
      let context = ProjectContext(
        name: project.name, tagNames: lineTagNames(project.tagExternalIds),
        topLevelFolder: project.folderPath.first)
      contexts[project.externalId] = context
      return Project(
        id: identities.id(for: taskRef(project.externalId), now: now),
        refs: [taskRef(project.externalId)], title: project.name, status: project.status,
        tagIDs: project.tagExternalIds.map { identities.id(for: taskRef($0), now: now) },
        line: mapper.assign(project: context))
    }
    let taskIds = Set(source.tasks.map(\.externalId))
    let tasks = source.tasks.map { task in
      let liveExternalId = task.repeatOfExternalId ?? Self.liveId(of: task.externalId, in: taskIds)
      return TaskItem(
        id: identities.id(for: taskRef(task.externalId), now: now),
        refs: [taskRef(task.externalId)], title: task.name,
        projectID: task.projectExternalId.map { identities.id(for: taskRef($0), now: now) },
        parentTaskID: task.parentExternalId.map { identities.id(for: taskRef($0), now: now) },
        tagIDs: task.tagExternalIds.map { identities.id(for: taskRef($0), now: now) },
        status: task.status, flagged: task.flagged, plannedAt: task.plannedAt,
        deferUntil: task.deferUntil, dueAt: task.dueAt,
        effectivePlannedAt: task.effectivePlannedAt, effectiveDeferUntil: task.effectiveDeferUntil,
        effectiveDueAt: task.effectiveDueAt, estimateMinutes: task.estimateMinutes,
        completedAt: task.completedAt, modifiedAt: task.modifiedAt,
        occurrenceOf: liveExternalId.map { identities.id(for: taskRef($0), now: now) },
        line: mapper.assign(
          taskTags: lineTagNames(task.tagExternalIds),
          project: task.projectExternalId.flatMap { contexts[$0] }))
    }

    return Workspace(
      timeZone: source.timeZone, lines: lines, artifacts: artifacts, notes: notes,
      projects: projects, tasks: tasks, tags: tags, issues: issues)
  }

  /// The artifacts read, plus the stored ones the read could not see: those of a carried note
  /// and those of a note whose `artifacts:` list was not read in full. When any is carried,
  /// stored positions are kept (updated in place, new ones last); a clean read keeps its own
  /// order.
  private static func artifacts(
    read: [Artifact], stored: Workspace, notes: [NoteRef], carriedNotes: [NoteRef],
    vault: VaultSnapshot
  ) -> [Artifact] {
    let readByID = Dictionary(read.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let noteByID = Dictionary(
      (stored.notes + notes).map { ($0.id, $0) }, uniquingKeysWith: { _, current in current })
    let carriedNoteIDs = Set(carriedNotes.map(\.id))
    func period(_ artifact: Artifact) -> Horizon? {
      artifact.noteID.flatMap { noteByID[$0]?.period }
    }
    let carried = stored.artifacts.filter { old in
      guard readByID[old.id] == nil else { return false }
      guard vault.isRead else { return true }
      guard let note = old.noteID.flatMap({ noteByID[$0] }),
        carriedNoteIDs.contains(note.id) || vault.unread.artifactLists.contains(note.path)
      else { return false }
      // A read item wins: the same key read in an overlapping period would be a duplicate
      // of the stored one had both notes been read. An unknown period counts as overlapping.
      return !read.contains { new in
        guard new.key == old.key else { return false }
        guard let mine = period(old), let theirs = period(new) else { return true }
        return mine.start < theirs.end && theirs.start < mine.end
      }
    }
    guard !carried.isEmpty else { return read }
    let carriedIDs = Set(carried.map(\.id))
    let storedIDs = Set(stored.artifacts.map(\.id))
    return stored.artifacts.compactMap {
      readByID[$0.id] ?? (carriedIDs.contains($0.id) ? $0 : nil)
    }
      + read.filter { !storedIDs.contains($0.id) }
  }

  /// OmniFocus names a completed occurrence `<liveId>.<n>`; only trusted when the live task exists.
  static func liveId(of externalId: String, in known: Set<String>) -> String? {
    guard let dot = externalId.lastIndex(of: "."),
      externalId[externalId.index(after: dot)...].allSatisfy(\.isNumber),
      dot < externalId.index(before: externalId.endIndex)
    else { return nil }
    let live = String(externalId[..<dot])
    return known.contains(live) ? live : nil
  }
}

/// The provider returned changes only; merging them as a full import would soft-delete
/// everything outside the delta.
public struct PartialSnapshotError: Error, Equatable, Sendable {
  public let modifiedSince: Date
}

/// Reads both providers, builds the workspace with the store's identities and commits it.
public actor ImportService {
  public let tasks: any TaskProvider
  public let notes: any NoteProvider
  public let store: any Store
  public let importer: Importer
  private var current: Task<Workspace, any Error>?
  private var followUp: Task<Workspace, any Error>?
  /// Requests waiting on the queued follow-up run (observable by tests).
  private(set) var followUpRequests = 0

  public init(
    tasks: any TaskProvider, notes: any NoteProvider, store: any Store,
    importer: Importer = Importer()
  ) {
    self.tasks = tasks
    self.notes = notes
    self.store = store
    self.importer = importer
  }

  /// Full import. An incremental merge is decided after the S3a-1 measurements (S3a-2).
  /// Single-flight: imports run one at a time (identity map → workspace → commit is not atomic
  /// otherwise); requests arriving during an import share at most one follow-up run, which
  /// starts when the current one ends, so the latest provider state is still read.
  @discardableResult
  public func run(now: Date = Date()) async throws -> Workspace {
    let task: Task<Workspace, any Error>
    if let followUp {
      task = followUp
      followUpRequests += 1
    } else if let current {
      task = Task { [current] in
        _ = await current.result
        promoteFollowUp()
        return try await importOnce(now: now)
      }
      followUp = task
      followUpRequests = 1
    } else {
      task = Task { try await importOnce(now: now) }
      current = task
    }
    let result = await task.result
    if current == task { current = nil }
    return try result.get()
  }

  private func promoteFollowUp() {
    current = followUp
    followUp = nil
    followUpRequests = 0
  }

  private func importOnce(now: Date) async throws -> Workspace {
    async let taskSnapshot = tasks.snapshot(modifiedSince: nil)
    async let vaultSnapshot = notes.vault()
    let (source, vault) = try await (taskSnapshot, vaultSnapshot)
    if let since = source.modifiedSince { throw PartialSnapshotError(modifiedSince: since) }
    var identities = try await store.identityMap()
    // Read after the identity map: a commit in between bumps the version and this one fails.
    let stored = try await store.workspace()
    let workspace = importer.makeWorkspace(
      tasks: source, vault: vault, stored: stored, identities: &identities.map, now: now)
    try await store.commit(
      workspace, identities: identities.map, expectedVersion: identities.version, at: now)
    return workspace
  }
}
