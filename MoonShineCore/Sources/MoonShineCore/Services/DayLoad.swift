import Foundation

/// A time of day, `HH:mm`.
public struct TimeOfDay: Hashable, Sendable {
  public let hour: Int
  public let minute: Int

  /// Nil outside 00:00–23:59.
  public init?(hour: Int, minute: Int) {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    self.hour = hour
    self.minute = minute
  }
}

/// OmniFocus' default times of day as the snapshot exports them, without a zone: a workspace
/// reads them in its own (`Workspace.defaultTimes`). A nil time is an absent setting.
public struct DefaultTimeSettings: Hashable, Sendable {
  public let due: TimeOfDay?
  public let `defer`: TimeOfDay?
  public let planned: TimeOfDay?

  public init(due: TimeOfDay? = nil, defer: TimeOfDay? = nil, planned: TimeOfDay? = nil) {
    self.due = due
    self.defer = `defer`
    self.planned = planned
  }
}

/// OmniFocus' default times (`docs/discovery/snapshot-contract.md` § Default times), in the
/// snapshot's time zone. A nil time is an absent setting: then only 00:00 counts as date only.
public struct DefaultTimes: Hashable, Sendable {
  public enum Kind: Sendable {
    case due, `defer`, planned
  }

  public let timeZone: TimeZone
  public let due: TimeOfDay?
  public let `defer`: TimeOfDay?
  public let planned: TimeOfDay?

  /// With no times, as when the snapshot has no `defaultTimes`.
  public init(
    timeZone: TimeZone, due: TimeOfDay? = nil, defer: TimeOfDay? = nil, planned: TimeOfDay? = nil
  ) {
    self.timeZone = timeZone
    self.due = due
    self.defer = `defer`
    self.planned = planned
  }

  public init(timeZone: TimeZone, _ settings: DefaultTimeSettings) {
    self.init(
      timeZone: timeZone, due: settings.due, defer: settings.defer, planned: settings.planned)
  }

  /// "A day, no particular time": the date's time in the snapshot's zone equals the default
  /// time of its kind, or 00:00 when that default is absent.
  public func isDateOnly(_ date: Date, kind: Kind) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
    let time: TimeOfDay? =
      switch kind {
      case .due: due
      case .defer: self.defer
      case .planned: planned
      }
    let expected = time ?? TimeOfDay(hour: 0, minute: 0)!
    return parts.hour == expected.hour && parts.minute == expected.minute && parts.second == 0
  }
}

/// The span of the day rail and of the free-time fact (Settings → Calendars), in minutes from
/// local midnight.
public struct DayWindow: Hashable, Sendable {
  public let startMinute: Int
  public let endMinute: Int

  public static let standard = DayWindow(startMinute: 8 * 60, endMinute: 22 * 60)!

  /// Nil unless `0 ≤ start < end ≤ 1440`.
  public init?(startMinute: Int, endMinute: Int) {
    guard 0 <= startMinute, startMinute < endMinute, endMinute <= 24 * 60 else { return nil }
    self.startMinute = startMinute
    self.endMinute = endMinute
  }

  /// The window on the day that holds `day`, by wall clock: 08:00–22:00 is 14 h on a
  /// daylight-saving day too; 24:00 is the end of the day, also where the next day starts at
  /// 01:00 (daylight saving at midnight).
  public func interval(on day: Date, calendar: Calendar) -> DateInterval {
    let midnight = calendar.startOfDay(for: day)
    func time(_ minute: Int) -> Date {
      if minute == 24 * 60 {
        return calendar.dateInterval(of: .day, for: day)?.end
          ?? midnight.addingTimeInterval(86_400)
      }
      return calendar.date(
        bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight)
        ?? midnight.addingTimeInterval(TimeInterval(minute * 60))
    }
    return DateInterval(start: time(startMinute), end: max(time(startMinute), time(endMinute)))
  }
}

/// Busy, planned and free time of one day (`design/screens/today.md` § Calendar). Whole
/// minutes: event and task bounds and "now" are floored to the minute before the union.
public struct DayLoad: Hashable, Sendable {
  public let window: DateInterval
  /// Events shown on the day (Show on, tentative and all-day included); nil without access.
  public let eventCount: Int?
  /// The union of busy events inside the window; nil without access.
  public let inCalendarMinutes: Int?
  /// Planned-task time inside the window not covered by a busy event.
  public let plannedMinutes: Int
  /// The window minus busy and planned time; nil without access.
  public let freeWholeWindowMinutes: Int?
  /// From now to the window's end; the whole window before it opens; nil after it closes or
  /// without access.
  public let freeFromNowMinutes: Int?

  /// `tasks` are the counted tasks only: the Today list's tasks plus completed ones, without
  /// reminders (S4, ADR-0017). A task occupies `[planned, planned + estimate)` when its
  /// `effectivePlannedAt` is on the day (a task planned the day before that runs past midnight
  /// counts nothing; owner, 2026-10-17) and not date only and its estimate is above zero;
  /// children that inherit a timed parent overlap and count once.
  public static func compute(
    day: Date, now: Date, window: DayWindow, events: CalendarRead<[CalendarEvent]>,
    visibility: CalendarVisibility, tasks: [TaskItem],
    defaultTimes: DefaultTimes, calendar: Calendar
  ) -> DayLoad {
    let dayInterval =
      calendar.dateInterval(of: .day, for: day)
      ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
    let span = window.interval(on: day, calendar: calendar)

    let planned: [DateInterval] = tasks.compactMap { task in
      guard let at = task.effectivePlannedAt, at >= dayInterval.start, at < dayInterval.end,
        !defaultTimes.isDateOnly(at, kind: .planned), let estimate = task.estimateMinutes,
        estimate > 0
      else { return nil }
      let start = floorMinute(at)
      return clip(start, start.addingTimeInterval(TimeInterval(min(estimate, 24 * 60) * 60)), span)
    }

    guard let read = events.value else {
      return DayLoad(
        window: span, eventCount: nil, inCalendarMinutes: nil,
        plannedMinutes: minutes(union(planned)), freeWholeWindowMinutes: nil,
        freeFromNowMinutes: nil)
    }

    func setting(_ event: CalendarEvent) -> CalendarSetting {
      visibility.setting(for: event.calendarID, kind: event.calendarKind)
    }
    let shown = read.filter { $0.overlaps(dayInterval) && setting($0).show }
    let busy: [DateInterval] = shown.compactMap { event in
      guard !event.isAllDay, event.occupiesTime, setting(event).occupiesTime else { return nil }
      return clip(floorMinute(event.start), floorMinute(event.end), span)
    }

    let busyUnion = union(busy)
    let taken = union(busy + planned)
    let wholeFree = minutes([span]) - minutes(taken)
    let from = floorMinute(now)
    let freeFromNow: Int? =
      if from < span.start {
        wholeFree
      } else if from >= span.end {
        nil
      } else {
        minutes([DateInterval(start: from, end: span.end)])
          - minutes(
            taken.compactMap { clip($0.start, $0.end, DateInterval(start: from, end: span.end)) })
      }
    return DayLoad(
      window: span, eventCount: shown.count, inCalendarMinutes: minutes(busyUnion),
      plannedMinutes: minutes(taken) - minutes(busyUnion), freeWholeWindowMinutes: wholeFree,
      freeFromNowMinutes: freeFromNow)
  }

  fileprivate static func floorMinute(_ date: Date) -> Date {
    Date(
      timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    )
  }

  /// `[start, end)` cut to `span`; nil when nothing of it is inside.
  fileprivate static func clip(_ start: Date, _ end: Date, _ span: DateInterval) -> DateInterval? {
    let from = max(start, span.start)
    let to = min(end, span.end)
    return from < to ? DateInterval(start: from, end: to) : nil
  }

  /// Disjoint intervals covering the same time; overlaps count once.
  private static func union(_ intervals: [DateInterval]) -> [DateInterval] {
    var merged: [DateInterval] = []
    for interval in intervals.sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, interval.start <= last.end {
        merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
      } else {
        merged.append(interval)
      }
    }
    return merged
  }

  /// Total length of disjoint intervals in whole minutes.
  private static func minutes(_ intervals: [DateInterval]) -> Int {
    Int((intervals.reduce(0) { $0 + $1.duration } / 60).rounded(.down))
  }
}

/// The Day section of Today's rail (`design/screens/today.md` § Calendar): the day's events of
/// Show-on calendars and its tasks with a time, each placed on the window's scale or pinned
/// above or below it. Times are floored to the minute, as in `DayLoad`.
public struct DayRail: Hashable, Sendable {
  public struct Mark: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
      /// A timed event; a tentative one is drawn hatched.
      case event(CalendarEvent)
      /// A task with a planned time: `[planned, planned + estimate)`, no length without one.
      case planned(TaskItem)
      /// A task with a due time on the day: an instant; its label hangs below the time.
      case due(TaskItem, isDeadline: Bool)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date
    /// The mark's lane as fractions of the scale's width; pinned marks span it.
    public let leading: Double
    public let width: Double

    var isEvent: Bool { if case .event = kind { true } else { false } }
  }

  /// The least time each kind of mark takes on the scale: the height the view draws it at, as
  /// a duration on the scale. The column rule reserves it (owner, 2026-11-17).
  public struct Footprint: Hashable, Sendable {
    public let event: TimeInterval
    public let planned: TimeInterval
    public let due: TimeInterval

    /// Each value within 60 s … 24 h; a value that is not finite counts as 60 s.
    public init(event: TimeInterval, planned: TimeInterval, due: TimeInterval) {
      func bounded(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(max(value, 60), 86_400) : 60
      }
      self.event = bounded(event)
      self.planned = bounded(planned)
      self.due = bounded(due)
    }

    /// One minute for every kind: the column rule on time alone.
    public static let oneMinute = Footprint(event: 60, planned: 60, due: 60)

    func minimum(_ kind: Mark.Kind) -> TimeInterval {
      switch kind {
      case .event: event
      case .planned: planned
      case .due: due
      }
    }
  }

  /// Marks of one run that do not fit their columns, drawn as one block in one column.
  public struct Block: Hashable, Sendable {
    /// The first mark's drawn top and the latest drawn end.
    public let start: Date
    public let end: Date
    public let leading: Double
    public let width: Double
    /// Time order.
    public let marks: [Mark]

    /// A deadline's due mark is in it: the block keeps the amber (owner, 2026-11-17).
    public var holdsDeadline: Bool {
      marks.contains { if case .due(_, isDeadline: true) = $0.kind { true } else { false } }
    }
  }

  /// A mark on the scale in its column, or a block.
  public enum Placed: Hashable, Sendable {
    case mark(Mark)
    case block(Block)
  }

  public let load: DayLoad
  /// The heights `marks` and `layout` reserve.
  public let footprint: Footprint
  /// All-day events of Show-on calendars, as one-line rows above the scale (owner, 2026-10-30).
  public let allDay: [CalendarEvent]
  /// Before the window's start; time order.
  public let above: [Mark]
  /// On the scale, in their columns with nothing collapsed; an item that crosses an edge is
  /// here, and the view clips it. `layout(minimumWidth:)` collapses what does not fit.
  public let marks: [Mark]
  /// At or after the window's end; time order.
  public let below: [Mark]

  /// `tasks` as for `DayLoad.compute`; `deadlines` are the tasks whose due mark is amber.
  public static func compute(
    day: Date, now: Date, window: DayWindow, events: CalendarRead<[CalendarEvent]>,
    visibility: CalendarVisibility, tasks: [TaskItem], deadlines: Set<TaskItemID>,
    defaultTimes: DefaultTimes, footprint: Footprint, calendar: Calendar
  ) -> DayRail {
    let load = DayLoad.compute(
      day: day, now: now, window: window, events: events, visibility: visibility, tasks: tasks,
      defaultTimes: defaultTimes, calendar: calendar)
    let dayInterval =
      calendar.dateInterval(of: .day, for: day)
      ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
    let span = load.window
    func onDay(_ date: Date) -> Bool { date >= dayInterval.start && date < dayInterval.end }

    let shown = (events.value ?? []).filter {
      $0.overlaps(dayInterval) && visibility.setting(for: $0.calendarID, kind: $0.calendarKind).show
    }
    var items: [(kind: Mark.Kind, start: Date, end: Date)] = shown.filter { !$0.isAllDay }.map {
      (.event($0), DayLoad.floorMinute($0.start), DayLoad.floorMinute($0.end))
    }
    for item in tasks {
      if let at = item.effectivePlannedAt, onDay(at), !defaultTimes.isDateOnly(at, kind: .planned) {
        let start = DayLoad.floorMinute(at)
        let minutes = min(max(item.estimateMinutes ?? 0, 0), 24 * 60)
        items.append((.planned(item), start, start.addingTimeInterval(TimeInterval(minutes * 60))))
      }
      if let due = item.effectiveDueAt, onDay(due), !defaultTimes.isDateOnly(due, kind: .due) {
        let at = DayLoad.floorMinute(due)
        items.append((.due(item, isDeadline: deadlines.contains(item.id)), at, at))
      }
    }
    // Time order; the same start keeps input order (events first).
    let ordered = items.enumerated().sorted {
      $0.element.start != $1.element.start
        ? $0.element.start < $1.element.start : $0.offset < $1.offset
    }.map(\.element)

    func pinned(_ item: (kind: Mark.Kind, start: Date, end: Date)) -> Mark {
      Mark(kind: item.kind, start: item.start, end: item.end, leading: 0, width: 1)
    }
    // Over before the window opens (an instant at its start is on the scale); from its end on.
    let isAbove = { (item: (kind: Mark.Kind, start: Date, end: Date)) in
      item.start < span.start && item.end <= span.start
    }
    let above = ordered.filter(isAbove)
    let below = ordered.filter { !isAbove($0) && $0.start >= span.end }
    let scale = ordered.filter { !isAbove($0) && $0.start < span.end }
    let unplaced = scale.map {
      Mark(kind: $0.kind, start: $0.start, end: $0.end, leading: 0, width: 1)
    }
    // Nothing collapses at a minimum width of 0.
    let marks: [Mark] = place(unplaced, footprint: footprint, from: span.start, minimumWidth: 0)
      .compactMap { if case .mark(let mark) = $0 { mark } else { nil } }
    return DayRail(
      load: load, footprint: footprint, allDay: shown.filter(\.isAllDay),
      above: above.map(pinned), marks: marks, below: below.map(pinned))
  }

  /// The scale's marks with the runs that do not fit collapsed: `minimumWidth` is the
  /// narrowest readable column as a fraction of the lane, taken within 0…1 (not finite: 0,
  /// nothing collapses).
  public func layout(minimumWidth: Double) -> [Placed] {
    Self.place(marks, footprint: footprint, from: load.window.start, minimumWidth: minimumWidth)
  }

  /// The column rule by drawn extent (owner, 2026-11-16 and 2026-11-17; `today.md` § Calendar).
  /// A mark is drawn from its start, or the window's start when it began before, for its
  /// length or its footprint, whichever is longer; a due mark's label hangs below its time.
  /// Marks whose drawn spans overlap form a cluster: events share the leading 55 % when a task
  /// is in it, else the whole width; tasks (due marks included) share the trailing 45 %, or
  /// the whole width without events. Each part collapses on its own, events as tasks do
  /// (owner, 2026-11-17). In each part, as many columns fit as `minimumWidth`
  /// allows (at least one); a run, a stretch where more marks overlap than fit, becomes one
  /// block of the marks that meet it, and the step repeats until every stretch fits. Then each
  /// mark or block takes the first free column, and the width is the part over the columns
  /// used, so marks that only chain keep the whole part. Spans that meet edge to edge do not
  /// overlap. `marks` are in time order.
  fileprivate static func place(
    _ marks: [Mark], footprint: Footprint, from windowStart: Date, minimumWidth: Double
  ) -> [Placed] {
    let minimum = minimumWidth.isFinite ? min(max(minimumWidth, 0), 1) : 0
    func top(_ index: Int) -> Date { max(marks[index].start, windowStart) }
    func bottom(_ index: Int) -> Date {
      max(marks[index].end, top(index).addingTimeInterval(footprint.minimum(marks[index].kind)))
    }
    func span(_ group: [Int]) -> (top: Date, bottom: Date) {
      (group.map(top).min() ?? .distantPast, group.map(bottom).max() ?? .distantPast)
    }
    func fit(_ part: Double) -> Int {
      guard minimum > 0 else { return .max }
      // No more columns than marks, so a tiny minimum cannot overflow `Int`.
      return max(1, Int(min(part / minimum + 1e-9, Double(marks.count)).rounded(.down)))
    }
    /// The groups of `members` (one mark, or a block's marks) so that no stretch holds more
    /// than `fit` at once.
    func groups(_ members: [Int], fit: Int) -> [[Int]] {
      var groups = members.map { [$0] }
      while true {
        let spans = groups.map(span)
        // Ends before starts at one moment: spans that only meet do not overlap.
        var edges: [(time: Date, step: Int)] = []
        for span in spans { edges += [(span.top, 1), (span.bottom, -1)] }
        edges.sort { $0.time != $1.time ? $0.time < $1.time : $0.step < $1.step }
        var runs: [(from: Date, to: Date)] = []
        var depth = 0
        var from: Date?
        for (time, step) in edges {
          depth += step
          if depth > fit, from == nil { from = time }
          if depth <= fit, let start = from {
            runs.append((start, time))
            from = nil
          }
        }
        if runs.isEmpty { return groups }
        var merged: [[Int]] = []
        var taken = Set<Int>()
        for run in runs {
          let meeting = groups.indices.filter {
            !taken.contains($0) && spans[$0].top < run.to && spans[$0].bottom > run.from
          }
          taken.formUnion(meeting)
          merged.append(meeting.flatMap { groups[$0] }.sorted())
        }
        merged += groups.indices.filter { !taken.contains($0) }.map { groups[$0] }
        groups = merged.sorted { $0[0] < $1[0] }
      }
    }
    var placed: [(order: Int, placed: Placed)] = []
    func lay(_ cluster: [Int]) {
      let events = cluster.filter { marks[$0].isEvent }
      let tasks = cluster.filter { !marks[$0].isEvent }
      let (eventPart, taskPart) =
        events.isEmpty ? (0.0, 1.0) : tasks.isEmpty ? (1.0, 0.0) : (0.55, 0.45)
      for (members, base, part) in [(events, 0.0, eventPart), (tasks, eventPart, taskPart)] {
        let parts = groups(members, fit: fit(part))
        // The first free column of each group, in time order.
        var ends: [Date] = []
        var column: [Int] = []
        for group in parts {
          let (from, to) = span(group)
          if let free = ends.firstIndex(where: { $0 <= from }) {
            column.append(free)
            ends[free] = to
          } else {
            column.append(ends.count)
            ends.append(to)
          }
        }
        let width = part / Double(max(ends.count, 1))
        for (group, column) in zip(parts, column) {
          let leading = base + width * Double(column)
          let laid = group.map {
            Mark(
              kind: marks[$0].kind, start: marks[$0].start, end: marks[$0].end,
              leading: leading, width: width)
          }
          if group.count == 1 {
            placed.append((group[0], .mark(laid[0])))
          } else {
            let (from, to) = span(group)
            placed.append(
              (
                group[0],
                .block(Block(start: from, end: to, leading: leading, width: width, marks: laid))
              ))
          }
        }
      }
    }
    var cluster: [Int] = []
    var clusterEnd = Date.distantPast
    for index in marks.indices {
      if !cluster.isEmpty && top(index) >= clusterEnd {
        lay(cluster)
        cluster = []
      }
      cluster.append(index)
      clusterEnd = max(clusterEnd, bottom(index))
    }
    if !cluster.isEmpty { lay(cluster) }
    return placed.sorted { $0.order < $1.order }.map(\.placed)
  }
}
