import MoonShineCore
import SwiftUI

/// Which weeks ‹ Today › can show (S5-1b). The shown week is held as the week itself, nil for
/// this week, so midnight cannot move it while the owner plans.
struct WeekNavigation: Equatable {
  let current: ISOWeek
  /// The week holding the completion window's start, when it is known: an earlier week would
  /// read unknown data as nothing done (owner, 2026-11-28). Else `reach` weeks back.
  let earliest: ISOWeek
  let latest: ISOWeek
  let calendar: Calendar

  /// Ten years each way: a bound, not a feature.
  static let reach = 520

  init(_ overview: Overview) {
    let calendar = overview.calendar
    self.calendar = calendar
    let current = ISOWeek(containing: overview.now, calendar: calendar)
    let floor = current.adding(-Self.reach, calendar: calendar)
    self.current = current
    // A window start after today (a clock set back) still lets this week show.
    earliest =
      overview.workspace.completedSince.map {
        min(max(ISOWeek(containing: $0, calendar: calendar), floor), current)
      } ?? floor
    latest = current.adding(Self.reach, calendar: calendar)
  }

  /// The week shown for `week`, nil being this week, inside the bounds.
  func clamped(_ week: ISOWeek?) -> ISOWeek {
    min(max(week ?? current, earliest), latest)
  }

  /// `delta` weeks from `week`, inside the bounds; nil when that is this week.
  func step(_ week: ISOWeek?, by delta: Int) -> ISOWeek? {
    let moved = clamped(clamped(week).adding(delta, calendar: calendar))
    return moved == current ? nil : moved
  }

  func canStep(_ week: ISOWeek?, by delta: Int) -> Bool {
    (step(week, by: delta) ?? current) != clamped(week)
  }
}

/// The shown week and its bounds, for the toolbar and the View menu.
struct WeekStepper {
  let navigation: WeekNavigation
  let shown: Binding<ISOWeek?>

  var isCurrent: Bool { navigation.clamped(shown.wrappedValue) == navigation.current }

  func canStep(by delta: Int) -> Bool { navigation.canStep(shown.wrappedValue, by: delta) }

  func step(by delta: Int) { shown.wrappedValue = navigation.step(shown.wrappedValue, by: delta) }

  func goToToday() { shown.wrappedValue = nil }
}
