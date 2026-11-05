import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5), not the bundled copy.
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

/// Today as the app loads it: `AppEnvironment.demo` through the model.
@MainActor private func demo() async throws -> (Overview, TodayScreen) {
  let model = AppModel(environment: try .demo(snapshot: trackedSnapshot))
  await model.load()
  guard case .loaded(let overview) = model.state else { throw NotLoaded() }
  return (overview, TodayScreen(overview))
}

private struct NotLoaded: Error {}

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
    // Every item once: in a list, or as a chip of the Anchors strip.
    try #require(rows.count + screen.anchors.count == items.count)
    try #require(Set(rows.map(\.id) + screen.anchors.map(\.id)) == Set(items.map(\.task.id)))
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
    let lateEvening = DemoVault.calendar.date(
      from: DateComponents(year: 2026, month: 9, day: 1, hour: 23, minute: 30))!
    #expect(
      TodayFormat.lastDate(lateEvening, today: now, timeZone: moscow, locale: english)
        == "1 September")
    #expect(
      TodayFormat.lastDate(lateEvening, today: now, timeZone: auckland, locale: english)
        == "2 September")
    // A year other than today's is shown; the year is the zone's: 31 December 2025 23:30 in
    // Moscow is already 2026 in Auckland.
    let lastYear = DemoVault.calendar.date(
      from: DateComponents(year: 2025, month: 9, day: 2, hour: 8))!
    #expect(
      TodayFormat.lastDate(lastYear, today: now, timeZone: moscow, locale: english)
        == "2 September 2025")
    let newYearsEve = DemoVault.calendar.date(
      from: DateComponents(year: 2025, month: 12, day: 31, hour: 23, minute: 30))!
    #expect(
      TodayFormat.lastDate(newYearsEve, today: now, timeZone: moscow, locale: english)
        == "31 December 2025")
    #expect(
      TodayFormat.lastDate(newYearsEve, today: now, timeZone: auckland, locale: english)
        == "1 January")
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

  @MainActor @Test func loadingTheDemoRecordsALaunchImport() async throws {
    let model = AppModel(snapshot: trackedSnapshot)
    await model.load()
    let run = try #require(model.lastImport)
    #expect(run.trigger == .launch)
    #expect(run.finishedAt == DemoEnvironment.now)
    #expect(model.freshness() == .justNow)
  }

  /// A store that keeps everything but cannot read its imports.
  struct NoImportsStore: Store {
    let inner = InMemoryStore(timeZone: DemoVault.calendar.timeZone)
    struct Unreadable: Error {}

    func identityMap() async throws -> VersionedIdentityMap { try await inner.identityMap() }
    func commit(
      _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date,
      run: PendingImportRun?
    ) async throws {
      try await inner.commit(
        workspace, identities: identities, expectedVersion: expectedVersion, at: now, run: run)
    }
    func lastCommittedImport() async throws -> ImportRun? { throw Unreadable() }
    func workspace() async throws -> Workspace { try await inner.workspace() }
    func stored() async throws -> StoredWorkspace { try await inner.stored() }
  }

  @MainActor @Test func aStoreThatCannotReadItsImportsStillShowsToday() async throws {
    let model = AppModel(
      environment: try .demo(snapshot: trackedSnapshot, store: NoImportsStore()))
    await model.load()
    #expect(model.lastImport == nil)
    guard case .loaded(let overview) = model.state else { throw NotLoaded() }
    let sections = TodayScreen(overview).sections
    #expect(!sections.isEmpty)
    #expect(
      sections.map { $0.rows.map(\.title) }
        == (try await demo()).1.sections.map { $0.rows.map(\.title) })
  }

  private func isUnavailable(_ state: AppModel.State) -> Bool {
    if case .unavailable = state { true } else { false }
  }

  // MARK: S4-1b-1

  @Test func doneTodayHoldsTheTasksCompletedOnTheDayMostRecentFirstAndNothingElse() async throws {
    let (overview, screen) = try await demo()
    let today = overview.today()
    // The fixture completes six tasks on Thu 1 Oct; three of them are done anchors in the strip.
    #expect(screen.doneToday.count == 3)
    #expect(screen.doneToday.map(\.id) == today.doneToday.map(\.task.id))
    #expect(screen.doneToday.allSatisfy { $0.isDone && !$0.isUrgent })
    let completed = screen.doneToday.compactMap { row in
      overview.workspace.tasks.first { $0.id == row.id }?.completedAt
    }
    #expect(completed == completed.sorted(by: >))
    let elsewhere =
      screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
    #expect(!elsewhere.contains { $0.isDone })
    #expect(screen.totals.done == 6)
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

  @Test func totalsComeFromCoreAndTheStripHoldsTheDemoAnchors() async throws {
    let (overview, screen) = try await demo()
    #expect(screen.totals == overview.today().totals)
    let open = screen.top + screen.sections.flatMap(\.rows) + screen.fromEarlier + screen.lifeOps
    let openAnchors = screen.anchors.filter { !$0.isDone }
    #expect(screen.totals.open == open.count + openAnchors.count)
    // `design/demo-data.md` § Draft-2: `3 of 5 done`.
    #expect(screen.anchors.count == 5)
    #expect(screen.anchorsTotal == 5)
    #expect(screen.anchorsDone == 3)
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
    // Demo's From earlier has three tasks, none flagged, in both modes.
    #expect(off.fromEarlier.count == 3)
    #expect(on.fromEarlier.count == 3)
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

  // MARK: Rail (S4-1b-2)

  /// `design/screens/today.md` § Acceptance: Italian is quiet, Piano (maintenance) is not,
  /// Calligraphy appears only under Paused on purpose; foundation lines are never quiet.
  @Test func theRailFollowsTheDemoFixture() async throws {
    let (overview, screen) = try await demo()
    let lines = overview.workspace.lines
    func key(_ id: LineID) -> LineKey? { lines.first { $0.id == id }?.key }
    let italian = try #require(screen.quiet.first)
    #expect(screen.quiet.compactMap { key($0.id) } == ["italian"])
    // `quiet for 29 days · Last: 2 September` (owner, 2026-10-24).
    let last = try #require(
      DemoVault.calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 19)))
    #expect(italian.lastDate == last)
    let calendar = overview.calendar
    #expect(
      italian.days
        == calendar.dateComponents(
          [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: screen.day)
        ).day)
    #expect(italian.days == 29)
    #expect(screen.noActivity.compactMap { key($0.id) } == ["japanese"])
    let quietOrNew = Set(screen.quiet.map(\.id) + screen.noActivity.map(\.id))
    for line in lines where line.state != .active {
      #expect(!quietOrNew.contains(line.id))
    }
    for line in lines where line.foundation {
      #expect(!screen.quiet.contains { $0.id == line.id })
    }
    #expect(screen.paused.compactMap { key($0.id) } == ["calligraphy"])
    let touched = overview.today().touchedToday
    try #require(!touched.isEmpty)
    #expect(screen.touched.map(\.id) == touched.map(\.line))
    #expect(screen.touched.map(\.sessions) == touched.map(\.counts.rhythm))
    #expect(screen.touched.map(\.tasks) == touched.map(\.counts.progress))
    // The card carries Core's last task and next step; the paused-line rule is pinned in Core.
    let core = try #require(overview.today().quietLines.first { $0.line.id == italian.id })
    guard case .quiet(_, let lastTask) = core.reason else {
      Issue.record("Italian is not quiet in Core")
      return
    }
    let next = try #require(core.nextStep)
    #expect(italian.lastTitle == lastTask.title)
    #expect(italian.next?.title == next.title)
    #expect(italian.next?.estimateMinutes == next.estimateMinutes)
    #expect(!screen.railIsEmpty)
    // `Q4 focus · 2 of 5 done`, each artifact with its line's emoji.
    let focus = try #require(screen.quarterFocus)
    #expect(focus.quarter == 4)
    #expect(focus.done == 2)
    #expect(focus.rows.map(\.emoji) == ["🎻", "🤖", "🔬", "📐", "💪"])
    #expect(focus.rows.map(\.isDone) == [true, false, false, true, false])
  }

  /// Invented: a quarter note with one artifact and no lines; the card alone keeps the rail
  /// from its "Nothing on the rail today" line, and the quarter comes from the note's period.
  @Test func aQuarterFocusAloneIsNotAnEmptyRail() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let calendar = Calendar.iso8601(in: zone)
    let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 12))!
    let note = NoteRef(
      id: .generate(), refs: [], path: "Q2.md", title: "Q2", type: "quarter_focus",
      scale: .quarter, period: Horizon.containing(now, scale: .quarter, calendar: calendar),
      parentLink: nil, lineKey: nil, status: nil)
    let artifact = Artifact(
      id: .generate(), refs: [], key: "q2-01", title: "First recital", lineIDs: [],
      status: .planned, priority: false, noteID: note.id)
    let screen = TodayScreen(
      Overview(
        workspace: Workspace(timeZone: zone, artifacts: [artifact], notes: [note]), now: now))
    #expect(!screen.railIsEmpty)
    #expect(screen.quarterFocus?.quarter == 2)
    #expect(screen.quarterFocus?.rows.map(\.emoji) == [nil])
    #expect(screen.quarterFocus?.done == 0)
  }

  /// Invented: an active line with no tasks has no first step, so its card reads
  /// `no next action`; an empty workspace leaves the rail with its one calm line.
  @Test func aLineWithoutANextActionHasNoNextStepAndAnEmptyRailSaysSo() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let now = Calendar.iso8601(in: zone).date(
      from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    let line = Line(
      id: .generate(), refs: [], key: "japanese", name: "Japanese", emoji: nil,
      block: "Languages", state: .active, budgetHoursPerWeek: nil, parentLink: nil,
      taskRules: LineTaskRules())
    let screen = TodayScreen(
      Overview(workspace: Workspace(timeZone: zone, lines: [line]), now: now))
    #expect(screen.noActivity.map(\.id) == [line.id])
    #expect(screen.noActivity.first?.next == nil)
    #expect(TodayScreen(Overview(workspace: Workspace(timeZone: zone), now: now)).railIsEmpty)
  }

  /// Invented: a paused line with a task completed today is only under Paused on purpose,
  /// while an active line completed today has its Touched today row.
  @Test func aPausedLineCompletedTodayIsNotInTouchedToday() throws {
    let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
    let now = Calendar.iso8601(in: zone).date(
      from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    func line(_ key: LineKey, _ state: LineState) -> Line {
      Line(
        id: .generate(), refs: [], key: key, name: key.rawValue, emoji: nil, block: "Arts",
        state: state, budgetHoursPerWeek: nil, parentLink: nil, taskRules: LineTaskRules())
    }
    let flute = line("flute", .active)
    let sketching = line("sketching", .paused)
    func done(_ line: Line) -> TaskItem {
      TaskItem(
        id: .generate(), refs: [], title: "Done", projectID: nil, parentTaskID: nil,
        tagIDs: [], status: .completed, flagged: false, plannedAt: nil, deferUntil: nil,
        dueAt: nil, effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: nil,
        estimateMinutes: nil, completedAt: now.addingTimeInterval(-3600), modifiedAt: nil,
        occurrenceOf: nil, line: .line(line.id))
    }
    let screen = TodayScreen(
      Overview(
        workspace: Workspace(
          timeZone: zone, lines: [flute, sketching], tasks: [done(flute), done(sketching)]),
        now: now))
    #expect(screen.touched.map(\.id) == [.line(flute.id)])
    #expect(screen.touched.map(\.tasks) == [1])
    #expect(screen.paused.map(\.id) == [sketching.id])
  }

  /// The catalog's Russian plurals, looked up in the app's `ru.lproj`.
  @Test func russianPluralsResolveFromTheCatalog() throws {
    let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
    let ru = try #require(Bundle(path: path))
    let russian = Locale(identifier: "ru")
    func format(_ key: String, _ value: Int) -> String {
      String(
        format: ru.localizedString(forKey: key, value: nil, table: nil), locale: russian, value)
    }
    #expect(format("%lld sessions", 1) == "1 занятие")
    #expect(format("%lld sessions", 3) == "3 занятия")
    #expect(format("%lld sessions", 5) == "5 занятий")
    #expect(format("quiet for %lld days", 21) == "тихо 21 день")
    #expect(format("quiet for %lld days", 29) == "тихо 29 дней")
  }
}
