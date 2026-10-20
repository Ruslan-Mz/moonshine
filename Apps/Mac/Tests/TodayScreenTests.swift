import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5), not the bundled copy.
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

private func demo() async throws -> (Overview, TodayScreen) {
  let overview = try await DemoEnvironment.overview(snapshot: trackedSnapshot)
  return (overview, TodayScreen(overview))
}

@Suite(.serialized) struct TodayScreenTests {
  @Test func sectionsFollowTheLineGroupsInVaultOrderWithoutLifeOps() async throws {
    let (overview, screen) = try await demo()
    let groups = overview.today().groups.filter { $0.line != .lifeOps }
    try #require(!groups.isEmpty)
    #expect(
      screen.sections.map(\.id)
        == groups.compactMap { group -> LineID? in
          if case .line(let id) = group.line { id } else { nil }
        })
    #expect(screen.sections.map { $0.rows.map(\.id) } == groups.map { $0.items.map(\.task.id) })
    let vaultOrder = screen.sections.compactMap { section in
      overview.workspace.lines.firstIndex { $0.id == section.id }
    }
    #expect(vaultOrder.count == screen.sections.count)
    #expect(vaultOrder == vaultOrder.sorted())
  }

  @Test func lifeOpsIsTheLifeOpsGroupWithItsEstimate() async throws {
    let (overview, screen) = try await demo()
    let group = try #require(overview.today().groups.first { $0.line == .lifeOps })
    try #require(!group.items.isEmpty)
    #expect(screen.lifeOps.map(\.id) == group.items.map(\.task.id))
    #expect(
      screen.lifeOpsEstimateMinutes
        == group.items.compactMap(\.task.estimateMinutes).reduce(0, +))
  }

  @Test func fromEarlierCarriesThePlannedAgeOldestFirst() async throws {
    let (overview, screen) = try await demo()
    let earlier = overview.today().fromEarlier
    try #require(!earlier.isEmpty)
    #expect(screen.fromEarlier.map(\.id) == earlier.map(\.task.id))
    #expect(screen.fromEarlier.map(\.plannedDaysAgo) == earlier.map(\.plannedDaysAgo))
    let ages = screen.fromEarlier.compactMap(\.plannedDaysAgo)
    #expect(ages.count == earlier.count)
    #expect(ages.allSatisfy { $0 > 0 })
    #expect(ages == ages.sorted(by: >))
  }

  @Test func onlyARealDueBeforeTheDayEndsIsUrgent() async throws {
    let (overview, screen) = try await demo()
    let today = overview.today()
    let rows = screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
    let items = today.groups.flatMap(\.items) + today.fromEarlier
    try #require(rows.count == items.count)
    let urgent = Set(items.filter(\.isUrgent).map(\.task.id))
    try #require(!urgent.isEmpty)
    #expect(Set(rows.filter(\.isUrgent).map(\.id)) == urgent)
    for row in rows where row.isUrgent {
      #expect(try #require(row.due) < today.day.end)
    }
    for row in rows where row.due == nil {
      #expect(!row.isUrgent)
    }
  }

  /// Auckland is 10 hours ahead of Moscow: there, Demo's 16:20 is already Friday.
  @Test func dayWeekAndDueDatesFollowTheWorkspaceZone() async throws {
    let (_, screen) = try await demo()
    let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
    #expect(screen.timeZone == moscow)
    #expect(screen.week == 40)
    let saved = NSTimeZone.default
    NSTimeZone.default = try #require(TimeZone(identifier: "Pacific/Auckland"))
    defer { NSTimeZone.default = saved }
    let english = Locale(identifier: "en_GB")
    let day = TodayFormat.day(screen.day, timeZone: screen.timeZone, locale: english)
    #expect(day == "Thursday 1 October")
    let due = DemoVault.calendar.date(
      from: DateComponents(year: 2026, month: 10, day: 1, hour: 17))!
    #expect(TodayFormat.dueDate(due, timeZone: screen.timeZone, locale: english) == "1 Oct")
  }

  /// Invented: a line whose trace ends at its parent note, one at a current-year artifact.
  @Test func traceLeavesOutAMissingStepAndEndsAtTheArtifactOrParentNote() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let calendar = Calendar.iso8601(in: zone)
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    let year = try #require(Horizon.containing(now, scale: .year, calendar: calendar))
    let yearNote = NoteRef(
      id: .generate(), refs: [], path: "Years/Artifacts_2026.md", title: "Artifacts 2026",
      type: "year_artifacts", scale: .year, period: year, parentLink: nil, lineKey: nil,
      status: nil)
    let parentNote = NoteRef(
      id: .generate(), refs: [], path: "Lines/Sketching.md", title: "Sketching", type: nil,
      scale: nil, period: nil, parentLink: nil, lineKey: nil, status: nil)
    func line(_ key: LineKey, emoji: String, parent: String?) -> Line {
      Line(
        id: .generate(), refs: [], key: key, name: key.rawValue.capitalized, emoji: emoji,
        block: "Creative", state: .active, budgetHoursPerWeek: nil, parentLink: parent,
        taskRules: LineTaskRules())
    }
    let flute = line("flute", emoji: "🪈", parent: nil)
    let sketching = line("sketching", emoji: "✏️", parent: "[[Sketching]]")
    let artifact = Artifact(
      id: .generate(), refs: [], key: "recital", title: "Spring recital", lineIDs: [flute.id],
      status: .planned, priority: false, noteID: yearNote.id)
    let project = Project(
      id: .generate(), refs: [], title: "Repertoire", status: .active, tagIDs: [],
      line: .line(flute.id))
    func task(_ title: String, _ line: Line, project: ProjectID?) -> TaskItem {
      TaskItem(
        id: .generate(), refs: [], title: title, projectID: project, parentTaskID: nil,
        tagIDs: [], status: .available, flagged: true, plannedAt: nil, deferUntil: nil,
        dueAt: nil, effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: nil,
        estimateMinutes: nil, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
        line: .line(line.id))
    }
    let workspace = Workspace(
      timeZone: zone, lines: [flute, sketching], artifacts: [artifact],
      notes: [yearNote, parentNote], projects: [project],
      tasks: [
        task("Long tones", flute, project: project.id),
        task("Draw hands", sketching, project: nil),
      ])
    let screen = TodayScreen(Overview(workspace: workspace, now: now))
    let traces = screen.sections.flatMap(\.rows).map(\.trace)
    #expect(
      traces == [
        ["Repertoire", "🪈 Flute", "Spring recital"],
        ["✏️ Sketching", "Sketching"],
      ])
  }

  @Test func theBundleCarriesTheSnapshot() {
    #expect(DemoEnvironment.bundledSnapshot != nil)
  }

  @MainActor @Test func aMissingSnapshotLeavesTodayUnavailable() async {
    let none = AppModel(snapshot: nil)
    await none.load()
    #expect(none.state == .unavailable)
    let gone = AppModel(
      snapshot: FileManager.default.temporaryDirectory
        .appendingPathComponent("moonshine-\(UUID().uuidString).json"))
    await gone.load()
    #expect(gone.state == .unavailable)
  }
}
