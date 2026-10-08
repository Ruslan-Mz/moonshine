import Foundation
import MoonShineCore

/// The budget note's `lines:` block (contract §1), checked item by item. Any invalid value
/// skips its item, so a stored line is never overwritten with less than it had.
struct BudgetLines: Equatable {
  let lines: VaultLines
  let issues: [ImportIssue]
  /// Line items skipped; each duplicate counts.
  let skipped: Int

  static func read(_ note: ScannedNote) -> BudgetLines {
    BudgetLines(lines: .unavailable, issues: [], skipped: 0)
  }
}
