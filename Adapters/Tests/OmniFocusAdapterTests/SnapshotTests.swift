import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import OmniFocusAdapter

/// `fixtures/omnifocus.snapshot.json` at the repository root (synthetic data).
let fixtureURL = URL(filePath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appending(path: "fixtures/omnifocus.snapshot.json")

func fixtureDocument() throws -> SnapshotDocument {
  try JSONDecoder().decode(SnapshotDocument.self, from: Data(contentsOf: fixtureURL))
}

@Suite struct SnapshotDecodingTests {
  @Test func decodesTheFixture() throws {
    let document = try fixtureDocument()
    #expect(document.schemaVersion == 1)
    #expect(document.mode == "full")
    #expect(document.defaultTimes?.planned == "09:00")
    #expect(document.folders.count == 12)
    #expect(document.tags.count == 23)
    #expect(document.projects.count == 13)
    #expect(document.tasks.count == 163)
  }

  @Test func fixtureSatisfiesEveryContractInvariant() throws {
    #expect(SnapshotValidator.violations(in: try fixtureDocument()) == [])
  }

  @Test func noTaskOrProjectCarriesNoteText() throws {
    let json = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
    for kind in ["tasks", "projects"] {
      let items = try #require(json[kind] as? [[String: Any]])
      #expect(items.allSatisfy { $0["note"] == nil && $0["noteText"] == nil })
    }
  }

  @Test func nonStringNameIsRejected() {
    let json =
      #"{"id":"x","name":1,"projectId":null,"parentTaskId":null,"tagIds":[],"status":"available","flagged":false,"effectiveFlagged":false,"added":"2026-07-06T10:00:00+03:00","modified":"2026-07-06T10:00:00+03:00","noteLength":0}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(SnapshotDocument.Task.self, from: Data(json.utf8))
    }
  }

  @Test func validatorReportsBrokenDocuments() throws {
    var document = try fixtureDocument()
    let index = try #require(document.tasks.firstIndex { $0.status == "completed" })
    document.tasks[index].completionDate = nil
    document.tasks[index].projectId = "prj-missing"
    document.tasks[index].modified = "2026-09-17T11:00:00"
    let violations = SnapshotValidator.violations(in: document)
    let path = "tasks[\(index)]"
    #expect(violations.contains(.init("\(path).projectId", "does not resolve")))
    #expect(violations.contains(.init("\(path).completionDate", "missing on a completed task")))
    #expect(violations.contains(.init("\(path).modified", "date without offset")))
  }

  @Test func errorsNameAPathAndARuleButNeverAValue() throws {
    var document = try fixtureDocument()
    let index = try #require(document.tasks.firstIndex { $0.status == "available" })
    let secrets = [
      document.tasks[index].id, document.tasks[index].name, "prj-secret", "Not a date",
    ]
    document.tasks[index].projectId = "prj-secret"
    document.tasks[index].dueDate = "Not a date"
    let invalid = String(describing: SnapshotValidator.violations(in: document))
    #expect(invalid.contains("tasks[\(index)].projectId: does not resolve"))
    document.tasks[index].projectId = nil
    document.tasks[index].dueDate = nil
    document.tasks[index].status = "Not a status"
    #expect(throws: SnapshotError.badValue(path: "tasks[\(index)].status")) {
      try SnapshotMapper.map(document)
    }
    document.tasks[index].status = "available"
    document.tasks[index].modified = "2026-13-45T99:00:00+03:00"
    #expect(throws: SnapshotError.badValue(path: "tasks[\(index)].modified")) {
      try SnapshotMapper.map(document)
    }
    for secret in secrets + ["2026-13-45", "Not a status"] { #expect(!invalid.contains(secret)) }
  }

  @Test func droppedTasksAreOnlyAllowedInAnIncrementalSnapshot() throws {
    var document = try fixtureDocument()
    let index = try #require(document.tasks.firstIndex { $0.status == "available" })
    document.tasks[index].status = "dropped"
    #expect(
      SnapshotValidator.violations(in: document) == [
        .init("tasks[\(index)].status", "dropped in a full snapshot")
      ])
    document.mode = "incremental"
    document.modifiedSince = "2026-09-30T20:00:00+03:00"
    #expect(SnapshotValidator.violations(in: document) == [])
  }

  @Test func anIncrementalSnapshotNeedsItsCutoffAndMayPointOutsideItself() throws {
    var document = try fixtureDocument()
    let index = try #require(document.tasks.firstIndex { $0.parentTaskId != nil })
    let parentIndex = try #require(
      document.tasks.firstIndex { $0.id == document.tasks[index].parentTaskId })
    let id = document.tasks[index].id
    document.tasks.remove(at: parentIndex)
    let child = try #require(document.tasks.firstIndex { $0.id == id })
    document.mode = "incremental"
    #expect(
      SnapshotValidator.violations(in: document) == [
        .init("modifiedSince", "missing in an incremental snapshot")
      ])
    document.modifiedSince = "2026-09-30T20:00:00+03:00"
    #expect(SnapshotValidator.violations(in: document) == [])
    document.mode = nil
    document.modifiedSince = nil
    #expect(
      SnapshotValidator.violations(in: document).contains(
        .init("tasks[\(child)].parentTaskId", "does not resolve")))
  }

  @Test func defaultTimesAreHoursAndMinutes() throws {
    var document = try fixtureDocument()
    document.defaultTimes = .init(due: "17:00", defer: "0:00", planned: nil)
    #expect(
      SnapshotValidator.violations(in: document) == [.init("defaultTimes.defer", "is not HH:mm")])
    document.defaultTimes?.defer = "00:00"
    document.defaultTimes?.planned = "09:00"
    #expect(SnapshotValidator.violations(in: document) == [])
  }

  func probe() throws -> ChangeProbe {
    let json =
      #"{"schemaVersion":1,"source":"omnifocus","mode":"probe","generatedAt":"2026-09-30T21:00:00+03:00","taskCount":163,"latestModified":"2026-09-30T20:58:00+03:00"}"#
    return try JSONDecoder().decode(ChangeProbe.self, from: Data(json.utf8))
  }

  @Test func decodesAndValidatesAChangeProbe() throws {
    let probe = try probe()
    #expect(probe.taskCount == 163)
    #expect(probe.latestModified == "2026-09-30T20:58:00+03:00")
    #expect(SnapshotValidator.violations(in: probe) == [])
  }

  @Test func rejectsAMalformedChangeProbe() throws {
    var probe = try probe()
    probe.schemaVersion = 2
    probe.source = "things"
    probe.mode = "full"
    probe.generatedAt = "2026-09-30T21:00:00"
    probe.taskCount = -1
    probe.latestModified = "2026-09-30 20:58"
    #expect(
      SnapshotValidator.violations(in: probe) == [
        .init("schemaVersion", "unsupported"), .init("source", "is not omnifocus"),
        .init("mode", "is not probe"), .init("generatedAt", "date without offset"),
        .init("taskCount", "is negative"), .init("latestModified", "date without offset"),
      ])
  }

  @Test func defaultTimesAreValidTwentyFourHourTimes() throws {
    var document = try fixtureDocument()
    document.defaultTimes = .init(due: "24:00", defer: "29:99", planned: "23:59")
    #expect(
      SnapshotValidator.violations(in: document) == [
        .init("defaultTimes.due", "is not HH:mm"), .init("defaultTimes.defer", "is not HH:mm"),
      ])
  }

  @Test func completionBeforeTheWindowIsAViolation() throws {
    var document = try fixtureDocument()
    let index = try #require(document.tasks.firstIndex { $0.status == "completed" })
    document.tasks[index].completionDate = "2026-07-05T23:59:00+03:00"
    #expect(
      SnapshotValidator.violations(in: document) == [
        .init("tasks[\(index)].completionDate", "before the window")
      ])
  }
}

@Suite struct SnapshotMapperTests {
  let source: TaskSourceSnapshot

  init() throws {
    source = try SnapshotMapper.map(try fixtureDocument())
  }

  @Test func folderPathStartsAtTheTopLevel() throws {
    let project = try #require(source.projects.first { $0.externalId == "prj-0046" })
    #expect(project.folderPath == ["Work", "Clients", "Client North"])
    #expect(project.status == .active)
  }

  @Test func datesKeepTheirInstant() throws {
    let task = try #require(source.tasks.first { $0.externalId == "tsk-0167" })
    #expect(task.dueAt == Date(timeIntervalSince1970: 1_790_780_400))  // 2026-09-30T18:00+03:00
    #expect(task.effectiveDueAt == task.dueAt)
    #expect(task.flagged)
    #expect(source.timeZone.identifier == "Europe/Moscow")
    #expect(source.modifiedSince == nil)
  }

  @Test func ownAndEffectiveDatesStaySeparate() throws {
    // Inherits its project's due date, 2026-10-16T18:00+03:00.
    let inheritsDue = try #require(source.tasks.first { $0.externalId == "tsk-0097" })
    #expect(inheritsDue.dueAt == nil)
    #expect(inheritsDue.effectiveDueAt == Date(timeIntervalSince1970: 1_792_162_800))
    // Inherits its group's planned date, 2026-10-01T09:00+03:00.
    let inheritsPlanned = try #require(source.tasks.first { $0.externalId == "tsk-0172" })
    #expect(inheritsPlanned.plannedAt == nil)
    #expect(inheritsPlanned.effectivePlannedAt == Date(timeIntervalSince1970: 1_790_834_400))
  }

  @Test func anIncrementalDocumentMapsToAPartialSnapshotWithDroppedTasks() throws {
    var document = try fixtureDocument()
    document.mode = "incremental"
    document.modifiedSince = "2026-09-30T20:00:00+03:00"
    document.tasks = [try #require(document.tasks.first { $0.status == "available" })]
    document.tasks[0].status = "dropped"
    let partial = try SnapshotMapper.map(document)
    #expect(partial.modifiedSince == Date(timeIntervalSince1970: 1_790_787_600))
    #expect(partial.tasks.map(\.status) == [.dropped])
  }

  @Test func repeatOfIsCarriedThrough() throws {
    let task = try #require(source.tasks.first { $0.externalId == "tsk-0115.0" })
    #expect(task.repeatOfExternalId == "tsk-0115")
    #expect(task.status == .completed)
    #expect(task.completedAt != nil)
  }
}

@Suite struct FixtureImportTests {
  func importFixture() async throws -> Workspace {
    let service = ImportService(
      tasks: SnapshotFileTaskProvider(url: fixtureURL), notes: DemoVault(), store: InMemoryStore())
    return try await service.run(now: Date(timeIntervalSince1970: 1_790_791_200))
  }

  func lineKey(_ assignment: LineAssignment, in workspace: Workspace) -> String {
    guard case .line(let id) = assignment else { return "life-ops" }
    return workspace.lines.first { $0.id == id }?.key.rawValue ?? "?"
  }

  @Test func everyProjectMapsToTheExpectedLine() async throws {
    let workspace = try await importFixture()
    let mapping = Dictionary(
      uniqueKeysWithValues: workspace.projects.map { ($0.title, lineKey($0.line, in: workspace)) })
    #expect(
      mapping == [
        "Partita — first movement": "violin", "Violin technique": "violin",
        "Piano upkeep": "piano", "Brush lettering basics": "calligraphy",
        "Italiano B1": "italian", "Linear algebra course": "math",
        "Задачник по вероятности": "math", "Pull-up progression": "calisthenics",
        "Paper draft on spaced repetition": "research", "Reading list — methods": "research",
        "Client North — mobile release": "work", "Work ops": "work", "Household": "life-ops",
      ])
    #expect(workspace.issues == [])
  }

  @Test func inboxTasksGoToLifeOps() async throws {
    let workspace = try await importFixture()
    let inbox = workspace.tasks.filter { $0.projectID == nil }
    #expect(inbox.count == 5)
    #expect(inbox.allSatisfy { $0.line == .lifeOps })
  }

  @Test func rhythmAndProgressAreSeparable() async throws {
    let workspace = try await importFixture()
    let completed = workspace.tasks.filter { $0.status == .completed }
    #expect(completed.count == 98)
    #expect(completed.filter(\.isOccurrence).count == 32)
  }
}
