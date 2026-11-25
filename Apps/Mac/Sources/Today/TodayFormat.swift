import Foundation
import MoonShineCore

/// Date text for Today, always in the given zone and locale (ADR-0009), never the Mac's zone.
enum TodayFormat {
  /// The weekday, day and month in the locale's own pattern: en_GB `Thursday 1 October`,
  /// ru `четверг, 1 октября` (`design/copy.md` lists `Thursday, 1 October`, the en_US order).
  static func day(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.wide).day().month(.wide))
  }

  /// `29 Sep`: a due date without its time; a due time today reads `TodayFormat.time`.
  static func dueDate(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).day().month(.abbreviated))
  }

  /// `29 Sep`, or `29 Sep 2027` when its year is not `today`'s: Line detail's dates.
  static func dueDate(_ date: Date, today: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(
      withYear(style(timeZone, locale).day().month(.abbreviated), date, today, timeZone))
  }

  /// `2 September`: the day of a quiet line's last completion.
  /// `2 September 2025` when its year is not `today`'s (owner, 2026-10-28).
  static func lastDate(_ date: Date, today: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(withYear(style(timeZone, locale).day().month(.wide), date, today, timeZone))
  }

  /// `style` with the year added when `date`'s year is not `today`'s.
  private static func withYear(
    _ style: Date.FormatStyle, _ date: Date, _ today: Date, _ timeZone: TimeZone
  ) -> Date.FormatStyle {
    let calendar = calendar(timeZone)
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
    return sameYear ? style : style.year()
  }

  /// `20:30`, on the 24-hour clock in every language: the rail's scale and labels need a fixed
  /// width (`design/i18n.md` rule 3, owner 2026-11-16).
  static func time(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    let hour = Date.FormatStyle.Symbol.VerbatimHour.twoDigits(
      clock: .twentyFourHour, hourCycle: .zeroBased)
    return date.formatted(
      Date.VerbatimFormatStyle(
        format: "\(hour: hour):\(minute: .twoDigits)", locale: locale, timeZone: timeZone,
        calendar: calendar(timeZone)))
  }

  /// A mark's start on the Day rail: `23:00`, or `Wed 23:00` for an event that began on an
  /// earlier day than `dayStart`'s (owner, 2026-11-16).
  static func markTime(_ date: Date, dayStart: Date, timeZone: TimeZone, locale: Locale) -> String {
    let time = time(date, timeZone: timeZone, locale: locale)
    guard date < dayStart else { return time }
    return "\(date.formatted(style(timeZone, locale).weekday(.abbreviated))) \(time)"
  }

  /// What the When column shows besides a planned age: a due date, else a planned time today.
  enum When: Equatable {
    /// `18:00` for a due time today, else the date, `1 Oct`; `Due` or `due` comes from the style.
    case due(String)
    /// `20:30`.
    case planned(String)
  }

  /// A due badge shows its time only for a due time today; Line detail reads the same rule
  /// (owner, 2026-11-16).
  static func showsDueTime(dueHasTime: Bool, dueIsToday: Bool) -> Bool {
    dueIsToday && dueHasTime
  }

  static func when(_ row: TodayScreen.Row, timeZone: TimeZone, locale: Locale) -> When? {
    if let due = row.due {
      return .due(
        showsDueTime(dueHasTime: row.dueHasTime, dueIsToday: row.dueIsToday)
          ? time(due, timeZone: timeZone, locale: locale)
          : dueDate(due, timeZone: timeZone, locale: locale))
    }
    return row.plannedTime.map { .planned(time($0, timeZone: timeZone, locale: locale)) }
  }

  /// The catalog's string in `locale`'s language, as `Text` reads it from the environment.
  static func localized(_ value: String.LocalizationValue, _ locale: Locale) -> String {
    var resource = LocalizedStringResource(value)
    resource.locale = locale
    return String(localized: resource)
  }

  /// `08`: the hour of a day window's edge, as `day window 08–22` reads it.
  static func hour(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    String(time(date, timeZone: timeZone, locale: locale).prefix(2))
  }

  /// The day fact of the toolbar and the Day rail (`design/components.md` § FreeTimeFact).
  static func dayFact(_ load: DayLoad) -> [DayFact] {
    dayFact(
      events: load.eventCount, inCalendar: load.inCalendarMinutes, planned: load.plannedMinutes,
      free: load.freeFromNowMinutes, until: load.window.end)
  }

  static func dayFact(
    events: Int?, inCalendar: Int?, planned: Int, free: Int?, until end: Date
  ) -> [DayFact] {
    var terms: [DayFact] = []
    if let events { terms.append(events == 0 ? .noEvents : .events(events)) }
    if let inCalendar, inCalendar > 0 { terms.append(.inCalendar(duration(inCalendar))) }
    if planned > 0 { terms.append(.planned(duration(planned))) }
    if let free { terms.append(.free(duration(free), until: end)) }
    return terms
  }

  /// A length of time in the estimate's shapes; zero is `0 min`.
  static func duration(_ minutes: Int) -> Estimate {
    estimate(minutes) ?? .minutes(0)
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

/// One term of the day fact; `nil` terms are left out, never shown as zero.
enum DayFact: Equatable {
  case events(Int)
  /// With calendar access and no event on the day.
  case noEvents
  case inCalendar(TodayFormat.Estimate)
  case planned(TodayFormat.Estimate)
  /// What remains of the day window from now, and the window's end.
  case free(TodayFormat.Estimate, until: Date)

  /// `4 events · 4 h in calendar`: the Day rail's header; the other terms are its footer.
  var isCalendar: Bool {
    switch self {
    case .events, .noEvents, .inCalendar: true
    case .planned, .free: false
    }
  }
}
