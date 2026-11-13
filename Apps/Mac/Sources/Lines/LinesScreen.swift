import Foundation
import MoonShineCore

/// What Lines shows, as values (`design/screens/lines.md`). Dates are formatted in `timeZone`,
/// the workspace's zone.
struct LinesScreen: Equatable {
  struct Row: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    let block: String
    let state: LineState
    let isFoundation: Bool
    /// Held for removal: no longer in the budget note (owner, 2026-11-12).
    let isHeld: Bool
    let budget: LinesFormat.Budget
    let sparkline: [WeekPoint]
    let last: LastActivity
    let nextActions: Int
    let estimateMinutes: Int

    /// An active line that is quiet or has no completions reads secondary
    /// (`design/components.md` § LineStateLabel).
    var isStateSecondary: Bool {
      switch (state, last) {
      case (.maintenance, _), (.active, .quiet), (.active, .noCompletions): true
      default: false
      }
    }
  }

  struct Tier: Identifiable, Hashable {
    let kind: LineTier.Kind
    let rows: [Row]
    let weeklyBudgetHours: Double?
    let floor: LinesFormat.Floor?
    var id: LineTier.Kind { kind }
  }

  /// One count of the subtitle.
  enum Count: Hashable {
    case lines(Int)
    case foundation(Int)
    case active(Int)
    case maintenance(Int)
    case paused(Int)
  }

  let tiers: [Tier]
  /// `11 lines · 2 foundation · …`, zero counts left out (owner, 2026-11-12).
  let counts: [Count]
  /// The weeks of the sparklines, oldest first; empty without a line.
  let weeks: [Int]
  let today: Date
  let timeZone: TimeZone

  init(_ overview: Overview) {
    let lines = overview.lines()
    let held = Set(overview.workspace.heldLineRemoval.map(\.id))
    tiers = lines.tiers.map { tier in
      Tier(
        kind: tier.kind,
        rows: tier.rows.map { row in
          let line = row.line
          return Row(
            id: line.id, emoji: line.emoji, name: line.name, block: line.block, state: line.state,
            isFoundation: line.foundation, isHeld: held.contains(line.id),
            budget: LinesFormat.budget(line), sparkline: row.activity.sparkline,
            last: row.activity.last, nextActions: row.activity.nextActions,
            estimateMinutes: row.activity.estimatedThisWeekMinutes)
        },
        weeklyBudgetHours: tier.weeklyBudgetHours,
        floor: LinesFormat.floor(tier.dailyFloorHours))
    }
    let c = lines.counts
    counts = [
      .lines(c.lines), .foundation(c.foundation), .active(c.active),
      .maintenance(c.maintenance), .paused(c.paused),
    ].filter { $0.value > 0 }
    weeks = tiers.first?.rows.first?.sparkline.map(\.week.week) ?? []
    today = overview.now
    timeZone = overview.workspace.timeZone
  }
}

extension LinesScreen.Count {
  var value: Int {
    switch self {
    case .lines(let n), .foundation(let n), .active(let n), .maintenance(let n), .paused(let n): n
    }
  }
}
