import Foundation

// MARK: - Today

public enum TodayReason: Hashable, Sendable {
  case planned, deferred, flagged, due
}

public struct TodayItem: Hashable, Sendable {
  public let task: TaskItem
  public let trace: Trace
  public let reasons: Set<TodayReason>
  /// Only a real due date on or before today makes an item urgent.
  public let isUrgent: Bool
  /// Calendar days since the planned date, for items carried over from earlier days.
  public let plannedDaysAgo: Int?
  public let isDone: Bool
}

public struct LineGroup: Hashable, Sendable {
  public let line: LineAssignment
  public let items: [TodayItem]
}

/// An active line without recent completions: a fact with a next step, never a warning.
/// Foundation lines are never quiet.
public struct QuietLine: Hashable, Sendable {
  public enum Reason: Hashable, Sendable {
    /// Calendar days since the line's last completion, and that completed task.
    case quiet(days: Int, last: TaskItem)
    /// No completed task in the store since `since`, the start of the task provider's
    /// window; nil when the window start is not known (owner, 2026-10-27; S4-4c-3).
    case noActivity(since: Date?)
  }

  public let line: Line
  public let reason: Reason
  /// The line's first available next action in source order (owner, 2026-10-24); nil when
  /// it has none.
  public let nextStep: TaskItem?
}

/// A line with a task completed today, with that day's sessions and tasks.
public struct TouchedLine: Hashable, Sendable {
  public let line: LineAssignment
  public let counts: WeekCounts
}

/// The current quarter's focus: its quarter note and that note's artifacts, dropped ones left
/// out (owner, 2026-10-28).
public struct QuarterFocus: Hashable, Sendable {
  public let note: NoteRef
  /// Source order.
  public let artifacts: [Artifact]

  public var doneCount: Int { artifacts.filter { $0.status == .done }.count }
}

public struct TodayTotals: Hashable, Sendable {
  public let open: Int
  public let done: Int
  /// Sum of the open items' positive estimates: an estimate, never a measured time.
  public let estimateMinutes: Int

  public init(open: Int, done: Int, estimateMinutes: Int) {
    self.open = open
    self.done = done
    self.estimateMinutes = estimateMinutes
  }
}

public struct TodayOverview: Hashable, Sendable {
  public let day: Horizon
  /// Every item of the day once, in source order: the open items and every task done today.
  public let items: [TodayItem]
  /// Every anchor among `items`, open and done, in source order; the strip shows the first
  /// `Overview.anchorsShown`, and only those leave their sections.
  public let anchors: [TodayItem]
  /// Top 3: open flagged items not shown in the strip, a due date today or earlier first,
  /// then source order; the first three, or all of them when asked.
  public let top: [TodayItem]
  /// Every Top 3 candidate, shown or not.
  public let flaggedCount: Int
  /// Foundation lines first, then vault line order, Life ops last; open items only, without
  /// the strip's and Top 3's.
  public let groups: [LineGroup]
  /// Planned on an earlier day and still open; oldest first.
  public let fromEarlier: [TodayItem]
  /// Every task completed today but the done anchors in the strip, most recent first; in no
  /// other section.
  public let doneToday: [TodayItem]
  public let totals: TodayTotals
  /// Vault order, Life ops last; paused lines are left out (owner, 2026-10-27).
  public let touchedToday: [TouchedLine]
  /// Vault order.
  public let quietLines: [QuietLine]
  /// Lines paused on purpose, in vault order.
  public let pausedLines: [Line]
  /// Nil without a current quarter note, or when it has no artifacts (owner, 2026-10-28).
  public let quarterFocus: QuarterFocus?
}

// MARK: - Week

public struct WeekItem: Hashable, Sendable {
  public let task: TaskItem
  public let trace: Trace
  public let hasDueBadge: Bool
}

public struct WeekDay: Hashable, Sendable {
  public let day: Horizon
  public let items: [WeekItem]
}

public struct LineWeekHeader: Hashable, Sendable {
  public let line: LineAssignment
  public let thisWeek: WeekCounts
  public let previousAverage: WeekAverage
}

public struct WeekOverview: Hashable, Sendable {
  public let week: ISOWeek
  /// Monday to Sunday.
  public let days: [WeekDay]
  /// Available tasks in active lines without any date.
  public let noPlan: [WeekItem]
  public let header: [LineWeekHeader]
}

// MARK: - Lines

/// A line's last completion as Lines shows it; the same rule as Today's quiet lines.
public enum LastActivity: Hashable, Sendable {
  case today
  case yesterday
  /// Two days or more, and not quiet: maintenance and foundation lines are never quiet.
  case daysAgo(Int)
  case quiet(days: Int)
  /// No completed task in the store since `since`, the start of the task provider's window;
  /// nil when the window start is not known.
  case noCompletions(since: Date?)
  /// Paused on purpose; its last completion, nil when the store has none (owner, 2026-10-30).
  case paused(last: Date?)
}

public struct LineActivity: Hashable, Sendable {
  /// 8 weeks, oldest first; the last one is the current, partial week.
  public let sparkline: [WeekPoint]
  public let last: LastActivity
  public let nextActions: Int
  /// Sum of the positive estimates of the tasks placed in the current week: an estimate
  /// (`Overview.estimatedThisWeek`).
  public let estimatedThisWeekMinutes: Int
}

public struct LineRow: Hashable, Sendable {
  public let line: Line
  public let activity: LineActivity
}

/// A section of Lines (design draft-2): tiers replace blocks.
public struct LineTier: Hashable, Sendable {
  public enum Kind: Hashable, Sendable, CaseIterable {
    case foundation, active, maintenance, paused

    /// Paused wins over foundation: "on purpose" (owner, 2026-10-30).
    public init(_ line: Line) {
      switch line.state {
      case .paused: self = .paused
      case _ where line.foundation: self = .foundation
      case .active: self = .active
      case .maintenance: self = .maintenance
      }
    }
  }

  public let kind: Kind
  /// Vault order.
  public let rows: [LineRow]
  /// Sum of the rows' weekly budgets; nil when no row has one.
  public let weeklyBudgetHours: Double?
  /// The foundation tier only: sum of the rows' daily floors above zero; nil when none.
  public let dailyFloorHours: Double?
}

public struct LineCounts: Hashable, Sendable {
  public let lines: Int
  public let foundation: Int
  public let active: Int
  public let maintenance: Int
  public let paused: Int

  public init(lines: Int, foundation: Int, active: Int, maintenance: Int, paused: Int) {
    self.lines = lines
    self.foundation = foundation
    self.active = active
    self.maintenance = maintenance
    self.paused = paused
  }
}

public struct LinesOverview: Hashable, Sendable {
  /// Foundation, active, maintenance, paused; empty tiers left out.
  public let tiers: [LineTier]
  public let counts: LineCounts
  public let lifeOps: LineActivity
}

// MARK: - Service

/// Today, Week and Lines, computed from the store's workspace at `now` in its time zone.
public struct Overview: Sendable {
  public let workspace: Workspace
  public let now: Date
  public let calendar: Calendar
  public let stats: Stats
  public let tracer: Tracer

  public static let quietAfterDays = 14
  public static let anchorsShown = 5
  public static let topShown = 3
  /// The tag that makes a task an anchor, matched by leaf name on the task's own tags.
  public static let anchorTag = "anchor"
  public static let sparklineWeeks = 8

  public init(workspace: Workspace, now: Date) {
    self.workspace = workspace
    self.now = now
    self.calendar = .iso8601(in: workspace.timeZone)
    self.stats = Stats(workspace: workspace, now: now)
    self.tracer = Tracer(workspace: workspace, now: now)
  }

  /// Vault line order, Life ops last.
  private var lineOrder: [LineAssignment] {
    workspace.lines.map { .line($0.id) } + [.lifeOps]
  }

  private var available: [TaskItem] {
    workspace.tasks.filter { $0.status == .available }
  }

  /// Available tasks that are not the parent of another available task, in source order.
  private var nextActions: [TaskItem] {
    let available = available
    let parents = Set(available.compactMap(\.parentTaskID))
    return available.filter { !parents.contains($0.id) }
  }

  private func day(containing date: Date) -> Horizon {
    Horizon.containing(date, scale: .day, calendar: calendar)
      ?? Horizon(scale: .day, start: date, end: date)
  }

  private func calendarDays(from date: Date, to day: Horizon) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: day.start).day ?? 0
  }

  // MARK: Today

  /// Foundation lines, then the other lines, each in vault order; Life ops last.
  private var todayLineOrder: [LineAssignment] {
    let lines = workspace.lines.filter(\.foundation) + workspace.lines.filter { !$0.foundation }
    return lines.map { .line($0.id) } + [.lifeOps]
  }

  /// Today's open items and every task completed today, in source order.
  private func todayItems(_ day: Horizon) -> [TodayItem] {
    workspace.tasks.compactMap { task in
      let isDone = task.status == .completed && task.completedAt.map(day.contains) == true
      guard task.status == .available || isDone else { return nil }
      var reasons: Set<TodayReason> = []
      if let due = task.effectiveDueAt, due < day.end { reasons.insert(.due) }
      if task.flagged { reasons.insert(.flagged) }
      if let deferUntil = task.effectiveDeferUntil, day.contains(deferUntil) {
        reasons.insert(.deferred)
      }
      if let planned = task.effectivePlannedAt, planned < day.end { reasons.insert(.planned) }
      guard isDone || !reasons.isEmpty else { return nil }
      let plannedEarlier = task.effectivePlannedAt.flatMap { $0 < day.start ? $0 : nil }
      return TodayItem(
        task: task, trace: tracer.trace(task), reasons: reasons,
        isUrgent: !isDone && reasons.contains(.due),
        plannedDaysAgo: isDone ? nil : plannedEarlier.map { calendarDays(from: $0, to: day) },
        isDone: isDone)
    }
  }

  public func today(showAllFlagged: Bool = false) -> TodayOverview {
    let day = day(containing: now)
    let items = todayItems(day)
    let open = items.filter { !$0.isDone }

    let anchorTags = Set(workspace.tags.filter { $0.matchesLeafName(Self.anchorTag) }.map(\.id))
    let anchors = items.filter { $0.task.tagIDs.contains(where: anchorTags.contains) }
    let inStrip = Set(anchors.prefix(Self.anchorsShown).map(\.task.id))
    let candidates = open.filter { $0.task.flagged && !inStrip.contains($0.task.id) }
    let dueByToday = { (item: TodayItem) in item.task.effectiveDueAt.map { $0 < day.end } == true }
    let ranked = candidates.filter(dueByToday) + candidates.filter { !dueByToday($0) }
    let top = showAllFlagged ? ranked : Array(ranked.prefix(Self.topShown))
    let lifted = inStrip.union(top.map(\.task.id))

    var byLine: [LineAssignment: [TodayItem]] = [:]
    var earlier: [TodayItem] = []
    for item in open where !lifted.contains(item.task.id) {
      if item.plannedDaysAgo != nil {
        earlier.append(item)
      } else {
        byLine[item.task.line, default: []].append(item)
      }
    }
    // Most recent first; the same completion time keeps source order. A done anchor in the
    // strip stays only there (owner, 2026-10-26).
    let done = items.filter(\.isDone)
    let doneToday = done.enumerated().filter { !inStrip.contains($0.element.task.id) }.sorted {
      let (a, b) = ($0.element.task.completedAt ?? now, $1.element.task.completedAt ?? now)
      return a != b ? a > b : $0.offset < $1.offset
    }.map(\.element)
    let estimate = open.compactMap(\.task.estimateMinutes).filter { $0 > 0 }.reduce(0) {
      let (total, overflow) = $0.addingReportingOverflow($1)
      return overflow ? .max : total
    }

    let paused = workspace.lines.filter { $0.state == .paused }
    let touched = Set(done.map(\.task.line)).subtracting(paused.map { .line($0.id) })
    return TodayOverview(
      day: day, items: items, anchors: anchors, top: top, flaggedCount: candidates.count,
      groups: todayLineOrder.compactMap { line in
        byLine[line].map { LineGroup(line: line, items: $0) }
      },
      fromEarlier: earlier.sorted {
        ($0.task.effectivePlannedAt ?? now) < ($1.task.effectivePlannedAt ?? now)
      },
      doneToday: doneToday,
      totals: TodayTotals(open: open.count, done: done.count, estimateMinutes: estimate),
      touchedToday: lineOrder.filter(touched.contains).map {
        TouchedLine(line: $0, counts: stats.dayCounts($0, on: now))
      },
      quietLines: quietLines(day), pausedLines: paused, quarterFocus: quarterFocus())
  }

  /// The first quarter note by path whose quarter holds `now`, chosen by type as the Tracer
  /// chooses year notes, and only with a quarter period: the reader keeps a `quarter_focus`
  /// note with any period, and the card's quarter comes from it. Its artifacts in source
  /// order, dropped ones left out.
  private func quarterFocus() -> QuarterFocus? {
    guard
      let note = workspace.notes.first(where: {
        $0.type == "quarter_focus" && $0.period?.scale == .quarter
          && $0.period?.contains(now) == true
      })
    else { return nil }
    let artifacts = workspace.artifacts.filter { $0.noteID == note.id && $0.status != .dropped }
    return artifacts.isEmpty ? nil : QuarterFocus(note: note, artifacts: artifacts)
  }

  /// Active lines with no completion for `quietAfterDays`, foundation lines never (owner,
  /// 2026-10-24), or with none at all, foundation lines included (owner, 2026-10-28).
  private func quietLines(_ day: Horizon) -> [QuietLine] {
    let lastDone = lastCompletions
    let firstNext = Dictionary(
      nextActions.map { ($0.line, $0) }, uniquingKeysWith: { first, _ in first })
    return workspace.lines.filter { $0.state == .active }.compactMap { line in
      let next = firstNext[.line(line.id)]
      guard let last = lastDone[.line(line.id)], let done = last.completedAt else {
        return QuietLine(
          line: line, reason: .noActivity(since: workspace.completedSince), nextStep: next)
      }
      let days = calendarDays(from: done, to: day)
      guard isQuiet(line, days: days) else { return nil }
      return QuietLine(line: line, reason: .quiet(days: days, last: last), nextStep: next)
    }
  }

  /// Each line's latest completion; the first in source order on a tie. Today and Lines both
  /// read it, so the two cannot disagree.
  private var lastCompletions: [LineAssignment: TaskItem] {
    var lastDone: [LineAssignment: TaskItem] = [:]
    for task in workspace.tasks where task.status == .completed {
      guard let done = task.completedAt else { continue }
      if let current = lastDone[task.line]?.completedAt, current >= done { continue }
      lastDone[task.line] = task
    }
    return lastDone
  }

  /// Quiet: an active line, not foundation, `quietAfterDays` or more since its last completion.
  private func isQuiet(_ line: Line, days: Int) -> Bool {
    line.state == .active && !line.foundation && days >= Self.quietAfterDays
  }

  // MARK: Week

  public func week() -> WeekOverview {
    let week = ISOWeek(containing: now, calendar: calendar)
    let range = week.horizon(calendar: calendar) ?? day(containing: now)
    let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
      .map { day(containing: $0) }
    let activeLines = Set(workspace.lines.filter { $0.state == .active }.map(\.id))

    var items: [[WeekItem]] = Array(repeating: [], count: days.count)
    var noPlan: [WeekItem] = []
    for task in available {
      guard
        let anchor = task.effectivePlannedAt ?? task.effectiveDeferUntil ?? task.effectiveDueAt
      else {
        if case .line(let id) = task.line, activeLines.contains(id) {
          noPlan.append(WeekItem(task: task, trace: tracer.trace(task), hasDueBadge: false))
        }
        continue
      }
      guard let index = days.firstIndex(where: { $0.contains(anchor) }) else { continue }
      items[index].append(
        WeekItem(
          task: task, trace: tracer.trace(task),
          hasDueBadge: task.effectiveDueAt.map(range.contains) ?? false))
    }
    return WeekOverview(
      week: week,
      days: zip(days, items).map { WeekDay(day: $0, items: $1) },
      noPlan: noPlan,
      header: lineOrder.map { line in
        LineWeekHeader(
          line: line, thisWeek: stats.counts(line, in: week),
          previousAverage: stats.average(line, before: week))
      })
  }

  // MARK: Lines

  public func lines() -> LinesOverview {
    let nextActions = Dictionary(grouping: nextActions, by: \.line)
    let lastDone = lastCompletions
    let estimates = estimatedThisWeek()
    let day = day(containing: now)
    func activity(_ assignment: LineAssignment, _ line: Line?) -> LineActivity {
      LineActivity(
        sparkline: stats.series(
          assignment, endingAt: stats.currentWeek, count: Self.sparklineWeeks),
        last: lastActivity(line, completed: lastDone[assignment]?.completedAt, day: day),
        nextActions: nextActions[assignment]?.count ?? 0,
        estimatedThisWeekMinutes: estimates[assignment] ?? 0)
    }

    let rows = workspace.lines.map { LineRow(line: $0, activity: activity(.line($0.id), $0)) }
    let byKind = Dictionary(grouping: rows) { LineTier.Kind($0.line) }
    let tiers = LineTier.Kind.allCases.compactMap { kind -> LineTier? in
      guard let rows = byKind[kind] else { return nil }
      let budgets = rows.compactMap(\.line.budgetHoursPerWeek)
      let floors = rows.compactMap(\.line.floorHoursPerDay).filter { $0 > 0 }
      return LineTier(
        kind: kind, rows: rows, weeklyBudgetHours: budgets.isEmpty ? nil : budgets.reduce(0, +),
        dailyFloorHours: kind == .foundation && !floors.isEmpty ? floors.reduce(0, +) : nil)
    }
    let count = { (kind: LineTier.Kind) in byKind[kind]?.count ?? 0 }
    return LinesOverview(
      tiers: tiers,
      counts: LineCounts(
        lines: rows.count, foundation: count(.foundation), active: count(.active),
        maintenance: count(.maintenance), paused: count(.paused)),
      lifeOps: activity(.lifeOps, nil))
  }

  /// `nil` for Life ops, which is never quiet and never paused.
  private func lastActivity(_ line: Line?, completed: Date?, day: Horizon) -> LastActivity {
    if line?.state == .paused { return .paused(last: completed) }
    guard let completed else { return .noCompletions(since: workspace.completedSince) }
    let days = calendarDays(from: completed, to: day)
    // A completion after today's start (a clock set back) reads today, never a negative count.
    if days <= 0 { return .today }
    if days == 1 { return .yesterday }
    if let line, isQuiet(line, days: days) { return .quiet(days: days) }
    return .daysAgo(days)
  }

  /// Estimated this week (owner, 2026-11-12; `docs/specs/phase-1-see.md` → S4-2): the positive
  /// estimates of each line's open leaf tasks whose anchor (planned, else defer, else due) lies
  /// in the current week, available, or blocked with a defer date after now. The store cannot
  /// tell a deferred task from one a sequential project blocks, so that clause stands in for
  /// "blocked only by its own defer date". Saturating.
  private func estimatedThisWeek() -> [LineAssignment: Int] {
    let week =
      ISOWeek(containing: now, calendar: calendar).horizon(calendar: calendar)
      ?? day(containing: now)
    let open = workspace.tasks.filter { $0.status == .available || $0.status == .blocked }
    let parents = Set(open.compactMap(\.parentTaskID))
    var totals: [LineAssignment: Int] = [:]
    for task in open where !parents.contains(task.id) {
      let deferredLater = task.effectiveDeferUntil.map { $0 > now } ?? false
      if task.status == .blocked && !deferredLater { continue }
      guard
        let anchor = task.effectivePlannedAt ?? task.effectiveDeferUntil ?? task.effectiveDueAt,
        week.contains(anchor), let estimate = task.estimateMinutes, estimate > 0
      else { continue }
      let (total, overflow) = (totals[task.line] ?? 0).addingReportingOverflow(estimate)
      totals[task.line] = overflow ? .max : total
    }
    return totals
  }
}
