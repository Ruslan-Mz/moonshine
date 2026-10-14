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
  /// Read byte by byte: the shapes are fixed, and a list of years is parsed part by part.
  static func parse(_ text: String, calendar: Calendar) -> WrittenDate? {
    let bytes = Array(text.utf8)
    let dash = UInt8(ascii: "-")
    guard bytes.count >= 4, let year = number(bytes[..<4]), years.contains(year) else { return nil }
    switch bytes.count {
    case 4:
      return make(.year, .year, year, 1, 1, calendar)
    case 7 where bytes[4] == dash && bytes[5] == UInt8(ascii: "Q"):
      guard let quarter = number(bytes[6...]), (1...4).contains(quarter) else { return nil }
      return make(.quarter, .quarter, year, (quarter - 1) * 3 + 1, 1, calendar)
    case 7 where bytes[4] == dash:
      guard let month = number(bytes[5...]) else { return nil }
      return make(.month, .month, year, month, 1, calendar)
    case 8 where bytes[4] == dash && bytes[5] == UInt8(ascii: "W"):
      // Built and read back: week 53 of a year with 52 weeks lands in the next year.
      guard let week = number(bytes[6...]) else { return nil }
      let written = ISOWeek(year: year, week: week)
      guard let span = written.horizon(calendar: calendar),
        ISOWeek(containing: span.start, calendar: calendar) == written
      else { return nil }
      return WrittenDate(shape: .week, year: year, start: span.start, end: span.end)
    case 10 where bytes[4] == dash && bytes[7] == dash:
      guard let month = number(bytes[5..<7]), let day = number(bytes[8...]) else { return nil }
      return make(.day, .day, year, month, day, calendar)
    default:
      return nil
    }
  }

  /// The value of ASCII digits; nil when any byte is something else. At most four digits.
  private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
    let zero = UInt8(ascii: "0")
    guard digits.allSatisfy({ (zero...zero + 9).contains($0) }) else { return nil }
    return digits.reduce(0) { $0 * 10 + Int($1 - zero) }
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
