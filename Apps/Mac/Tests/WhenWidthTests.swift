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
    let row = Self.row(due: Self.october1, urgent: true, plannedDaysAgo: 3)
    let russian = WhenWidth.parts(row, timeZone: Self.zone, locale: Self.russian)
    #expect(russian.map(\.text).first == "запланировано 3 дня назад")
    #expect(russian.last?.text.hasPrefix("Срок ") == true)
    #expect(russian.map(\.style) == [.plain, .badge])
    let english = WhenWidth.parts(row, timeZone: Self.zone, locale: Self.english)
    #expect(english.first?.text == "planned 3 days ago")
    #expect(english.last?.text.hasPrefix("Due ") == true)
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
    let rows = [Self.row(due: Self.october1, urgent: true, plannedDaysAgo: 12)]
    func ideal(_ locale: Locale) -> CGFloat {
      WhenWidth.ideal(
        rows.map { WhenWidth.parts($0, timeZone: Self.zone, locale: locale) },
        measure: WhenWidth.measured)
    }
    #expect(ideal(Self.english) > TodayColumns.when)
    #expect(ideal(Self.russian) > ideal(Self.english))
  }

  /// A row in a collapsed group counts: `From earlier` is collapsed by default, and the column
  /// must not jump when it opens. Today's minimum width stays 532 (owner, 2026-10-26).
  @MainActor @Test func everyRowOfTheScreenCountsAndTheMinimumStays() async throws {
    let screen = TodayScreen(try await demoOverview())
    #expect(!screen.fromEarlier.isEmpty)
    #expect(screen.tableRows.count >= screen.fromEarlier.count + screen.lifeOps.count)
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
