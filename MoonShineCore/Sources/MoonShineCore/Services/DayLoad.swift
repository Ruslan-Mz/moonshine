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
      /// A task with a due time on the day: an instant.
      case due(TaskItem, isDeadline: Bool)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date
    /// The mark's lane as fractions of the scale's width; pinned marks span it.
    public let leading: Double
    public let width: Double
  }

  public let load: DayLoad
  /// All-day events of Show-on calendars, as one-line rows above the scale (owner, 2026-10-30).
  public let allDay: [CalendarEvent]
  /// Before the window's start; time order.
  public let above: [Mark]
  /// On the scale; an item that crosses an edge is here, and the view clips it.
  public let marks: [Mark]
  /// At or after the window's end; time order.
  public let below: [Mark]

  /// `tasks` as for `DayLoad.compute`; `deadlines` are the tasks whose due mark is amber.
  public static func compute(
    day: Date, now: Date, window: DayWindow, events: CalendarRead<[CalendarEvent]>,
    visibility: CalendarVisibility, tasks: [TaskItem], deadlines: Set<TaskItemID>,
    defaultTimes: DefaultTimes, calendar: Calendar
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
    return DayRail(
      load: load, allDay: shown.filter(\.isAllDay), above: above.map(pinned),
      marks: lanes(scale), below: below.map(pinned))
  }

  /// Per cluster of marks linked by overlap: events share the leading 55 % when a task is in
  /// the cluster, else the whole width; tasks share the trailing 45 %, or the whole width
  /// without events (`today.md` § Calendar). Each mark takes the first free column of its
  /// kind, and the width is the part over the most marks of that kind at one moment, so marks
  /// that only chain keep the whole part (the column rule, owner 2026-11-16). A due mark spans
  /// the lane. A mark with no length counts as one minute here.
  private static func lanes(_ items: [(kind: Mark.Kind, start: Date, end: Date)]) -> [Mark] {
    var shares: [(leading: Double, width: Double)] = Array(
      repeating: (0, 1), count: items.count)
    let blocks = items.indices.filter {
      if case .due = items[$0].kind { false } else { true }
    }
    func end(_ index: Int) -> Date {
      max(items[index].end, items[index].start.addingTimeInterval(60))
    }
    /// The first free column of each mark, in time order, and the number of columns used.
    func columns(_ marks: [Int]) -> (column: [Int: Int], count: Int) {
      var ends: [Date] = []
      var column: [Int: Int] = [:]
      for index in marks {
        if let free = ends.firstIndex(where: { $0 <= items[index].start }) {
          column[index] = free
          ends[free] = end(index)
        } else {
          column[index] = ends.count
          ends.append(end(index))
        }
      }
      return (column, ends.count)
    }
    var cluster: [Int] = []
    var clusterEnd = Date.distantPast
    func place() {
      let events = cluster.filter { if case .event = items[$0].kind { true } else { false } }
      let others = cluster.filter { !events.contains($0) }
      let (eventPart, taskPart) =
        events.isEmpty ? (0.0, 1.0) : others.isEmpty ? (1.0, 0.0) : (0.55, 0.45)
      for (marks, base, part) in [(events, 0.0, eventPart), (others, eventPart, taskPart)] {
        let (column, count) = columns(marks)
        for index in marks {
          let width = part / Double(max(count, 1))
          shares[index] = (base + width * Double(column[index] ?? 0), width)
        }
      }
    }
    for index in blocks {
      if !cluster.isEmpty && items[index].start >= clusterEnd {
        place()
        cluster = []
      }
      cluster.append(index)
      clusterEnd = max(clusterEnd, end(index))
    }
    place()
    return items.indices.map {
      Mark(
        kind: items[$0].kind, start: items[$0].start, end: items[$0].end,
        leading: shares[$0].leading, width: shares[$0].width)
    }
  }
}
