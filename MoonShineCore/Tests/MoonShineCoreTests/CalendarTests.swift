import Foundation
import MoonShineCore
import Testing

@Suite struct CalendarEventTests {
  let zone = TimeZone(identifier: "Europe/Riga")!
  let cal = CalendarID("cal")

  func date(_ d: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
      from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m, second: s))!
  }

  func event(_ start: Date, _ end: Date, title: String? = "Secret title") -> CalendarEvent? {
    CalendarEvent(id: "secret-id", calendarID: cal, title: title, start: start, end: end)
  }

  @Test func refusesAnEndBeforeTheStartAndAllowsZeroLength() {
    #expect(event(date(1, 10), date(1, 9, 59, 59)) == nil)
    #expect(event(date(1, 10), date(1, 10)) != nil)
  }

  @Test func emptyOrBlankTitleIsNil() {
    #expect(event(date(1, 10), date(1, 11), title: "")?.title == nil)
    #expect(event(date(1, 10), date(1, 11), title: "  \n")?.title == nil)
    #expect(event(date(1, 10), date(1, 11), title: nil)?.title == nil)
    #expect(event(date(1, 10), date(1, 11), title: "Physio")?.title == "Physio")
  }

  @Test func overlapIsHalfOpen() throws {
    let thursday = DateInterval(start: date(1, 0), end: date(2, 0))
    let friday = DateInterval(start: date(2, 0), end: date(3, 0))
    let endsAtMidnight = try #require(event(date(1, 23), date(2, 0)))
    #expect(endsAtMidnight.overlaps(thursday))
    #expect(!endsAtMidnight.overlaps(friday))
    let startsAtMidnight = try #require(event(date(2, 0), date(2, 1)))
    #expect(!startsAtMidnight.overlaps(thursday))
    #expect(startsAtMidnight.overlaps(friday))
  }

  @Test func zeroLengthEventBelongsToTheDayOfItsStart() throws {
    let thursday = DateInterval(start: date(1, 0), end: date(2, 0))
    let friday = DateInterval(start: date(2, 0), end: date(3, 0))
    let atMidnight = try #require(event(date(2, 0), date(2, 0)))
    #expect(!atMidnight.overlaps(thursday))
    #expect(atMidnight.overlaps(friday))
    #expect(!atMidnight.overlaps(DateInterval(start: date(2, 0), duration: 0)))
  }

  @Test func aZeroLengthQueryIsAnInstant() throws {
    let lesson = try #require(event(date(1, 17), date(1, 18)))
    func at(_ h: Int, _ m: Int = 0) -> DateInterval {
      DateInterval(start: date(1, h, m), duration: 0)
    }
    #expect(lesson.overlaps(at(17)))
    #expect(lesson.overlaps(at(17, 30)))
    #expect(!lesson.overlaps(at(18)))
    #expect(!lesson.overlaps(at(16, 59)))
    let instant = try #require(event(date(1, 17, 30), date(1, 17, 30)))
    #expect(!instant.overlaps(at(17, 30)))
  }

  @Test func anAllDayEventNeverOccupiesTime() throws {
    let allDay = try #require(
      CalendarEvent(
        id: "a", calendarID: cal, title: nil, start: date(3, 0), end: date(5, 0), isAllDay: true,
        occupiesTime: true))
    #expect(!allDay.occupiesTime)
    #expect(try #require(event(date(1, 10), date(1, 11))).occupiesTime)
  }

  @Test func descriptionsShowNoTitleNameOrId() throws {
    let sample = try #require(event(date(1, 10), date(1, 11)))
    let info = CalendarInfo(
      id: CalendarID("secret-calendar"), title: "Secret calendar", account: "Secret account",
      colorHex: "#123456", kind: .other)
    var dumped = ""
    dump(sample, to: &dumped)
    dump(info, to: &dumped)
    let texts = [
      String(describing: sample), String(reflecting: sample), String(describing: info),
      String(reflecting: info), String(describing: info.id), String(reflecting: info.id), dumped,
    ]
    for text in texts {
      for secret in ["Secret", "secret", "cal\""] {
        #expect(!text.contains(secret), "\(text)")
      }
    }
    #expect(String(describing: sample).contains("occupiesTime: true"))
  }
}

@Suite struct CalendarRangeTests {
  func utc(_ y: Int, _ mo: Int, _ d: Int, _ s: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, second: s))!
  }

  func passes(_ start: Date, _ end: Date) -> Bool {
    (try? CalendarRange.check(DateInterval(start: start, end: end))) != nil
  }

  @Test func allowsExactlyFourCalendarYears() {
    #expect(passes(utc(2026, 10, 1), utc(2030, 10, 1)))
    #expect(!passes(utc(2026, 10, 1), utc(2030, 10, 1, 1)))
    #expect(throws: CalendarRangeError.tooLong) {
      try CalendarRange.check(DateInterval(start: utc(2026, 10, 1), end: utc(2030, 10, 1, 1)))
    }
  }

  @Test func countsCalendarYearsAcrossTheTwentyNinthOfFebruary() {
    #expect(passes(utc(2028, 2, 29), utc(2032, 2, 29)))
    #expect(!passes(utc(2028, 2, 29), utc(2032, 2, 29, 1)))
    // Crosses 29 Feb 2028: four calendar years are 1,461 days here, not 4 × 365.
    #expect(passes(utc(2027, 3, 1), utc(2031, 3, 1)))
    #expect(!passes(utc(2027, 3, 1), utc(2031, 3, 1, 1)))
  }

  @Test func allowsAZeroLengthInterval() {
    #expect(passes(utc(2026, 10, 1), utc(2026, 10, 1)))
  }
}

@Suite struct CalendarVisibilityTests {
  func info(_ id: String, _ kind: CalendarKind) -> CalendarInfo {
    CalendarInfo(id: CalendarID(id), title: "t", account: nil, colorHex: nil, kind: kind)
  }

  @Test func defaultsByKind() {
    let visibility = CalendarVisibility()
    #expect(visibility.setting(for: info("a", .other)) == .init(show: true, countsAsBusy: true))
    #expect(
      visibility.setting(for: info("b", .subscribed)) == .init(show: true, countsAsBusy: false))
    #expect(
      visibility.setting(for: info("c", .birthdays)) == .init(show: true, countsAsBusy: false))
  }

  @Test func storedSettingWins() {
    let visibility = CalendarVisibility([
      CalendarID("b"): CalendarSetting(show: true, countsAsBusy: true),
      CalendarID("a"): CalendarSetting(show: false, countsAsBusy: false),
    ])
    #expect(visibility.setting(for: info("b", .subscribed)).occupiesTime)
    #expect(!visibility.setting(for: info("a", .other)).show)
  }

  @Test func showOffContributesNothingEvenWhenBusy() {
    #expect(!CalendarSetting(show: false, countsAsBusy: true).occupiesTime)
    #expect(CalendarSetting(show: true, countsAsBusy: true).occupiesTime)
    #expect(!CalendarSetting(show: true, countsAsBusy: false).occupiesTime)
  }
}

@Suite struct CalendarReadTests {
  @Test func unavailableIsNotEmpty() {
    let none: CalendarRead<[Int]> = .unavailable(.denied)
    let empty: CalendarRead<[Int]> = .read([], skipped: 0)
    #expect(none.value == nil)
    #expect(empty.value == [])
    #expect(none != empty)
  }
}
