import Foundation

/// Date text for Today, always in the given zone and locale (ADR-0009), never the Mac's zone.
enum TodayFormat {
  /// The weekday, day and month in the locale's own pattern: en_GB `Thursday 1 October`,
  /// ru `четверг, 1 октября` (`design/copy.md` lists `Thursday, 1 October`, the en_US order).
  static func day(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.wide).day().month(.wide))
  }

  /// `29 Sep`: a due date without its time, which is shown from S4-3a on.
  static func dueDate(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).day().month(.abbreviated))
  }

  /// `2 September`: the day of a quiet line's last completion.
  /// `2 September 2025` when its year is not `today`'s (owner, 2026-10-28).
  static func lastDate(_ date: Date, today: Date, timeZone: TimeZone, locale: Locale) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let style = style(timeZone, locale).day().month(.wide)
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
    return date.formatted(sameYear ? style : style.year())
  }

  /// An estimate as the catalog shows it: `≈ 45 min`, `≈ 2 h`, `≈ 1 h 15 min`.
  enum Estimate: Equatable {
    case minutes(Int)
    case hours(Int)
    case hoursAndMinutes(Int, Int)
  }

  /// Nil without an estimate, or for zero or less.
  static func estimate(_ minutes: Int?) -> Estimate? {
    guard let minutes, minutes > 0 else { return nil }
    let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
    if hours == 0 { return .minutes(rest) }
    return rest == 0 ? .hours(hours) : .hoursAndMinutes(hours, rest)
  }

  /// An anchor chip's title: at most 22 characters, cut at the tail with an ellipsis.
  static func chipTitle(_ title: String) -> String {
    title.count <= chipTitleLimit ? title : String(title.prefix(chipTitleLimit - 1)) + "…"
  }

  static let chipTitleLimit = 22

  enum DueStyle: Equatable {
    /// The amber `Due` badge.
    case deadline
    /// Plain secondary `due` text.
    case plain
  }

  /// Amber only for an urgent due date (CLAUDE.md rule 8); any other due date is plain text.
  static func dueStyle(isUrgent: Bool) -> DueStyle { isUrgent ? .deadline : .plain }

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
