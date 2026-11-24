import AppKit
import Foundation

/// The When column's ideal width: its widest text among the rows of the screen, every group
/// counted whether expanded or collapsed, in the UI language (`design/screens/today.md`
/// § SwiftUI; owner, 2026-11-24). Its minimum stays `TodayColumns.when`.
enum WhenWidth {
  /// One piece of `WhenText`, as it is drawn.
  struct Part: Equatable {
    enum Style: Equatable {
      case plain
      /// The amber `Due` badge: semibold, 5 pt padding on each side.
      case badge
      case digits
    }

    let text: String
    let style: Style
  }

  /// `WhenText`'s `HStack` spacing.
  static let spacing: CGFloat = 6
  static let badgePadding: CGFloat = 10

  /// `WhenText`'s pieces in its order: the planned age, then a due date or a planned time.
  static func parts(_ row: TodayScreen.Row, timeZone: TimeZone, locale: Locale) -> [Part] {
    var parts: [Part] = []
    if let days = row.plannedDaysAgo {
      let age = TodayFormat.localized("planned \(days) days ago", locale)
      parts.append(Part(text: age, style: .plain))
    }
    switch TodayFormat.when(row, timeZone: timeZone, locale: locale) {
    case .due(let date):
      switch TodayFormat.dueStyle(isUrgent: row.isUrgent) {
      case .deadline:
        parts.append(Part(text: TodayFormat.localized("Due \(date)", locale), style: .badge))
      case .plain:
        parts.append(Part(text: TodayFormat.localized("due \(date)", locale), style: .plain))
      }
    case .planned(let time): parts.append(Part(text: time, style: .digits))
    case nil: break
    }
    return parts
  }

  /// The pieces side by side, each as `measure` sizes its text, the badge with its padding.
  static func width(_ parts: [Part], measure: (Part) -> CGFloat) -> CGFloat {
    guard !parts.isEmpty else { return 0 }
    let texts = parts.map { measure($0) + ($0.style == .badge ? badgePadding : 0) }
    return texts.reduce(0, +) + spacing * CGFloat(parts.count - 1)
  }

  /// The widest row's, never under the column's minimum. Rounded up, so the text is not cut by
  /// a fraction of a point.
  static func ideal(_ rows: [[Part]], measure: (Part) -> CGFloat) -> CGFloat {
    let widest = rows.map { width($0, measure: measure) }.max() ?? 0
    return max(TodayColumns.when, widest.rounded(.up))
  }

  static func ideal(_ screen: TodayScreen, locale: Locale) -> CGFloat {
    ideal(
      screen.tableRows.map { parts($0, timeZone: screen.timeZone, locale: locale) },
      measure: measured)
  }

  /// The table's body font; the badge semibold, a planned time with monospaced digits.
  static func measured(_ part: Part) -> CGFloat {
    let size = NSFont.systemFontSize
    let font: NSFont =
      switch part.style {
      case .plain: .systemFont(ofSize: size)
      case .badge: .systemFont(ofSize: size, weight: .semibold)
      case .digits: .monospacedDigitSystemFont(ofSize: size, weight: .regular)
      }
    return NSAttributedString(string: part.text, attributes: [.font: font]).size().width
  }
}
