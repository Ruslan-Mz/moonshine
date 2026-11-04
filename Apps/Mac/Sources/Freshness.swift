import Foundation

/// The status bar's "updated …": how long ago the last committed import finished
/// (`design/screens/settings.md` § Status bar).
enum Freshness: Equatable {
  case justNow
  case minutes(Int)
  case hours(Int)
  /// From 24 hours on: the day the import finished.
  case day(Date)

  /// Under a minute, or a clock set back, reads as just now.
  init(finishedAt: Date, now: Date) {
    let elapsed = now.timeIntervalSince(finishedAt)
    switch elapsed {
    case ..<60: self = .justNow
    case ..<3_600: self = .minutes(Int(elapsed / 60))
    case ..<86_400: self = .hours(Int(elapsed / 3_600))
    default: self = .day(finishedAt)
    }
  }
}
