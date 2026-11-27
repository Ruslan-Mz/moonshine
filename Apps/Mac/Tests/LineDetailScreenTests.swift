import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

@Suite(.serialized) struct LineDetailScreenTests {
  static let zone = TimeZone(identifier: "Europe/Moscow")!
  static let calendar = Calendar.iso8601(in: zone)

  static func date(_ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
  }

  /// Wednesday of ISO week 40.
  static let now = date(9, 30)

  static let violin = Line(
    id: .generate(), refs: [], key: "violin", name: "Violin", emoji: "🎻", block: "Creative",
    state: .active, budgetHoursPerWeek: 6, parentLink: nil, taskRules: LineTaskRules())

  /// The one next action of a line with one available task, as Core computes it at `now`.
  static func item(planned: Date? = nil, defer deferUntil: Date? = nil, due: Date? = nil)
    throws -> LineDetailItem
  {
    let task = TaskItem(
      id: .generate(), refs: [], title: "Task", projectID: nil, parentTaskID: nil, tagIDs: [],
      status: .available, flagged: false, plannedAt: planned, deferUntil: deferUntil,
      dueAt: due, effectivePlannedAt: planned, effectiveDeferUntil: deferUntil,
      effectiveDueAt: due, estimateMinutes: nil, completedAt: nil, modifiedAt: nil,
      occurrenceOf: nil, line: .line(violin.id))
    let workspace = Workspace(timeZone: zone, lines: [violin], tasks: [task])
    let detail = Overview(workspace: workspace, now: now).lineDetail(violin.id)
    return try #require(detail?.nextActions.first)
  }

  // MARK: When

  @Test func whenShowsTheDueBadgeThenTodayThenThePlacement() throws {
    let week = ISOWeek(containing: Self.now, calendar: Self.calendar)
      .horizon(calendar: Self.calendar)
    func when(_ item: LineDetailItem) -> LineDetailFormat.When {
      LineDetailFormat.when(
        item, now: Self.now, week: week, calendar: Self.calendar,
        defaultTimes: DefaultTimes(timeZone: Self.zone))
    }
    let tonight = Self.date(9, 30, 23)
    #expect(when(try Self.item(due: tonight)) == .due(tonight, urgent: true, showsTime: true))
    let nextWeek = Self.date(10, 6)
    #expect(when(try Self.item(due: nextWeek)) == .due(nextWeek, urgent: false, showsTime: false))
    #expect(when(try Self.item(planned: Self.date(9, 29))) == .today)
    let friday = Self.date(10, 2)
    #expect(when(try Self.item(defer: friday)) == .weekday(friday))
    // A day of this week that has passed is a date, not a weekday.
    let monday = Self.date(9, 28)
    #expect(when(try Self.item(defer: monday)) == .date(monday))
    let tuesday = Self.date(10, 6)
    #expect(when(try Self.item(planned: tuesday)) == .date(tuesday))
    // An old defer date is not today's work (Today's rule): its date, not `today`.
    let longAgo = Self.date(9, 27)
    #expect(when(try Self.item(defer: longAgo)) == .date(longAgo))
    #expect(when(try Self.item()) == .none)
  }

  /// Today's rule (`TodayFormat.when`): the time only for a due time on today's date; a due
  /// today at OmniFocus' default time, or none, shows the date (owner, 2026-11-16).
  @Test func theDueBadgeShowsTheTimeOnlyForADueTimeToday() throws {
    let week = ISOWeek(containing: Self.now, calendar: Self.calendar)
      .horizon(calendar: Self.calendar)
    let fiveOClock = TimeOfDay(hour: 17, minute: 0)
    func when(_ due: Date, defaultDue: TimeOfDay? = nil) throws -> LineDetailFormat.When {
      LineDetailFormat.when(
        try Self.item(due: due), now: Self.now, week: week, calendar: Self.calendar,
        defaultTimes: DefaultTimes(timeZone: Self.zone, due: defaultDue))
    }
    let six = Self.date(9, 30, 18)
    #expect(try when(six) == .due(six, urgent: true, showsTime: true))
    let midnight = Self.date(9, 30, 0)
    #expect(try when(midnight) == .due(midnight, urgent: true, showsTime: false))
    let five = Self.date(9, 30, 17)
    #expect(try when(five, defaultDue: fiveOClock) == .due(five, urgent: true, showsTime: false))
    let tomorrow = Self.date(10, 1, 18)
    #expect(try when(tomorrow) == .due(tomorrow, urgent: false, showsTime: false))
    // A due time on an earlier day is a date: only today shows the time.
    let yesterday = Self.date(9, 29, 18)
    #expect(try when(yesterday) == .due(yesterday, urgent: true, showsTime: false))
  }

  @Test func horizonIsAYearOrAQuarter() {
    func period(_ scale: Scale) -> Horizon? {
      Horizon.containing(Self.date(11, 15), scale: scale, calendar: Self.calendar)
    }
    #expect(LineDetailFormat.horizon(period(.year), timeZone: Self.zone) == .year(2026))
    #expect(
      LineDetailFormat.horizon(period(.quarter), timeZone: Self.zone) == .quarter(4, year: 2026))
    #expect(LineDetailFormat.horizon(period(.month), timeZone: Self.zone) == nil)
    #expect(LineDetailFormat.horizon(nil, timeZone: Self.zone) == nil)
  }

  @Test func completionDayAndWeekdayFollowTheZoneAndLocale() {
    let english = Locale(identifier: "en_GB")
    let wednesday = Self.date(9, 30)
    let day = LineDetailFormat.completionDay(wednesday, timeZone: Self.zone, locale: english)
    #expect(day == "Wed 30 Sep")
    let friday = LineDetailFormat.weekday(Self.date(10, 2), timeZone: Self.zone, locale: english)
    #expect(friday == "Fri")
  }

  /// `TodayFormat.lastDate`'s rule: the year only when it is not this year's.
  @Test func aDateOfAnotherYearShowsItsYear() {
    let english = Locale(identifier: "en_GB")
    func text(_ date: Date) -> String {
      TodayFormat.dueDate(date, today: Self.now, timeZone: Self.zone, locale: english)
    }
    #expect(text(Self.date(10, 12)) == "12 Oct")
    let january = Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 5))!
    #expect(text(january) == "5 Jan 2027")
  }

  @Test func theDaysSoFarRunFromMondayToToday() {
    let english = Locale(identifier: "en_GB")
    func days(_ today: Date) -> String {
      LineDetailFormat.daysSoFar(
        from: Self.date(9, 28, 0), to: today, timeZone: Self.zone, locale: english)
    }
    #expect(days(Self.now) == "Mon–Wed")
    #expect(days(Self.date(9, 28, 9)) == "Mon")
  }

  // MARK: Screen

  @Test func aLineNotInTheOverviewHasNoScreen() {
    let overview = Overview(workspace: Workspace(timeZone: Self.zone), now: Self.now)
    #expect(LineDetailScreen(overview, line: .generate()) == nil)
  }

  @Test func zeroCountsAreLeftOutOfTheSubtitle() throws {
    let overview = Overview(
      workspace: Workspace(timeZone: Self.zone, lines: [Self.violin]), now: Self.now)
    let screen = try #require(LineDetailScreen(overview, line: Self.violin.id))
    #expect(screen.counts.isEmpty)
    #expect(screen.title == "🎻 Violin")
    #expect(screen.parent == nil)
    #expect(screen.weeks.count == Overview.sparklineWeeks)
  }

  /// The artifact's card takes its year note's horizon, path and note; a parent note its own.
  @Test func theParentCardIsTheArtifactOrTheParentNote() throws {
    let year = try #require(Horizon.containing(Self.now, scale: .year, calendar: Self.calendar))
    let quarter = try #require(
      Horizon.containing(Self.now, scale: .quarter, calendar: Self.calendar))
    let yearNote = NoteRef(
      id: .generate(), refs: [], path: "Years/Artifacts_2026.md", title: "Artifacts 2026",
      type: "year_artifacts", scale: .year, period: year, parentLink: nil, lineKey: nil,
      status: nil)
    let quarterNote = NoteRef(
      id: .generate(), refs: [], path: "Years/Q3_2026.md", title: "Q3 2026", type: nil,
      scale: .quarter, period: quarter, parentLink: nil, lineKey: nil, status: nil)
    let sketching = Line(
      id: .generate(), refs: [], key: "sketching", name: "Sketching", emoji: nil,
      block: "Creative", state: .active, budgetHoursPerWeek: nil, parentLink: "[[Q3_2026]]",
      taskRules: LineTaskRules())
    let artifact = Artifact(
      id: .generate(), refs: [], key: "recital", title: "Spring recital",
      lineIDs: [Self.violin.id], status: .planned, priority: false, noteID: yearNote.id)
    let overview = Overview(
      workspace: Workspace(
        timeZone: Self.zone, lines: [Self.violin, sketching], artifacts: [artifact],
        notes: [yearNote, quarterNote]),
      now: Self.now)
    let violin = try #require(LineDetailScreen(overview, line: Self.violin.id))
    #expect(
      violin.parent
        == .init(
          isArtifact: true, title: "Spring recital", horizon: .year(2026),
          path: "Years/Artifacts_2026.md", note: yearNote.id))
    let note = try #require(LineDetailScreen(overview, line: sketching.id))
    #expect(
      note.parent
        == .init(
          isArtifact: false, title: "Q3 2026", horizon: .quarter(3, year: 2026),
          path: "Years/Q3_2026.md", note: quarterNote.id))
  }

  // MARK: Columns

  @Test func theNarrowestLineDetailFitsBesideTheInspectorAt1100() {
    #expect(LineDetailColumns.minimumWidth == CGFloat(2 * 230 + 12 + 40))
    #expect(LineDetailColumns.inspectorMinimum < LineDetailColumns.inspectorIdeal)
    // At 1100×700 with a 200 pt sidebar the detail has about 900.
    #expect(LineDetailColumns.minimumWidth + LineDetailColumns.inspectorMinimum <= 900)
  }

  // MARK: Demo (`design/screens/line-detail.md`, `design/demo-data.md` § Lines)

  @MainActor @Test func demoViolin() async throws {
    let overview = try await demoOverview()
    let violin = try #require(overview.workspace.lines.first { $0.key == "violin" })
    let screen = try #require(LineDetailScreen(overview, line: violin.id))
    #expect(screen.weeks == Array(33...40))
    #expect(screen.rhythm.values == [6, 5, 2, 1, 3, 6, 6, 4])
    #expect(screen.progress.values == [1, 2, 0, 0, 1, 2, 1, 1])
    #expect(screen.rhythm.average == 4.0)
    #expect(screen.progress.average == 1.0)
    #expect(screen.last == .today)
    // `Line detail · 4 projects · 9 next actions` (`line-detail.md` § Layout).
    #expect(screen.counts == [.projects(4), .nextActions(9)])
    #expect(
      screen.projects.map(\.title) == [
        "Daily technique", "Bach Partita No. 2", "Études", "Recital prep",
      ])
    #expect(screen.projects.first?.kind == .repeatingSessions)
    #expect(screen.completions.count == Overview.completionsShown)
    #expect(screen.parent?.isArtifact == true)
  }

  // MARK: ⌘O (owner, 2026-11-26)

  @MainActor @Test func openInOmniFocusTargetsTheFirstProjectInProjectsOrder() async throws {
    let overview = try await demoOverview()
    let violin = try #require(overview.workspace.lines.first { $0.key == "violin" })
    let screen = try #require(LineDetailScreen(overview, line: violin.id))
    let first = try #require(screen.projects.first)
    #expect(screen.projects.count > 1)
    #expect(OpenCommands.target(screen) == .project(first.id))
  }

  @Test func aLineWithNoProjectHasNoOpenTarget() throws {
    let overview = Overview(
      workspace: Workspace(timeZone: Self.zone, lines: [Self.violin]), now: Self.now)
    let screen = try #require(LineDetailScreen(overview, line: Self.violin.id))
    #expect(screen.projects.isEmpty)
    #expect(OpenCommands.target(screen) == nil)
  }

  /// No Line detail: a line that left the workspace; other screens never set the value.
  @Test func withoutALineDetailThereIsNoOpenTarget() {
    #expect(OpenCommands.target(nil) == nil)
  }
}
