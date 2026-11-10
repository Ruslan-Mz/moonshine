import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import OmniFocusAdapter

/// `DemoDay` and the fixture snapshot hold the same timed tasks of Thu 1 Oct 2026
/// (`design/demo-data.md` § Draft-3; spec, Demo data).
@Suite struct DemoDayGoldenTests {
  /// The fields of `DemoDay` that are canonical (`DemoDay.swift`): title, times, estimate, status.
  struct Row: Equatable, CustomStringConvertible {
    let title: String
    let plannedAt: Date?
    let dueAt: Date?
    let effectivePlannedAt: Date?
    let effectiveDueAt: Date?
    let estimateMinutes: Int?
    let status: TaskItemStatus
    let completedAt: Date?

    init(_ task: TaskItem) {
      title = task.title
      plannedAt = task.plannedAt
      dueAt = task.dueAt
      effectivePlannedAt = task.effectivePlannedAt
      effectiveDueAt = task.effectiveDueAt
      estimateMinutes = task.estimateMinutes
      status = task.status
      completedAt = task.completedAt
    }

    var time: Date { effectivePlannedAt ?? effectiveDueAt ?? .distantFuture }
    var description: String { title }
  }

  func workspace() async throws -> Workspace {
    let source = try SnapshotMapper.map(try fixtureDocument())
    var identities = IdentityMap()
    return Importer(metaTagGroups: DemoMapping.metaTagGroups).makeWorkspace(
      tasks: source, vault: try await DemoVault().vault(), stored: Workspace(timeZone: .gmt),
      approvedLineRemovals: [], identities: &identities, now: source.generatedAt)
  }

  func hhmm(_ time: TimeOfDay?) -> String? {
    time.map { String(format: "%02d:%02d", $0.hour, $0.minute) }
  }

  @Test func theSnapshotDefaultsAreTheDemoDefaults() throws {
    let document = try fixtureDocument()
    let defaults = DemoDay.defaultTimes
    #expect(document.timeZone == DemoCalendar.calendar.timeZone.identifier)
    #expect(defaults.timeZone == DemoCalendar.calendar.timeZone)
    #expect(document.defaultTimes?.due == "17:00")
    #expect(document.defaultTimes?.due == hhmm(defaults.due))
    #expect(document.defaultTimes?.defer == hhmm(defaults.defer))
    #expect(document.defaultTimes?.planned == hhmm(defaults.planned))
  }

  /// The demo app's import path (S4-3a): the workspace's default times are `DemoDay`'s.
  @Test func theImportedDefaultTimesAreTheDemoDefaults() async throws {
    let workspace = try await workspace()
    #expect(workspace.defaultTimes == DemoDay.defaultTimes)
    #expect(!workspace.issues.contains(.defaultTimesNotRead))
  }

  /// Over the whole snapshot, not only week 40: every other planned or due date is date only,
  /// but Friday's `Book rehearsal room for November`, due 12:00 (`design/demo-data.md` § Week 40
  /// extras).
  @Test func theTimedTasksOfTheSnapshotAreTheDemoDay() async throws {
    let defaults = DemoDay.defaultTimes
    let timed = try await workspace().tasks.filter { task in
      let planned = task.effectivePlannedAt.map { !defaults.isDateOnly($0, kind: .planned) }
      let due = task.effectiveDueAt.map { !defaults.isDateOnly($0, kind: .due) }
      return (planned == true || due == true) && task.title != "Book rehearsal room for November"
    }
    let rows = timed.map(Row.init).sorted { $0.time < $1.time }
    #expect(rows == DemoDay.tasks.map(Row.init).sorted { $0.time < $1.time })
  }

  /// Contract invariant 5 (own ?? nearest container) for the one project with a due date; the
  /// mapper drops project dates, so this reads the raw document.
  @Test func theInheritedDueMatchesItsProject() throws {
    let json = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
    let projects = try #require(json["projects"] as? [[String: Any]])
    let tasks = try #require(json["tasks"] as? [[String: Any]])
    let dated = projects.filter { $0["dueDate"] is String }
    #expect(dated.map { $0["id"] as? String } == ["prj-0046"])
    for project in dated {
      let inheriting = tasks.filter {
        $0["projectId"] as? String == project["id"] as? String && !($0["dueDate"] is String)
          && $0["parentTaskId"] is NSNull
      }
      #expect(!inheriting.isEmpty)
      #expect(
        inheriting.allSatisfy {
          $0["effectiveDueDate"] as? String == project["dueDate"] as? String
        })
    }
  }

  /// `4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00`, as
  /// `DemoDayLoadTests` computes it from `DemoDay`.
  @Test func theThursdayDayLoadOnTheSnapshotMatchesTheDesign() async throws {
    let noon = try #require(
      DemoCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
    let workspace = try await workspace()
    let load = DayLoad.compute(
      day: noon, now: DemoCalendar.now, window: .standard,
      events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
      tasks: workspace.tasks, defaultTimes: workspace.defaultTimes,
      calendar: DemoCalendar.calendar)
    #expect(load.eventCount == 4)
    #expect(load.inCalendarMinutes == 240)
    #expect(load.plannedMinutes == 75)
    #expect(load.freeFromNowMinutes == 145)
    #expect(load.freeWholeWindowMinutes == 525)
  }
}
