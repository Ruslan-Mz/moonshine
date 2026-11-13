import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

private func line(
  foundation: Bool = false, budget: Double? = nil, floor: Double? = nil
) -> Line {
  Line(
    id: .generate(), refs: [], key: "line", name: "Line", emoji: nil, block: "Block",
    state: .active, budgetHoursPerWeek: budget, parentLink: nil, taskRules: LineTaskRules(),
    foundation: foundation, floorHoursPerDay: floor)
}

@Suite(.serialized) struct LinesScreenTests {
  // MARK: Budget cell (`design/screens/lines.md` § Draft-5)

  @Test(arguments: [
    (0.33, LinesFormat.Floor.minutes(20)), (0.99, .minutes(59)), (0.02, .minutes(1)),
    (0.004, .minutes(1)), (0.5, .minutes(30)), (1, .hours(1)), (1.25, .hours(1.25)),
    (1.5, .hours(1.5)), (4, .hours(4)),
  ])
  func floorFormat(hours: Double, expected: LinesFormat.Floor) {
    #expect(LinesFormat.floor(hours) == expected)
  }

  @Test func noFloorAtZeroNegativeOrUnset() {
    #expect(LinesFormat.floor(0) == nil)
    #expect(LinesFormat.floor(-1) == nil)
    #expect(LinesFormat.floor(nil) == nil)
    #expect(LinesFormat.floor(.infinity) == nil)
  }

  @Test func budgetCellFollowsTheTable() {
    #expect(LinesFormat.budget(line(budget: 6)) == .weekly(6))
    #expect(LinesFormat.budget(line(foundation: true, budget: 9, floor: 3)) == .floor(.hours(3)))
    #expect(
      LinesFormat.budget(line(budget: 4, floor: 0.33)) == .weeklyOverFloor(4, .minutes(20)))
    #expect(LinesFormat.budget(line(floor: 0.5)) == .floor(.minutes(30)))
    #expect(LinesFormat.budget(line()) == .none)
    #expect(LinesFormat.budget(line(floor: 0)) == .none)
    // An owner-set 0 is a budget: `0 h / week` (owner, 2026-11-12).
    #expect(LinesFormat.budget(line(budget: 0)) == .weekly(0))
    #expect(LinesFormat.budget(line(budget: 0, floor: 0)) == .weekly(0))
  }

  @Test func hoursUseTheLocaleSeparatorAndNoTrailingZeros() {
    let english = Locale(identifier: "en_GB")
    let russian = Locale(identifier: "ru")
    #expect(1.0.formatted(LinesFormat.hours.locale(english)) == "1")
    #expect(1.25.formatted(LinesFormat.hours.locale(english)) == "1.25")
    #expect(1.5.formatted(LinesFormat.hours.locale(russian)) == "1,5")
  }

  // MARK: Sparkline

  @Test func barsShareOneScaleWithAFloorForNonZeroValues() {
    #expect(LinesFormat.bars([12, 0, 6, 1]) == [24, 0, 12, 3])
    #expect(LinesFormat.bars([0, 0]) == [0, 0])
    #expect(LinesFormat.bars([]) == [])
    #expect(LinesFormat.bars([Int.max, 1]) == [24, 3])
  }

  // MARK: Columns

  @Test func theNarrowestLinesIsEveryColumnAtItsMinimum() {
    #expect(LinesColumns.lineMinimum < LinesColumns.lineIdeal)
    #expect(LinesColumns.lastMinimum < LinesColumns.lastIdeal)
    #expect(
      LinesColumns.minimumWidth == 150 + 96 + 110 + 176 + 130 + 64 + 110 + LinesColumns.margins)
    // At 1100×700 with a 200 pt sidebar the detail has about 900.
    #expect(LinesColumns.minimumWidth <= 900)
  }

  // MARK: Demo (`design/demo-data.md` § Lines)

  @MainActor @Test func demoSubtitleTiersAndCells() async throws {
    let screen = LinesScreen(try await demoOverview())
    #expect(
      screen.counts == [.lines(11), .foundation(2), .active(7), .maintenance(1), .paused(1)])
    #expect(screen.tiers.map(\.kind) == [.foundation, .active, .maintenance, .paused])
    #expect(screen.tiers.first?.floor == .hours(4))
    let rows = screen.tiers.flatMap(\.rows)
    let math = try #require(rows.first { $0.name.contains("Math") })
    #expect(math.budget == .weeklyOverFloor(4, .minutes(20)))
    #expect(screen.tiers.last?.rows.count == 1)
    #expect(screen.tiers.last?.rows.first?.state == .paused)
    #expect(screen.weeks == Array(33...40))
    #expect(rows.filter(\.isHeld).isEmpty)
    // A foundation line shows its floor only.
    for row in screen.tiers[0].rows {
      guard case .floor = row.budget else {
        Issue.record("\(row.name): \(row.budget)")
        continue
      }
    }
  }

  @MainActor @Test func zeroCountsAreLeftOutOfTheSubtitle() async throws {
    let overview = try await demoOverview()
    var workspace = overview.workspace
    workspace.lines.removeAll { $0.state == .paused || $0.state == .maintenance }
    let screen = LinesScreen(Overview(workspace: workspace, now: overview.now))
    #expect(screen.counts == [.lines(9), .foundation(2), .active(7)])
  }

  @MainActor @Test func aHeldLineIsMarked() async throws {
    let overview = try await demoOverview()
    let held = try #require(overview.workspace.lines.first)
    var workspace = overview.workspace
    workspace.issues.append(.lineRemovalHeld([held.key]))
    let screen = LinesScreen(Overview(workspace: workspace, now: overview.now))
    let rows = screen.tiers.flatMap(\.rows)
    #expect(rows.filter(\.isHeld).map(\.id) == [held.id])
  }

  @Test func quietOrNoCompletionsReadsTheStateSecondary() {
    func row(_ state: LineState, _ last: LastActivity) -> LinesScreen.Row {
      LinesScreen.Row(
        id: .generate(), emoji: nil, name: "Line", block: "Block", state: state,
        isFoundation: false, isHeld: false, budget: .none, sparkline: [], last: last,
        nextActions: 0, estimateMinutes: 0)
    }
    #expect(row(.active, .quiet(days: 14)).isStateSecondary)
    #expect(row(.active, .noCompletions(since: nil)).isStateSecondary)
    #expect(!row(.active, .daysAgo(3)).isStateSecondary)
    #expect(row(.maintenance, .daysAgo(29)).isStateSecondary)
  }
}
