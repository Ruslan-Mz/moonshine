import Foundation
import Testing

@testable import MoonShineCore

@Suite struct HorizonTests {
  let moscow = Calendar.iso8601(in: TimeZone(identifier: "Europe/Moscow")!)
  let berlin = Calendar.iso8601(in: TimeZone(identifier: "Europe/Berlin")!)

  private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
  }

  @Test func firstOfJanuary2027IsInISOWeek53Of2026() {
    let week = ISOWeek(containing: date(moscow, 2027, 1, 1), calendar: moscow)
    #expect(week == ISOWeek(year: 2026, week: 53))
  }

  @Test func fourthOfJanuary2027StartsWeek1() {
    let week = ISOWeek(containing: date(moscow, 2027, 1, 4), calendar: moscow)
    #expect(week == ISOWeek(year: 2027, week: 1))
  }

  @Test func weekStartsOnMondayMidnightLocalTime() throws {
    // 2026-09-30 is a Wednesday.
    let week = try #require(
      Horizon.containing(date(moscow, 2026, 9, 30), scale: .week, calendar: moscow))
    #expect(week.start == date(moscow, 2026, 9, 28, 0))
    #expect(week.end == date(moscow, 2026, 10, 5, 0))
  }

  @Test func weekAcrossDSTEndIsSevenDaysAndOneHour() throws {
    // Berlin leaves summer time on Sunday 2026-10-25.
    let week = try #require(
      Horizon.containing(date(berlin, 2026, 10, 22), scale: .week, calendar: berlin))
    #expect(week.start == date(berlin, 2026, 10, 19, 0))
    #expect(week.end.timeIntervalSince(week.start) == 7 * 86_400 + 3_600)
  }

  @Test(arguments: [
    (Scale.day, (2026, 9, 30), (2026, 10, 1)),
    (Scale.month, (2026, 9, 1), (2026, 10, 1)),
    (Scale.quarter, (2026, 7, 1), (2026, 10, 1)),
    (Scale.year, (2026, 1, 1), (2027, 1, 1)),
  ])
  func containingBoundsAreLocalMidnights(
    scale: Scale, start: (Int, Int, Int), end: (Int, Int, Int)
  ) throws {
    let horizon = try #require(
      Horizon.containing(date(moscow, 2026, 9, 30), scale: scale, calendar: moscow))
    #expect(horizon.scale == scale)
    #expect(horizon.start == date(moscow, start.0, start.1, start.2, 0))
    #expect(horizon.end == date(moscow, end.0, end.1, end.2, 0))
  }

  @Test func yearOfLastISOWeekIsTheCalendarYear() throws {
    // 2027-01-01 belongs to ISO week 2026-W53 but to calendar year 2027.
    let year = try #require(
      Horizon.containing(date(moscow, 2027, 1, 1), scale: .year, calendar: moscow))
    #expect(year.start == date(moscow, 2027, 1, 1, 0))
  }

  @Test func multiYearAndLifetimeAreNotDerivedFromADate() {
    #expect(Horizon.containing(Date(), scale: .years(5), calendar: moscow) == nil)
    #expect(Horizon.containing(Date(), scale: .lifetime, calendar: moscow) == nil)
  }

  @Test func isoWeekHorizonAndArithmeticCrossTheISOYear() throws {
    let w53 = ISOWeek(year: 2026, week: 53)
    let horizon = try #require(w53.horizon(calendar: moscow))
    #expect(horizon.start == date(moscow, 2026, 12, 28, 0))
    #expect(horizon.end == date(moscow, 2027, 1, 4, 0))
    #expect(w53.adding(1, calendar: moscow) == ISOWeek(year: 2027, week: 1))
    #expect(w53.adding(-53, calendar: moscow) == ISOWeek(year: 2025, week: 52))
  }

  @Test func containsIsHalfOpen() throws {
    let day = try #require(
      Horizon.containing(date(moscow, 2026, 9, 30), scale: .day, calendar: moscow))
    #expect(day.contains(day.start))
    #expect(!day.contains(day.end))
  }
}
