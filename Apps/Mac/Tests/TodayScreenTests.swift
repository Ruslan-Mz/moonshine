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
  @Test func sectionsFollowTheLineGroupsFoundationFirstWithoutLifeOps() async throws {
    let (overview, screen) = try await demo()
    let groups = overview.today().groups.filter { $0.line != .lifeOps }
    try #require(!groups.isEmpty)
    #expect(
      screen.sections.map(\.id)
        == groups.compactMap { group -> LineID? in
          if case .line(let id) = group.line { id } else { nil }
        })
    #expect(screen.sections.map { $0.rows.map(\.id) } == groups.map { $0.items.map(\.task.id) })
    let lines = overview.workspace.lines
    let order = screen.sections.compactMap { section in
      lines.firstIndex { $0.id == section.id }.map { (lines[$0].foundation ? 0 : 1, $0) }
    }
    #expect(order.count == screen.sections.count)
    #expect(order.map(\.0) == order.map(\.0).sorted())
    #expect(order.map(\.1) == order.sorted { $0 < $1 }.map(\.1))
    // Demo's 💪 foundation line has a task today, so its section leads.
    let first = try #require(screen.sections.first)
    #expect(lines.first { $0.id == first.id }?.foundation == true)
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
    let rows =
      screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
      + screen.doneToday
    let items = today.items
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

  @Test func dayAndWeekComeFromTheWorkspace() async throws {
    let (_, screen) = try await demo()
    #expect(screen.timeZone == TimeZone(identifier: "Europe/Moscow"))
    #expect(screen.day == DemoEnvironment.now)
    #expect(screen.week == 40)
  }

  /// Auckland is 10 hours ahead of Moscow: there, Demo's 16:20 is already Friday. The
  /// formatter must follow the zone it is given, whatever the Mac's zone is.
  @Test func formattingFollowsTheZoneItIsGiven() throws {
    let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
    let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
    let english = Locale(identifier: "en_GB")
    let now = DemoEnvironment.now
    #expect(TodayFormat.day(now, timeZone: moscow, locale: english) == "Thursday 1 October")
    #expect(TodayFormat.day(now, timeZone: auckland, locale: english) == "Friday 2 October")
    let due = DemoVault.calendar.date(
      from: DateComponents(year: 2026, month: 10, day: 1, hour: 17))!
    #expect(TodayFormat.dueDate(due, timeZone: moscow, locale: english) == "1 Oct")
    #expect(TodayFormat.dueDate(due, timeZone: auckland, locale: english) == "2 Oct")
  }

  @Test func estimatesAndDueStyles() {
    #expect(TodayFormat.estimate(nil) == nil)
    #expect(TodayFormat.estimate(0) == nil)
    #expect(TodayFormat.estimate(-30) == nil)
    #expect(TodayFormat.estimate(45) == .minutes(45))
    #expect(TodayFormat.estimate(60) == .hours(1))
    #expect(TodayFormat.estimate(75) == .hoursAndMinutes(1, 15))
    #expect(TodayFormat.dueStyle(isUrgent: true) == .deadline)
    #expect(TodayFormat.dueStyle(isUrgent: false) == .plain)
  }

  /// Invented Life ops estimates: a negative one is left out and a huge sum never traps.
  @Test func theLifeOpsSumSkipsNegativeEstimatesAndNeverTraps() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let calendar = Calendar.iso8601(in: zone)
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    func screen(_ estimates: [Int]) -> TodayScreen {
      let tasks = estimates.map { minutes in
        TaskItem(
          id: .generate(), refs: [], title: "Errand", projectID: nil, parentTaskID: nil,
          tagIDs: [], status: .available, flagged: false, plannedAt: now, deferUntil: nil,
          dueAt: nil, effectivePlannedAt: now, effectiveDeferUntil: nil, effectiveDueAt: nil,
          estimateMinutes: minutes, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
          line: .lifeOps)
      }
      return TodayScreen(Overview(workspace: Workspace(timeZone: zone, tasks: tasks), now: now))
    }
    #expect(screen([-30, 45]).lifeOps.count == 2)
    #expect(screen([-30, 45]).lifeOpsEstimateMinutes == 45)
    #expect(screen([.max, 1]).lifeOpsEstimateMinutes == .max)
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
        tagIDs: [], status: .available, flagged: false, plannedAt: now, deferUntil: nil,
        dueAt: nil, effectivePlannedAt: now, effectiveDeferUntil: nil, effectiveDueAt: nil,
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

  @MainActor @Test func loadingTheDemoShowsToday() async throws {
    let model = AppModel(snapshot: trackedSnapshot)
    await model.load()
    guard case .loaded(let overview) = model.state else {
      Issue.record("Today is not loaded")
      return
    }
    let loaded = TodayScreen(overview)
    let (_, expected) = try await demo()
    try #require(!expected.sections.isEmpty)
    #expect(
      loaded.sections.map { $0.rows.map(\.title) }
        == expected.sections.map { $0.rows.map(\.title) })
    #expect(loaded.fromEarlier.map(\.title) == expected.fromEarlier.map(\.title))
    #expect(loaded.lifeOps.map(\.title) == expected.lifeOps.map(\.title))
    #expect(loaded.top.map(\.title) == expected.top.map(\.title))
    #expect(loaded.doneToday.map(\.title) == expected.doneToday.map(\.title))
    #expect(loaded.day == expected.day)
    #expect(loaded.week == expected.week)
    #expect(TodayScreen(overview, showAllFlagged: true).top.count == expected.flaggedCount)
  }

  /// The tests run inside the app; there the app reads Demo data only, never a live source.
  @MainActor @Test func aTestHostReadsDemoOnly() {
    #expect(AppModel.isTestHost)
    #expect(AppModel.source(isTestHost: true) == .demo)
    #expect(AppModel().source == .demo)
  }

  @MainActor @Test func aMissingSnapshotLeavesTodayUnavailable() async {
    let none = AppModel(snapshot: nil)
    await none.load()
    #expect(isUnavailable(none.state))
    let gone = AppModel(
      snapshot: FileManager.default.temporaryDirectory
        .appendingPathComponent("moonshine-\(UUID().uuidString).json"))
    await gone.load()
    #expect(isUnavailable(gone.state))
  }

  private func isUnavailable(_ state: AppModel.State) -> Bool {
    if case .unavailable = state { true } else { false }
  }

  // MARK: S4-1b-1

  @Test func doneTodayHoldsTheTasksCompletedOnTheDayMostRecentFirstAndNothingElse() async throws {
    let (overview, screen) = try await demo()
    let today = overview.today()
    // The fixture completes two tasks on Thu 1 Oct.
    #expect(screen.doneToday.count == 2)
    #expect(screen.doneToday.map(\.id) == today.doneToday.map(\.task.id))
    #expect(screen.doneToday.allSatisfy { $0.isDone && !$0.isUrgent })
    let completed = screen.doneToday.compactMap { row in
      overview.workspace.tasks.first { $0.id == row.id }?.completedAt
    }
    #expect(completed == completed.sorted(by: >))
    let elsewhere =
      screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
    #expect(!elsewhere.contains { $0.isDone })
    #expect(screen.totals.done == 2)
  }

  @Test func topThreeShowsThreeFlaggedTasksOnceAndShowAllShowsEveryCandidate() async throws {
    let (overview, screen) = try await demo()
    try #require(screen.flaggedCount > Overview.topShown)
    #expect(screen.top.count == Overview.topShown)
    #expect(screen.flaggedCount == overview.today().flaggedCount)
    let below = Set(
      (screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps).map(\.id))
    #expect(below.isDisjoint(with: screen.top.map(\.id)))
    let all = TodayScreen(overview, showAllFlagged: true)
    #expect(all.top.count == screen.flaggedCount)
    let allBelow = Set((all.sections.flatMap(\.rows) + all.fromEarlier + all.lifeOps).map(\.id))
    #expect(allBelow.isDisjoint(with: all.top.map(\.id)))
  }

  @Test func totalsComeFromCoreAndTheDemoHasNoAnchorsYet() async throws {
    let (overview, screen) = try await demo()
    #expect(screen.totals == overview.today().totals)
    let open = screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
    #expect(screen.totals.open == open.count)
    // The fixture gets `anchor` tags in S4-DD; until then the strip is absent.
    #expect(screen.anchors.isEmpty)
    #expect(screen.anchorsTotal == 0)
  }

  /// Invented: six anchors, one done, one in Life ops.
  @Test func theStripShowsFiveChipsWithTheirLineEmojiAndCountsEveryAnchor() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let calendar = Calendar.iso8601(in: zone)
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    let violin = Line(
      id: .generate(), refs: [], key: "violin", name: "Violin", emoji: "🎻", block: "Creative",
      state: .active, budgetHoursPerWeek: nil, parentLink: nil, taskRules: LineTaskRules())
    let anchor = MoonShineCore.Tag(
      id: .generate(), refs: [], name: "Anchor", parentID: nil, isMeta: false)
    func task(_ title: String, line: LineAssignment, done: Bool = false) -> TaskItem {
      TaskItem(
        id: .generate(), refs: [], title: title, projectID: nil, parentTaskID: nil,
        tagIDs: [anchor.id], status: done ? .completed : .available, flagged: false,
        plannedAt: now, deferUntil: nil, dueAt: nil, effectivePlannedAt: now,
        effectiveDeferUntil: nil, effectiveDueAt: nil, estimateMinutes: nil,
        completedAt: done ? now : nil, modifiedAt: nil, occurrenceOf: nil, line: line)
    }
    let tasks =
      [task("Done", line: .line(violin.id), done: true), task("Errand", line: .lifeOps)]
      + (1...4).map { task("Bow \($0)", line: .line(violin.id)) }
      + [task("Late", line: .line(violin.id), done: true)]
    let workspace = Workspace(timeZone: zone, lines: [violin], tasks: tasks, tags: [anchor])
    let screen = TodayScreen(Overview(workspace: workspace, now: now))
    #expect(screen.anchors.map(\.title) == ["Done", "Errand", "Bow 1", "Bow 2", "Bow 3"])
    #expect(screen.anchors.map(\.emoji) == ["🎻", "🧺", "🎻", "🎻", "🎻"])
    #expect(screen.anchors.map(\.isDone) == [true, false, false, false, false])
    #expect(screen.anchorsTotal == 7)
    // The done anchor after the fifth chip counts and is in Done today; the chip is not.
    #expect(screen.anchorsDone == 2)
    #expect(screen.doneToday.map(\.title) == ["Late"])
    #expect(screen.totals.done == 2)
    #expect(screen.sections.flatMap(\.rows).map(\.title) == ["Bow 4"])
  }

  @Test func aChipTitleIsCutAtTwentyTwoCharacters() {
    let fits = String(repeating: "a", count: 22)
    #expect(TodayFormat.chipTitle(fits) == fits)
    #expect(TodayFormat.chipTitle(fits + "b") == String(repeating: "a", count: 21) + "…")
    #expect(TodayFormat.chipTitle("👨‍👩‍👧 reading") == "👨‍👩‍👧 reading")
  }

  // MARK: PR #31 round 1

  /// Every table row once, in both modes of Top 3, and each section loses only the flagged
  /// tasks "Show all" moves up.
  @Test func rowIDsAreUniqueAndSectionsKeepTheirRowsWithShowAllOffAndOn() async throws {
    let (overview, off) = try await demo()
    let on = TodayScreen(overview, showAllFlagged: true)
    func ids(_ screen: TodayScreen) -> [TaskItemID] {
      (screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
        + screen.doneToday).map(\.id)
    }
    for screen in [off, on] {
      #expect(Set(ids(screen)).count == ids(screen).count)
    }
    #expect(Set(ids(off)) == Set(ids(on)))
    let movedUp = Set(on.top.map(\.id)).subtracting(off.top.map(\.id))
    func kept(_ rows: [TodayScreen.Row]) -> [TaskItemID] {
      rows.map(\.id).filter { !movedUp.contains($0) }
    }
    #expect(on.fromEarlier.map(\.id) == kept(off.fromEarlier))
    #expect(on.lifeOps.map(\.id) == kept(off.lifeOps))
    #expect(on.doneToday.map(\.id) == off.doneToday.map(\.id))
    for section in off.sections {
      let rows = on.sections.first { $0.id == section.id }?.rows ?? []
      #expect(rows.map(\.id) == kept(section.rows))
    }
    // Demo's From earlier has one task, not flagged, in both modes.
    #expect(off.fromEarlier.count == 1)
    #expect(on.fromEarlier.count == 1)
  }

  /// Invented: five tasks done today and three or four flagged ones.
  @Test func doneTodayShowsThreeAndTheCaptionNeedsMoreThanThreeCandidates() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let calendar = Calendar.iso8601(in: zone)
    func at(_ hour: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
    }
    let now = at(16)
    func task(_ title: String, flagged: Bool = false, done: Date? = nil) -> TaskItem {
      TaskItem(
        id: .generate(), refs: [], title: title, projectID: nil, parentTaskID: nil, tagIDs: [],
        status: done == nil ? .available : .completed, flagged: flagged, plannedAt: nil,
        deferUntil: nil, dueAt: nil, effectivePlannedAt: nil, effectiveDeferUntil: nil,
        effectiveDueAt: nil, estimateMinutes: nil, completedAt: done, modifiedAt: nil,
        occurrenceOf: nil, line: .lifeOps)
    }
    let done = (1...5).map { task("Done \($0)", done: at(8 + $0)) }
    func screen(flagged: Int) -> TodayScreen {
      let tasks = done + (0..<flagged).map { task("F\($0)", flagged: true) }
      return TodayScreen(
        Overview(workspace: Workspace(timeZone: zone, tasks: tasks), now: now))
    }
    let three = screen(flagged: 3)
    #expect(three.doneVisible.map(\.title) == ["Done 5", "Done 4", "Done 3"])
    #expect(three.doneMore.map(\.title) == ["Done 2", "Done 1"])
    #expect(!three.showsFlaggedCaption)
    #expect(screen(flagged: 4).showsFlaggedCaption)
  }

  @Test func theNarrowestTodayIsTheSumOfTheColumnMinimums() {
    #expect(TodayColumns.taskMinimum >= 120)
    #expect(TodayColumns.traceMinimum < TodayColumns.traceIdeal)
    #expect(TodayColumns.minimumWidth == 34 + 120 + 120 + 100 + 118 + TodayColumns.margins)
  }
}
