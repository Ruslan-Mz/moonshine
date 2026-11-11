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
    /// The effective due date, shown as a date only until S4-3b shows due times (owner, 2026-10-28).
    let due: Date?
    let isUrgent: Bool
    let plannedDaysAgo: Int?
    let isDone: Bool
  }

  /// One chip of the Anchors strip.
  struct Anchor: Identifiable, Hashable {
    let id: TaskItemID
    let title: String
    let emoji: String?
    let isDone: Bool
  }

  struct Section: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    let rows: [Row]
  }

  /// A row of Touched today: the day's sessions and tasks, never summed.
  struct Touched: Identifiable, Hashable {
    let id: LineAssignment
    let emoji: String?
    /// Nil for Life ops, which the view names in the UI language.
    let name: String?
    let sessions: Int
    let tasks: Int
  }

  /// The line's first available next action in source order (owner, 2026-10-24).
  struct NextStep: Hashable {
    let title: String
    let estimateMinutes: Int?
  }

  struct Quiet: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    let days: Int
    let lastTitle: String
    let lastDate: Date
    let next: NextStep?
  }

  struct NoActivity: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    /// The start of OmniFocus' completed-task window; nil when not known (S4-4c-3).
    let since: Date?
    let next: NextStep?
  }

  struct Paused: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
  }

  /// The Quarter focus card: the current quarter note's artifacts, dropped ones left out.
  struct QuarterFocus: Equatable {
    struct Row: Identifiable, Hashable {
      let id: ArtifactID
      let emoji: String?
      let title: String
      let isDone: Bool
    }

    /// 1–4, from the note's period in the workspace's time zone.
    let quarter: Int
    let rows: [Row]
    var done: Int { rows.filter(\.isDone).count }
  }

  let day: Date
  let week: Int
  let timeZone: TimeZone
  /// The strip's chips: the first `Overview.anchorsShown` of today's anchors.
  let anchors: [Anchor]
  let anchorsTotal: Int
  let anchorsDone: Int
  let top: [Row]
  let flaggedCount: Int
  /// Foundation lines first, then vault order; Life ops is not among them.
  let sections: [Section]
  let fromEarlier: [Row]
  let lifeOps: [Row]
  /// Most recent first.
  let doneToday: [Row]
  let totals: TodayTotals
  /// The rail: vault order, Life ops last; paused lines are not touched (owner, 2026-10-27).
  let touched: [Touched]
  let quiet: [Quiet]
  let noActivity: [NoActivity]
  let paused: [Paused]
  let quarterFocus: QuarterFocus?

  /// With nothing to show, the rail holds one calm line (owner, 2026-10-27).
  var railIsEmpty: Bool {
    quarterFocus == nil && touched.isEmpty && quiet.isEmpty && noActivity.isEmpty
      && paused.isEmpty
  }

  /// Done today shows the most recent ones; the rest sit behind "N more".
  static let doneShown = 3

  var doneVisible: [Row] { Array(doneToday.prefix(Self.doneShown)) }
  var doneMore: [Row] { Array(doneToday.dropFirst(Self.doneShown)) }

  /// `5 flagged — 3 shown` and its toggle, only with more candidates than Top 3 holds.
  var showsFlaggedCaption: Bool { flaggedCount > Overview.topShown }

  /// Sum of the Life ops estimates; an estimate, over the tasks that have a positive one.
  /// The snapshot validator bounds each estimate; the sum still never traps.
  var lifeOpsEstimateMinutes: Int {
    lifeOps.compactMap(\.estimateMinutes).filter { $0 > 0 }.reduce(0) { sum, minutes in
      let (total, overflow) = sum.addingReportingOverflow(minutes)
      return overflow ? .max : total
    }
  }

  init(_ overview: Overview, showAllFlagged: Bool = false) {
    let today = overview.today(showAllFlagged: showAllFlagged)
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
    anchors = today.anchors.prefix(Overview.anchorsShown).map { item in
      Anchor(
        id: item.task.id, title: item.task.title,
        emoji: item.task.line == .lifeOps ? "🧺" : item.trace.lineEntity?.emoji,
        isDone: item.isDone)
    }
    anchorsTotal = today.anchors.count
    anchorsDone = today.anchors.filter(\.isDone).count
    top = today.top.map(Self.row)
    flaggedCount = today.flaggedCount
    doneToday = today.doneToday.map(Self.row)
    totals = today.totals
    touched = today.touchedToday.compactMap { row in
      let (sessions, tasks) = (row.counts.rhythm, row.counts.progress)
      guard case .line(let id) = row.line else {
        return Touched(id: row.line, emoji: "🧺", name: nil, sessions: sessions, tasks: tasks)
      }
      guard let line = lines[id] else { return nil }
      return Touched(
        id: row.line, emoji: line.emoji, name: line.name, sessions: sessions, tasks: tasks)
    }
    var quiet: [Quiet] = []
    var noActivity: [NoActivity] = []
    for line in today.quietLines {
      let next = line.nextStep.map {
        NextStep(title: $0.title, estimateMinutes: $0.estimateMinutes)
      }
      switch line.reason {
      case .quiet(let days, let last):
        guard let done = last.completedAt else { continue }
        quiet.append(
          Quiet(
            id: line.line.id, emoji: line.line.emoji, name: line.line.name, days: days,
            lastTitle: last.title, lastDate: done, next: next))
      case .noActivity(let since):
        noActivity.append(
          NoActivity(
            id: line.line.id, emoji: line.line.emoji, name: line.line.name, since: since,
            next: next))
      }
    }
    self.quiet = quiet
    self.noActivity = noActivity
    paused = today.pausedLines.map { Paused(id: $0.id, emoji: $0.emoji, name: $0.name) }
    quarterFocus = today.quarterFocus.flatMap { focus in
      guard let start = focus.note.period?.start else { return nil }
      let month = overview.calendar.component(.month, from: start)
      return QuarterFocus(
        quarter: (month - 1) / 3 + 1,
        rows: focus.artifacts.map { artifact in
          QuarterFocus.Row(
            id: artifact.id, emoji: artifact.lineIDs.lazy.compactMap { lines[$0]?.emoji }.first,
            title: artifact.title, isDone: artifact.status == .done)
        })
    }
  }

  private static func row(_ item: TodayItem) -> Row {
    Row(
      id: item.task.id, title: item.task.title, trace: trace(item.trace),
      estimateMinutes: item.task.estimateMinutes, due: item.task.effectiveDueAt,
      isUrgent: item.isUrgent, plannedDaysAgo: item.plannedDaysAgo, isDone: item.isDone)
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
