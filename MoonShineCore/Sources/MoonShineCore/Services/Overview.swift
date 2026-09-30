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
}

public struct LineGroup: Hashable, Sendable {
  public let line: LineAssignment
  public let items: [TodayItem]
}

/// An active line without recent completions: a fact with a next step, never a warning.
public struct QuietLine: Hashable, Sendable {
  public enum Reason: Hashable, Sendable {
    case lastActivity(Date)
    case noActivityYet
  }

  public let line: Line
  public let reason: Reason
}

public struct TodayOverview: Hashable, Sendable {
  public let day: Horizon
  /// In vault line order, Life ops last.
  public let groups: [LineGroup]
  /// Planned on an earlier day and still open; oldest first.
  public let fromEarlier: [TodayItem]
  public let touchedToday: [LineAssignment]
  public let quietLines: [QuietLine]
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

public struct LineActivity: Hashable, Sendable {
  /// 8 weeks, oldest first; the last one is the current, partial week.
  public let sparkline: [WeekPoint]
  public let lastActivity: Date?
  public let nextActions: Int
  /// Sum of task estimates: an estimate, and only over `estimatedTasks` of `nextActions`.
  public let estimatedMinutes: Int
  public let estimatedTasks: Int
}

public struct LineRow: Hashable, Sendable {
  public let line: Line
  public let activity: LineActivity
}

public struct LineBlock: Hashable, Sendable {
  public let name: String
  /// Active, then maintenance, then paused; vault order within each.
  public let rows: [LineRow]
}

public struct LinesOverview: Hashable, Sendable {
  public let blocks: [LineBlock]
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

  private func day(containing date: Date) -> Horizon {
    Horizon.containing(date, scale: .day, calendar: calendar)
      ?? Horizon(scale: .day, start: date, end: date)
  }

  private func calendarDays(from date: Date, to day: Horizon) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: day.start).day ?? 0
  }

  // MARK: Today

  public func today() -> TodayOverview {
    let day = day(containing: now)
    var byLine: [LineAssignment: [TodayItem]] = [:]
    var earlier: [TodayItem] = []
    for task in available {
      var reasons: Set<TodayReason> = []
      if let due = task.dueAt, due < day.end { reasons.insert(.due) }
      if task.flagged { reasons.insert(.flagged) }
      if let deferUntil = task.deferUntil, day.contains(deferUntil) { reasons.insert(.deferred) }
      if let planned = task.plannedAt, planned < day.end { reasons.insert(.planned) }
      guard !reasons.isEmpty else { continue }
      let plannedEarlier = task.plannedAt.flatMap { $0 < day.start ? $0 : nil }
      let item = TodayItem(
        task: task, trace: tracer.trace(task), reasons: reasons,
        isUrgent: reasons.contains(.due),
        plannedDaysAgo: plannedEarlier.map { calendarDays(from: $0, to: day) })
      if plannedEarlier != nil {
        earlier.append(item)
      } else {
        byLine[task.line, default: []].append(item)
      }
    }

    let touched = Set(
      workspace.tasks.filter { $0.status == .completed && $0.completedAt.map(day.contains) == true }
        .map(\.line))
    let quiet = workspace.lines.filter { $0.state == .active }.compactMap { line -> QuietLine? in
      guard let last = stats.lastCompletion(.line(line.id)) else {
        return QuietLine(line: line, reason: .noActivityYet)
      }
      guard calendarDays(from: last, to: day) >= Self.quietAfterDays else { return nil }
      return QuietLine(line: line, reason: .lastActivity(last))
    }
    let groups = lineOrder.compactMap { line in
      byLine[line].map { LineGroup(line: line, items: $0) }
    }
    return TodayOverview(
      day: day, groups: groups,
      fromEarlier: earlier.sorted { ($0.task.plannedAt ?? now) < ($1.task.plannedAt ?? now) },
      touchedToday: lineOrder.filter(touched.contains), quietLines: quiet)
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
      guard let anchor = task.plannedAt ?? task.deferUntil ?? task.dueAt else {
        if case .line(let id) = task.line, activeLines.contains(id) {
          noPlan.append(WeekItem(task: task, trace: tracer.trace(task), hasDueBadge: false))
        }
        continue
      }
      guard let index = days.firstIndex(where: { $0.contains(anchor) }) else { continue }
      items[index].append(
        WeekItem(
          task: task, trace: tracer.trace(task),
          hasDueBadge: task.dueAt.map(range.contains) ?? false))
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
    let parentsOfAvailable = Set(available.compactMap(\.parentTaskID))
    let nextActions = Dictionary(
      grouping: available.filter { !parentsOfAvailable.contains($0.id) }, by: \.line)
    func activity(_ line: LineAssignment) -> LineActivity {
      let actions = nextActions[line] ?? []
      let estimates = actions.compactMap(\.estimateMinutes)
      return LineActivity(
        sparkline: stats.series(line, endingAt: stats.currentWeek, count: Self.sparklineWeeks),
        lastActivity: stats.lastCompletion(line), nextActions: actions.count,
        estimatedMinutes: estimates.reduce(0, +), estimatedTasks: estimates.count)
    }

    func stateRank(_ state: LineState) -> Int {
      switch state {
      case .active: 0
      case .maintenance: 1
      case .paused: 2
      }
    }
    var blockNames: [String] = []
    for line in workspace.lines where !blockNames.contains(line.block) {
      blockNames.append(line.block)
    }
    let blocks = blockNames.map { name in
      let rows = workspace.lines.enumerated().filter { $0.element.block == name }
        .sorted {
          (stateRank($0.element.state), $0.offset) < (stateRank($1.element.state), $1.offset)
        }
        .map { LineRow(line: $0.element, activity: activity(.line($0.element.id))) }
      return LineBlock(name: name, rows: rows)
    }
    return LinesOverview(blocks: blocks, lifeOps: activity(.lifeOps))
  }
}
