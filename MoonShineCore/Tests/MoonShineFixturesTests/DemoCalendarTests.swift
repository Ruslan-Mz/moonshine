import Foundation
import MoonShineCore
import Testing

@testable import MoonShineFixtures

@Suite struct DemoCalendarTests {
  let demo = DemoCalendar()

  func day(_ month: Int, _ day: Int, days: Int = 1) -> DateInterval {
    let start = DemoCalendar.at(month, day, 0, 0)
    return DateInterval(
      start: start, end: DemoCalendar.calendar.date(byAdding: .day, value: days, to: start)!)
  }

  func events(_ interval: DateInterval) async throws -> [CalendarEvent] {
    try #require(try await demo.events(in: interval).value)
  }

  @Test func weekFortyHasSeventeenEvents() async throws {
    let week = try await events(day(9, 28, days: 7))
    #expect(week.count == 17)
    #expect(week.filter(\.isAllDay).count == 1)
  }

  @Test func eventsPerDayFollowTheDemoTable() async throws {
    var counts: [Int] = []
    for (month, date) in [(9, 28), (9, 29), (9, 30), (10, 1), (10, 2), (10, 3), (10, 4)] {
      counts.append(try await events(day(month, date)).count)
    }
    // Sat and Sun: one timed event each plus the two-day all-day event.
    #expect(counts == [2, 3, 2, 4, 3, 2, 2])
  }

  @Test func nothingOutsideWeekForty() async throws {
    #expect(try await events(day(9, 27)).isEmpty)
    #expect(try await events(day(10, 5)).isEmpty)
  }

  @Test func aZeroLengthQueryReturnsTheEventsInProgress() async throws {
    func at(_ hour: Int, _ minute: Int) async throws -> [String?] {
      try await events(DateInterval(start: DemoCalendar.at(10, 1, hour, minute), duration: 0))
        .map(\.title)
    }
    #expect(try await at(17, 30) == ["Violin lesson"])
    #expect(try await at(17, 0) == ["Violin lesson"])
    #expect(try await at(18, 0) == [])
    #expect(try await at(16, 20) == [])
  }

  @Test func theWeekendIsAllDayAndTakesNoTime() async throws {
    let saturday = try await events(day(10, 3))
    #expect(saturday.filter(\.isAllDay).allSatisfy { !$0.occupiesTime })
  }

  @Test func coloursAreTheDocumentedDemoValues() {
    // `design/components.md` § CalendarDot (light) and the Settings → Calendars mockup.
    #expect(
      DemoCalendar.calendars.map(\.colorHex) == [
        "#6E9A80", "#9282B4", "#B0946A", "#A0A0A8", "#6C84AE", "#B08484",
      ])
  }

  @Test func theSprintDemoIsTentativeAndTakesNoTime() async throws {
    let friday = try await events(day(10, 2))
    let tentative = friday.filter { $0.display == .tentative }
    #expect(tentative.map(\.title) == ["Sprint demo"])
    #expect(tentative.allSatisfy { !$0.occupiesTime })
  }

  @Test func refusesMoreThanFourYears() async {
    let start = DemoCalendar.at(10, 1, 0, 0)
    await #expect(throws: CalendarRangeError.tooLong) {
      try await demo.events(
        in: DateInterval(start: start, end: start.addingTimeInterval(5 * 366 * 86_400)))
    }
  }

  @Test func calendarsAccessAndSettings() async {
    #expect(await demo.access() == .granted)
    let calendars = await demo.calendars().value ?? []
    #expect(calendars.count == 6)
    let settings = calendars.map { DemoCalendar.visibility.setting(for: $0) }
    #expect(settings.filter(\.show).count == 5)
    #expect(settings.filter(\.occupiesTime).count == 4)
    var changes = 0
    for await _ in demo.changes() { changes += 1 }
    #expect(changes == 0)
  }
}
