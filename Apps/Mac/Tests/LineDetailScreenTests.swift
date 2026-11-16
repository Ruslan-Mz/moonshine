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
      LineDetailFormat.when(item, now: Self.now, week: week)
    }
    let tonight = Self.date(9, 30, 23)
    #expect(when(try Self.item(due: tonight)) == .due(tonight, urgent: true))
    let nextWeek = Self.date(10, 6)
    #expect(when(try Self.item(due: nextWeek)) == .due(nextWeek, urgent: false))
    #expect(when(try Self.item(planned: Self.date(9, 29))) == .today)
    let friday = Self.date(10, 2)
    #expect(when(try Self.item(defer: friday)) == .weekday(friday))
    let tuesday = Self.date(10, 6)
    #expect(when(try Self.item(planned: tuesday)) == .date(tuesday))
    // An old defer date is not today's work (Today's rule): its date, not `today`.
    let longAgo = Self.date(9, 27)
    #expect(when(try Self.item(defer: longAgo)) == .date(longAgo))
    #expect(when(try Self.item()) == .none)
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
}
