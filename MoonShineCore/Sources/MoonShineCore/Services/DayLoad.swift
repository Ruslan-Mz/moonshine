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

  private static func floorMinute(_ date: Date) -> Date {
    Date(
      timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    )
  }

  /// `[start, end)` cut to `span`; nil when nothing of it is inside.
  private static func clip(_ start: Date, _ end: Date, _ span: DateInterval) -> DateInterval? {
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
