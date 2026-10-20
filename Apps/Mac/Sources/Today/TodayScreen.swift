import Foundation
import MoonShineCore

/// What Today shows, as values: dates, counts and titles. The views format them in
/// `timeZone`, the workspace's zone, never the Mac's.
struct TodayScreen: Equatable {
  struct Row: Identifiable, Hashable {
    let id: TaskItemID
    let title: String
    /// project → line → artifact (or the line's parent note); a missing step is left out.
    let trace: [String]
    let estimateMinutes: Int?
    /// The effective due date, shown as a date only until S4-3a brings the default times.
    let due: Date?
    let isUrgent: Bool
    let plannedDaysAgo: Int?
  }

  struct Section: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    let rows: [Row]
  }

  let day: Date
  let week: Int
  let timeZone: TimeZone
  /// Vault line order; Life ops is not among them.
  let sections: [Section]
  let fromEarlier: [Row]
  let lifeOps: [Row]

  /// Sum of the Life ops estimates; an estimate, over the tasks that have one.
  var lifeOpsEstimateMinutes: Int { lifeOps.compactMap(\.estimateMinutes).reduce(0, +) }

  init(_ overview: Overview) {
    let today = overview.today()
    day = overview.now
    week = ISOWeek(containing: overview.now, calendar: overview.calendar).week
    timeZone = overview.workspace.timeZone
    let lines = Dictionary(
      overview.workspace.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    sections = today.groups.compactMap { group in
      guard case .line(let id) = group.line, let line = lines[id] else { return nil }
      return Section(
        id: id, emoji: line.emoji, name: line.name, rows: group.items.map(Self.row))
    }
    fromEarlier = today.fromEarlier.map(Self.row)
    lifeOps = today.groups.first { $0.line == .lifeOps }?.items.map(Self.row) ?? []
  }

  private static func row(_ item: TodayItem) -> Row {
    Row(
      id: item.task.id, title: item.task.title, trace: trace(item.trace),
      estimateMinutes: item.task.estimateMinutes, due: item.task.effectiveDueAt,
      isUrgent: item.isUrgent, plannedDaysAgo: item.plannedDaysAgo)
  }

  private static func trace(_ trace: Trace) -> [String] {
    let line = trace.lineEntity.map {
      [$0.emoji, $0.name].compactMap { $0 }.joined(separator: " ")
    }
    let target: String? =
      switch trace.target {
      case .artifact(let artifact): artifact.title
      case .note(let note): note.title
      case nil: nil
      }
    return [trace.project?.title, line, target].compactMap { $0 }
  }
}
