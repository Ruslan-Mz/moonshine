import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import MoonShineMac

/// The status bar's freshness ladder (`design/screens/settings.md` § Status bar).
@Suite struct FreshnessTests {
  let finished = DemoEnvironment.now

  func after(_ seconds: TimeInterval) -> Freshness {
    Freshness(finishedAt: finished, now: finished.addingTimeInterval(seconds))
  }

  @Test func theLadderStepsAtAMinuteAnHourAndADay() {
    #expect(after(0) == .justNow)
    #expect(after(59) == .justNow)
    #expect(after(-300) == .justNow)
    #expect(after(60) == .minutes(1))
    #expect(after(59 * 60) == .minutes(59))
    #expect(after(60 * 60) == .hours(1))
    #expect(after(23 * 3_600 + 59 * 60) == .hours(23))
    #expect(after(24 * 3_600) == .day(finished))
  }

  /// The catalog's Russian forms, looked up in the app's `ru.lproj`.
  @Test func russianFormsResolveFromTheCatalog() throws {
    let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
    let ru = try #require(Bundle(path: path))
    let russian = Locale(identifier: "ru")
    func format(_ key: String, _ value: CVarArg) -> String {
      String(
        format: ru.localizedString(forKey: key, value: nil, table: nil), locale: russian, value)
    }
    #expect(
      ru.localizedString(forKey: "Updated just now", value: nil, table: nil)
        == "Обновлено только что")
    #expect(format("Updated %lld min ago", 3) == "Обновлено 3 мин назад")
    #expect(format("Updated %lld h ago", 21) == "Обновлено 21 ч назад")
    let day = TodayFormat.lastDate(
      finished, today: finished, timeZone: DemoVault.calendar.timeZone, locale: russian)
    #expect(format("Updated on %@", day) == "Обновлено 1 октября")
  }
}
