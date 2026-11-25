import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

/// The When column's ideal width (`design/screens/today.md` § SwiftUI; owner, 2026-11-24).
struct WhenWidthTests {
  static let zone = TimeZone(identifier: "Europe/Moscow")!
  static let russian = Locale(identifier: "ru")
  static let english = Locale(identifier: "en_GB")

  static func row(
    due: Date? = nil, urgent: Bool = false, plannedDaysAgo: Int? = nil
  ) -> TodayScreen.Row {
    TodayScreen.Row(
      id: .generate(), title: "Task", trace: [], estimateMinutes: nil, due: due,
      dueHasTime: false, dueIsToday: false, isUrgent: urgent, plannedDaysAgo: plannedDaysAgo,
      plannedTime: nil, isDone: false)
  }

  static let october1 = Calendar.iso8601(in: zone).date(
    from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!

  /// One point per character: the sums are exact.
  static func characters(_ part: WhenWidth.Part) -> CGFloat { CGFloat(part.text.count) }

  @Test func thePartsAreTheCatalogsWordsInTheUILanguage() {
    let age = Self.row(plannedDaysAgo: 3)
    #expect(
      WhenWidth.parts(age, timeZone: Self.zone, locale: Self.russian)
        == [.init(text: "назначено 3 дня назад", style: .plain)])
    #expect(
      WhenWidth.parts(age, timeZone: Self.zone, locale: Self.english)
        == [.init(text: "planned 3 days ago", style: .plain)])
    let due = Self.row(due: Self.october1, urgent: true)
    let russian = WhenWidth.parts(due, timeZone: Self.zone, locale: Self.russian)
    #expect(russian.map(\.style) == [.badge])
    #expect(russian.first?.text.hasPrefix("Срок ") == true)
    let english = WhenWidth.parts(due, timeZone: Self.zone, locale: Self.english)
    #expect(english.first?.text.hasPrefix("Due ") == true)
  }

  /// A row from earlier with a due date shows only the due text; its age is the tooltip
  /// (owner, 2026-11-25, PR #70 round 2).
  @Test func aRowFromEarlierWithADueDateShowsOnlyTheDueText() {
    for locale in [Self.english, Self.russian] {
      for urgent in [true, false] {
        let row = Self.row(due: Self.october1, urgent: urgent, plannedDaysAgo: 3)
        let when = TodayFormat.when(row, timeZone: Self.zone, locale: locale)
        #expect(WhenWidth.ageIsTooltip(row, when: when))
        let parts = WhenWidth.parts(row, timeZone: Self.zone, locale: locale)
        let dueOnly = Self.row(due: Self.october1, urgent: urgent)
        #expect(parts == WhenWidth.parts(dueOnly, timeZone: Self.zone, locale: locale))
      }
    }
    // Without a due date the age stays in the cell; without an age there is no tooltip.
    let age = Self.row(plannedDaysAgo: 3)
    #expect(!WhenWidth.ageIsTooltip(age, when: nil))
    let due = Self.row(due: Self.october1)
    let when = TodayFormat.when(due, timeZone: Self.zone, locale: Self.english)
    #expect(!WhenWidth.ageIsTooltip(due, when: when))
  }

  @Test func aPlainDueIsNotABadge() {
    let parts = WhenWidth.parts(
      Self.row(due: Self.october1), timeZone: Self.zone, locale: Self.english)
    #expect(parts.map(\.style) == [.plain])
    #expect(parts.first?.text.hasPrefix("due ") == true)
  }

  @Test func theWidthAddsTheSpacingAndTheBadgesPadding() {
    let parts = [
      WhenWidth.Part(text: "abcd", style: .plain), WhenWidth.Part(text: "ef", style: .badge),
    ]
    // Four and two characters, the badge's 10 pt padding, one 6 pt spacing.
    let expected: CGFloat = 4 + 2 + 10 + 6
    #expect(WhenWidth.width(parts, measure: Self.characters) == expected)
    #expect(WhenWidth.width([], measure: Self.characters) == 0)
  }

  @Test func theIdealIsTheWidestRowAndNeverUnderTheMinimum() {
    let wide = [WhenWidth.Part(text: String(repeating: "x", count: 200), style: .plain)]
    let narrow = [WhenWidth.Part(text: "x", style: .plain)]
    #expect(WhenWidth.ideal([narrow, wide], measure: Self.characters) == 200)
    #expect(WhenWidth.ideal([narrow], measure: Self.characters) == TodayColumns.when)
    #expect(WhenWidth.ideal([], measure: Self.characters) == TodayColumns.when)
    // Rounded up, so a text is never cut by a fraction of a point.
    #expect(WhenWidth.ideal([narrow], measure: { _ in 150.2 }) == 151)
  }

  /// The badge is drawn semibold, so it is measured so.
  @Test func theBadgeIsMeasuredSemibold() {
    let text = "Due 30 September"
    #expect(
      WhenWidth.measured(.init(text: text, style: .badge))
        > WhenWidth.measured(.init(text: text, style: .plain)))
  }

  /// Russian is longer: the column follows the UI language.
  @Test func russianNeedsAWiderColumn() {
    let rows = [Self.row(plannedDaysAgo: 12)]
    func ideal(_ locale: Locale) -> CGFloat {
      WhenWidth.ideal(
        rows.map { WhenWidth.parts($0, timeZone: Self.zone, locale: locale) },
        measure: WhenWidth.measured)
    }
    #expect(ideal(Self.english) > TodayColumns.when)
    #expect(ideal(Self.russian) > ideal(Self.english))
  }

  /// At 1100×700 with the rail, the When column keeps what the other columns leave: the
  /// window less the sidebar, the rail, two 1 pt dividers and every other column at its
  /// minimum (184 pt).
  static var availableAt1100: CGFloat {
    let others = TodayColumns.minimumWidth - TodayColumns.when
    return 1100 - RootView.sidebarWidth - TodayColumns.rail - 2 - others
  }

  /// A three-digit Russian age fits there (owner, 2026-11-25, PR #70 round 1).
  @Test func aThreeDigitRussianAgeFitsAt1100WithTheRail() {
    let parts = WhenWidth.parts(
      Self.row(plannedDaysAgo: 120), timeZone: Self.zone, locale: Self.russian)
    #expect(parts.map(\.text) == ["назначено 120 дней назад"])
    let width = WhenWidth.width(parts, measure: WhenWidth.measured)
    print("Russian three-digit age: \(width) of \(Self.availableAt1100) pt")
    #expect(width <= Self.availableAt1100)
  }

  /// The widest row from earlier with a due date fits too, in English and Russian: a
  /// two-digit day in every month, as a badge and as plain text (owner, 2026-11-25, round 2).
  @Test func theWidestRowFromEarlierWithADueDateFitsAt1100WithTheRail() {
    let calendar = Calendar.iso8601(in: Self.zone)
    for locale in [Self.english, Self.russian] {
      var widest: CGFloat = 0
      for month in 1...12 {
        let due = calendar.date(from: DateComponents(year: 2026, month: month, day: 28, hour: 12))!
        for urgent in [true, false] {
          let row = Self.row(due: due, urgent: urgent, plannedDaysAgo: 120)
          let parts = WhenWidth.parts(row, timeZone: Self.zone, locale: locale)
          widest = max(widest, WhenWidth.width(parts, measure: WhenWidth.measured))
        }
      }
      print("Widest row from earlier with a due date, \(locale.identifier): \(widest) pt")
      #expect(widest <= Self.availableAt1100)
    }
  }

  /// A row in a collapsed group counts: `From earlier` is collapsed by default, and the column
  /// must not jump when it opens. Today's minimum width stays 532 (owner, 2026-10-26).
  @MainActor @Test func everyRowOfTheScreenCountsAndTheMinimumStays() async throws {
    let screen = TodayScreen(try await demoOverview())
    // Every group of the table, each with rows in Demo, so a group left out is missed.
    let ids = Set(screen.tableRows.map(\.id))
    for group in [
      screen.top, screen.sections.flatMap(\.rows), screen.fromEarlier, screen.lifeOps,
      screen.doneToday,
    ] {
      #expect(!group.isEmpty)
      #expect(group.allSatisfy { ids.contains($0.id) })
    }
    let earlier = screen.fromEarlier.map {
      WhenWidth.parts($0, timeZone: screen.timeZone, locale: Self.english)
    }
    let ideal = WhenWidth.ideal(screen, locale: Self.english)
    #expect(ideal >= WhenWidth.ideal(earlier, measure: WhenWidth.measured))
    // The owner's `planned 3 days a…`: the demo's From earlier is wider than 118.
    #expect(ideal > TodayColumns.when)
    #expect(TodayColumns.minimumWidth == 532)
  }
}
