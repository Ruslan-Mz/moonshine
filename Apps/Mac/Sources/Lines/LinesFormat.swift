import Foundation
import MoonShineCore

/// The Budget cell and the sparkline's heights, as values (`design/screens/lines.md` § Draft-5,
/// `design/components.md` § Sparkline).
enum LinesFormat {
  /// A daily floor: minutes under an hour (at least 1), else hours with up to two decimals.
  enum Floor: Hashable {
    case minutes(Int)
    case hours(Double)
  }

  enum Budget: Hashable {
    /// `6 h / week`; an owner-set `0` is a budget too (`0 h / week`).
    case weekly(Double)
    /// `floor 3 h/day`: a foundation line's floor, or the only number of another line.
    case floor(Floor)
    /// `4 h / week` over `floor 20 min/day`, on a line that is not foundation.
    case weeklyOverFloor(Double, Floor)
    /// `—`: no budget, and no floor above 0.
    case none
  }

  /// Hours as the Budget cell writes them: up to two decimals, no trailing zeros, in the
  /// view's locale (`1`, `1.25`, `1,5`).
  static let hours = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))

  /// Nil for no floor (`0`, negative or unset).
  static func floor(_ hoursPerDay: Double?) -> Floor? {
    guard let hoursPerDay, hoursPerDay > 0, hoursPerDay.isFinite else { return nil }
    let minutes = (hoursPerDay * 60).rounded()
    if minutes < 60 { return .minutes(max(1, Int(minutes))) }
    return .hours((minutes / 60 * 100).rounded() / 100)
  }

  static func budget(_ line: Line) -> Budget {
    let floor = floor(line.floorHoursPerDay)
    switch (line.budgetHoursPerWeek, floor) {
    case (_, let floor?) where line.foundation: return .floor(floor)
    case (let weekly?, let floor?): return .weeklyOverFloor(weekly, floor)
    case (let weekly?, nil): return .weekly(weekly)
    case (nil, let floor?): return .floor(floor)
    case (nil, nil): return .none
    }
  }

  /// The sparkline's full height and its bars' cap: one scale per line, the larger series at
  /// `barMaximum`, and a value above 0 at least `barMinimum`.
  static let chartHeight: Double = 28
  static let barMaximum: Double = 24
  static let barMinimum: Double = 3

  /// Bar heights for the counts, in order, on one scale.
  static func bars(_ values: [Int]) -> [Double] {
    guard let top = values.max(), top > 0 else { return values.map { _ in 0 } }
    return values.map { value in
      guard value > 0 else { return 0 }
      return max(barMinimum, Double(value) / Double(top) * barMaximum)
    }
  }
}
