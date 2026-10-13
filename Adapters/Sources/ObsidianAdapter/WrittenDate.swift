import Foundation
import MoonShineCore

/// A year, month, day, ISO week or quarter as a note writes it (contract §2): `YYYY`,
/// `YYYY-MM`, `YYYY-MM-DD`, `YYYY-Www`, `YYYY-Qn`, ASCII digits only, years 1900 to 2199.
struct WrittenDate: Equatable {
  enum Shape: Equatable { case year, month, day, week, quarter }

  static let years = 1900...2199

  let shape: Shape
  let year: Int
  /// The first instant of it and the first instant after it, in the calendar's time zone.
  let start: Date
  let end: Date

  /// Nil for any other shape, a year out of range, and a month, day or week that does not exist.
  static func parse(_ text: String, calendar: Calendar) -> WrittenDate? {
    let shapes = #/([0-9]{4})(?:-([0-9]{2})(?:-([0-9]{2}))?|-W([0-9]{2})|-Q([1-4]))?/#
    guard text.utf8.allSatisfy({ $0 < 0x80 }), let match = text.wholeMatch(of: shapes),
      let year = Int(match.1), years.contains(year)
    else { return nil }
    if let week = match.4.flatMap({ Int($0) }) {
      // Built and read back: week 53 of a year with 52 weeks lands in the next year.
      let written = ISOWeek(year: year, week: week)
      guard let span = written.horizon(calendar: calendar),
        ISOWeek(containing: span.start, calendar: calendar) == written
      else { return nil }
      return WrittenDate(shape: .week, year: year, start: span.start, end: span.end)
    }
    if let quarter = match.5.flatMap({ Int($0) }) {
      return make(.quarter, .quarter, year, (quarter - 1) * 3 + 1, 1, calendar)
    }
    guard let month = match.2.flatMap({ Int($0) }) else {
      return make(.year, .year, year, 1, 1, calendar)
    }
    guard let day = match.3.flatMap({ Int($0) }) else {
      return make(.month, .month, year, month, 1, calendar)
    }
    return make(.day, .day, year, month, day, calendar)
  }

  /// The span of `scale` around the given day; nil when the day does not exist (`2026-02-30`
  /// would be read back as 2 March).
  private static func make(
    _ shape: Shape, _ scale: Scale, _ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar
  ) -> WrittenDate? {
    let written = DateComponents(year: year, month: month, day: day)
    guard let date = calendar.date(from: written),
      calendar.dateComponents([.year, .month, .day], from: date) == written,
      let span = Horizon.containing(date, scale: scale, calendar: calendar)
    else { return nil }
    return WrittenDate(shape: shape, year: year, start: span.start, end: span.end)
  }
}
