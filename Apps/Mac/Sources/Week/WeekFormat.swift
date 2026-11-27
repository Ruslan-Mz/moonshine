import Foundation

/// Date text for Week, always in the given zone and locale (ADR-0009), never the Mac's zone.
enum WeekFormat {
  /// `28 September – 4 October 2026`; `28 December 2026 – 3 January 2027` across a year.
  static func range(_ first: Date, _ last: Date, timeZone: TimeZone, locale: Locale) -> String {
    let calendar = TodayFormat.calendar(timeZone)
    let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
    let day = style(timeZone, locale).day().month(.wide)
    let start = first.formatted(sameYear ? day : day.year())
    return "\(start) – \(last.formatted(day.year()))"
  }

  /// `Mon`, `Пн`: a column's header, the stand-alone form.
  static func weekday(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.abbreviated))
  }

  /// `Mon`, `пн`: a weekday inside a sentence, as `design/copy.md` writes `неделя идёт — пн–чт`
  /// and `Срок пт 12:00`. macOS formats a Russian abbreviated weekday capitalized (`Пн`) in
  /// every context, and Russian writes it lowercase in running text; English keeps its capital.
  static func weekdayInText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    let day = weekday(date, timeZone: timeZone, locale: locale)
    return locale.language.languageCode == .russian ? day.lowercased(with: locale) : day
  }

  /// `28`: the day of the month in a column's header.
  static func dayNumber(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).day())
  }

  /// The partial week's days, `Mon` to `Thu`; on Monday the second is nil (`Week in progress —
  /// Mon`).
  static func daysSoFar(
    first: Date, today: Date, timeZone: TimeZone, locale: Locale
  ) -> (first: String, today: String?) {
    let calendar = TodayFormat.calendar(timeZone)
    let start = weekdayInText(first, timeZone: timeZone, locale: locale)
    guard !calendar.isDate(first, inSameDayAs: today) else { return (start, nil) }
    return (start, weekdayInText(today, timeZone: timeZone, locale: locale))
  }

  /// `4.0`, `4,0`: a 4-week average with one decimal in the locale's separator.
  static func average(_ value: Double, locale: Locale) -> String {
    value.formatted(.number.precision(.fractionLength(1)).locale(locale))
  }

  /// `Fri 12:00`, or `Fri` for a date-only due date.
  static func due(_ due: WeekScreen.Due, timeZone: TimeZone, locale: Locale) -> String {
    let day = weekdayInText(due.date, timeZone: timeZone, locale: locale)
    guard due.hasTime else { return day }
    return "\(day) \(TodayFormat.time(due.date, timeZone: timeZone, locale: locale))"
  }

  private static func style(_ timeZone: TimeZone, _ locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: TodayFormat.calendar(timeZone), timeZone: timeZone)
  }
}
