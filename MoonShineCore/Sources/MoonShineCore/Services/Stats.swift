import Foundation

/// Completions in one week or one day, never mixed (decision O1): rhythm = sessions of
/// repeating tasks, progress = completed one-off tasks.
public struct WeekCounts: Hashable, Sendable {
  public var rhythm: Int
  public var progress: Int

  public init(rhythm: Int = 0, progress: Int = 0) {
    self.rhythm = rhythm
    self.progress = progress
  }

  public static let zero = WeekCounts()
}

public struct WeekAverage: Hashable, Sendable {
  public let rhythm: Double
  public let progress: Double

  public init(rhythm: Double, progress: Double) {
    self.rhythm = rhythm
    self.progress = progress
  }
}

public struct WeekPoint: Hashable, Sendable {
  public let week: ISOWeek
  public let counts: WeekCounts
  /// The week containing `now`: still running, so the UI dims it.
  public let isPartial: Bool

  public init(week: ISOWeek, counts: WeekCounts, isPartial: Bool) {
    self.week = week
    self.counts = counts
    self.isPartial = isPartial
  }
}

/// Rhythm and progress per line (and Life ops) per ISO week, in the workspace's time zone.
public struct Stats: Sendable {
  public let calendar: Calendar
  public let currentWeek: ISOWeek

  private var weekly: [LineAssignment: [ISOWeek: WeekCounts]] = [:]
  private var last: [LineAssignment: Date] = [:]
  /// Every completion date of each session, and each one-off's, for day counts.
  private var sessionDates: [LineAssignment: [[Date]]] = [:]
  private var oneOffDates: [LineAssignment: [Date]] = [:]

  /// One completed repeating group is one session per line it touches, however many
  /// of its cloned children belong to that line.
  private struct SessionKey: Hashable {
    let root: TaskItemID
    let line: LineAssignment
  }

  public init(workspace: Workspace, now: Date) {
    calendar = .iso8601(in: workspace.timeZone)
    currentWeek = ISOWeek(containing: now, calendar: calendar)
    let byID = Dictionary(
      workspace.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var sessions: [SessionKey: Date] = [:]
    var sessionDates: [SessionKey: [Date]] = [:]
    var oneOffs: [(LineAssignment, Date)] = []
    for task in workspace.tasks where task.status == .completed {
      guard let done = task.completedAt else { continue }
      last[task.line] = max(last[task.line] ?? done, done)
      if task.isOccurrence {
        let key = SessionKey(root: Self.sessionRoot(of: task, in: byID), line: task.line)
        sessions[key] = min(sessions[key] ?? done, done)
        sessionDates[key, default: []].append(done)
      } else {
        oneOffs.append((task.line, done))
      }
    }
    let calendar = calendar
    var weekly: [LineAssignment: [ISOWeek: WeekCounts]] = [:]
    func add(_ line: LineAssignment, _ date: Date, _ keyPath: WritableKeyPath<WeekCounts, Int>) {
      let week = ISOWeek(containing: date, calendar: calendar)
      weekly[line, default: [:]][week, default: .zero][keyPath: keyPath] += 1
    }
    for (line, done) in oneOffs { add(line, done, \.progress) }
    for (key, done) in sessions { add(key.line, done, \.rhythm) }
    self.weekly = weekly
    for (key, dates) in sessionDates { self.sessionDates[key.line, default: []].append(dates) }
    for (line, done) in oneOffs { oneOffDates[line, default: []].append(done) }
  }

  /// The outermost occurrence above `task`: the cloned group it was completed with.
  private static func sessionRoot(of task: TaskItem, in byID: [TaskItemID: TaskItem])
    -> TaskItemID
  {
    var current = task
    while let parentID = current.parentTaskID, let parent = byID[parentID], parent.isOccurrence {
      current = parent
    }
    return current.id
  }

  public func counts(_ line: LineAssignment, in week: ISOWeek) -> WeekCounts {
    weekly[line]?[week] ?? .zero
  }

  /// `count` weeks, oldest first, ending with `week`; weeks without completions are zero.
  public func series(_ line: LineAssignment, endingAt week: ISOWeek, count: Int) -> [WeekPoint] {
    (0..<count).reversed().map { back in
      let week = week.adding(-back, calendar: calendar)
      return WeekPoint(week: week, counts: counts(line, in: week), isPartial: week == currentWeek)
    }
  }

  /// Mean of the `weeks` weeks before `week` (not including it).
  public func average(_ line: LineAssignment, before week: ISOWeek, weeks: Int = 4) -> WeekAverage {
    let previous = series(line, endingAt: week.adding(-1, calendar: calendar), count: weeks)
    let total = Double(max(weeks, 1))
    return WeekAverage(
      rhythm: Double(previous.map(\.counts.rhythm).reduce(0, +)) / total,
      progress: Double(previous.map(\.counts.progress).reduce(0, +)) / total)
  }

  /// The counts of the day around `date` (owner, 2026-10-27): a session counts on every day one
  /// of its completions falls on; weeks keep its first completion.
  public func dayCounts(_ line: LineAssignment, on date: Date) -> WeekCounts {
    guard let day = Horizon.containing(date, scale: .day, calendar: calendar) else { return .zero }
    return WeekCounts(
      rhythm: (sessionDates[line] ?? []).filter { $0.contains(where: day.contains) }.count,
      progress: (oneOffDates[line] ?? []).filter(day.contains).count)
  }

  public func lastCompletion(_ line: LineAssignment) -> Date? {
    last[line]
  }
}
