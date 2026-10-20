import Foundation

/// Date text for Today, always in the given zone and locale (ADR-0009), never the Mac's zone.
enum TodayFormat {
  /// `Thursday, 1 October`.
  static func day(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.wide).day().month(.wide))
  }

  /// `29 Sep`: a due date without its time, which is shown from S4-3a on.
  static func dueDate(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).day().month(.abbreviated))
  }

  /// Gregorian in the given zone. An ISO 8601 calendar would get CLDR's generic patterns
  /// (`October 1, Thursday`); week numbers come from Core's `ISOWeek`, never from formatting.
  static func calendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private static func style(_ timeZone: TimeZone, _ locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar(timeZone), timeZone: timeZone)
  }
}
