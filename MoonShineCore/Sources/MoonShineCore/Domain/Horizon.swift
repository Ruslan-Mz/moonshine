import Foundation

public enum Scale: Hashable, Sendable {
  case day, week, month, quarter, year
  case years(Int)
  case lifetime
}

/// A time span at one scale. `end` is exclusive.
public struct Horizon: Hashable, Sendable {
  public let scale: Scale
  public let start: Date
  public let end: Date

  public init(scale: Scale, start: Date, end: Date) {
    self.scale = scale
    self.start = start
    self.end = end
  }

  public func contains(_ date: Date) -> Bool {
    start <= date && date < end
  }

  /// The day, ISO week, month, quarter or calendar year around `date` in the calendar's time zone.
  /// Multi-year and lifetime horizons come from notes and settings, not from a date.
  public static func containing(_ date: Date, scale: Scale, calendar: Calendar) -> Horizon? {
    let component: Calendar.Component
    switch scale {
    case .day: component = .day
    case .week: component = .weekOfYear
    case .month: component = .month
    case .year: component = .year
    case .quarter:
      let month = calendar.component(.month, from: date)
      let firstMonth = (month - 1) / 3 * 3 + 1
      let year = calendar.component(.year, from: date)
      guard let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)),
        let end = calendar.date(byAdding: .month, value: 3, to: start)
      else { return nil }
      return Horizon(scale: .quarter, start: start, end: end)
    case .years, .lifetime:
      return nil
    }
    guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
    return Horizon(scale: scale, start: interval.start, end: interval.end)
  }
}

/// An ISO 8601 week: Monday start, week 1 contains the first Thursday.
public struct ISOWeek: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let year: Int
  public let week: Int

  public init(year: Int, week: Int) {
    self.year = year
    self.week = week
  }

  public init(containing date: Date, calendar: Calendar) {
    let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    self.init(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
  }

  public static func < (lhs: ISOWeek, rhs: ISOWeek) -> Bool {
    (lhs.year, lhs.week) < (rhs.year, rhs.week)
  }

  public var description: String { String(format: "%04d-W%02d", year, week) }

  /// Monday 00:00 to the next Monday 00:00 in the calendar's time zone.
  public func horizon(calendar: Calendar) -> Horizon? {
    let monday = DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)
    guard let start = calendar.date(from: monday),
      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
    else { return nil }
    return Horizon(scale: .week, start: start, end: end)
  }

  public func adding(_ weeks: Int, calendar: Calendar) -> ISOWeek {
    guard let start = horizon(calendar: calendar)?.start,
      let moved = calendar.date(byAdding: .weekOfYear, value: weeks, to: start)
    else { return self }
    return ISOWeek(containing: moved, calendar: calendar)
  }
}

extension Calendar {
  /// The ISO 8601 calendar in a given time zone; all week and day maths in MoonShine uses it.
  public static func iso8601(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = timeZone
    return calendar
  }
}
