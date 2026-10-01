import Foundation
import MoonShineCore
import MoonShineFixtures
import OmniFocusAdapter
import Testing

@testable import SQLiteStore

/// `fixtures/omnifocus.snapshot.json` at the repository root (synthetic data).
let fixtureURL = URL(filePath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appending(path: "fixtures/omnifocus.snapshot.json")

func fixtureSnapshot() throws -> TaskSourceSnapshot {
  try SnapshotMapper.map(
    JSONDecoder().decode(SnapshotDocument.self, from: Data(contentsOf: fixtureURL)))
}

/// Serves a fixed snapshot, so a test can drop, rename or re-zone items between imports.
struct FixedTaskProvider: TaskProvider {
  let source: TaskSourceSnapshot
  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot { source }
}

extension TaskSourceSnapshot {
  func with(
    timeZone: TimeZone? = nil, tags: [SourceTag]? = nil, projects: [SourceProject]? = nil,
    tasks: [SourceTask]? = nil
  ) -> TaskSourceSnapshot {
    TaskSourceSnapshot(
      provider: provider, generatedAt: generatedAt, timeZone: timeZone ?? self.timeZone,
      tags: tags ?? self.tags, projects: projects ?? self.projects, tasks: tasks ?? self.tasks)
  }

  /// An open one-off task nothing else points at, so dropping it changes exactly one row.
  func plainOpenTask() throws -> SourceTask {
    try #require(
      tasks.first { task in
        task.status == .available
          && !tasks.contains {
            $0.parentExternalId == task.externalId || $0.repeatOfExternalId == task.externalId
              || $0.externalId.hasPrefix(task.externalId + ".")
          }
      })
  }

  func dropping(_ externalId: String) -> TaskSourceSnapshot {
    with(tasks: tasks.filter { $0.externalId != externalId })
  }

  func renaming(_ externalId: String, to name: String) -> TaskSourceSnapshot {
    with(
      tasks: tasks.map { task in
        guard task.externalId == externalId else { return task }
        return SourceTask(
          externalId: task.externalId, name: name, projectExternalId: task.projectExternalId,
          parentExternalId: task.parentExternalId, tagExternalIds: task.tagExternalIds,
          status: task.status, flagged: task.flagged, plannedAt: task.plannedAt,
          deferUntil: task.deferUntil, dueAt: task.dueAt, estimateMinutes: task.estimateMinutes,
          completedAt: task.completedAt, modifiedAt: task.modifiedAt,
          repeatOfExternalId: task.repeatOfExternalId)
      })
  }

  /// `copies` disjoint copies of every tag, project and task, ids prefixed per copy.
  func scaled(_ copies: Int) -> TaskSourceSnapshot {
    let ranges = (0..<copies).map { copy in
      let id = { (externalId: String) in "k\(copy)-\(externalId)" }
      return (
        tags: tags.map {
          SourceTag(
            externalId: id($0.externalId), name: $0.name,
            parentExternalId: $0.parentExternalId.map(id))
        },
        projects: projects.map {
          SourceProject(
            externalId: id($0.externalId), name: $0.name, status: $0.status,
            tagExternalIds: $0.tagExternalIds.map(id), folderPath: $0.folderPath)
        },
        tasks: tasks.map {
          SourceTask(
            externalId: id($0.externalId), name: $0.name,
            projectExternalId: $0.projectExternalId.map(id),
            parentExternalId: $0.parentExternalId.map(id),
            tagExternalIds: $0.tagExternalIds.map(id),
            status: $0.status, flagged: $0.flagged, plannedAt: $0.plannedAt,
            deferUntil: $0.deferUntil, dueAt: $0.dueAt, estimateMinutes: $0.estimateMinutes,
            completedAt: $0.completedAt, modifiedAt: $0.modifiedAt,
            repeatOfExternalId: $0.repeatOfExternalId.map(id))
        }
      )
    }
    return with(
      tags: ranges.flatMap(\.tags), projects: ranges.flatMap(\.projects),
      tasks: ranges.flatMap(\.tasks))
  }
}

/// Every `Store` implementation; the contract suite runs each test against all of them.
enum StoreKind: String, CaseIterable, CustomTestStringConvertible, Sendable {
  case inMemory, sqlite

  func make(timeZone: TimeZone = .gmt) throws -> any Store {
    switch self {
    case .inMemory: InMemoryStore(timeZone: timeZone)
    case .sqlite: try SQLiteStore(timeZone: timeZone)
    }
  }

  var testDescription: String { rawValue }
}

func temporaryDatabasePath() -> String {
  FileManager.default.temporaryDirectory
    .appending(path: "moonshine-\(UUID().uuidString).sqlite").path()
}

func expectSame(
  _ actual: Workspace, _ expected: Workspace, sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(actual.timeZone == expected.timeZone, sourceLocation: sourceLocation)
  #expect(actual.lines == expected.lines, sourceLocation: sourceLocation)
  #expect(actual.artifacts == expected.artifacts, sourceLocation: sourceLocation)
  #expect(actual.notes == expected.notes, sourceLocation: sourceLocation)
  #expect(actual.projects == expected.projects, sourceLocation: sourceLocation)
  #expect(actual.tasks == expected.tasks, sourceLocation: sourceLocation)
  #expect(actual.tags == expected.tags, sourceLocation: sourceLocation)
  #expect(actual.issues == expected.issues, sourceLocation: sourceLocation)
}
