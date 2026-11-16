import AppKit
import SwiftUI

/// The colours of `design/tokens.json` this app uses, light and dark. Amber is only for a
/// real due date (CLAUDE.md rule 8); there is no red.
enum Tokens {
  static let dueText = dynamic(light: 0x8A4B00, dark: 0xFFC266)
  static let dueFill = dynamic(light: 0xFFEFD6, dark: 0xFFB040, darkAlpha: 0.15)
  static let chipText = dynamic(light: 0x4F4F57, dark: 0xBDBDC4)
  static let checkboxStroke = dynamic(light: 0xB4B4BB, dark: 0x64646C)
  static let doneText = dynamic(light: 0x9A9AA2, dark: 0x7E7E86)
  static let rhythm = dynamic(light: 0x2F68C8, dark: 0x5E92EE)
  static let progress = dynamic(light: 0x14917A, dark: 0x3FA690)
  static let paused = dynamic(light: 0x8E8E95, dark: 0x7E7E86)
  static let card = dynamic(light: 0xFFFFFF, dark: 0x2A2A2E)
  static let cardBorder = dynamic(
    light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.07)
  static let chipFill = dynamic(
    light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.075)

  /// A calendar's colour toned toward the tokens (`design/components.md` § CalendarDot):
  /// saturation at most 35 %, lightness 50–60 % in light mode and 65–75 % in dark; `paused`
  /// without a colour.
  static func calendar(_ hex: String?) -> Color {
    guard let hex, hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16)
    else { return paused }
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return toned(value, lightness: isDark ? 0.65...0.75 : 0.50...0.60)
      })
  }

  private static func toned(_ hex: Int, lightness range: ClosedRange<CGFloat>) -> NSColor {
    let (r, g, b) = (
      CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255
    )
    let (high, low) = (max(r, g, b), min(r, g, b))
    let delta = high - low
    let hue: CGFloat =
      if delta == 0 { 0 } else if high == r {
        ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      } else if high == g { (b - r) / delta + 2 } else { (r - g) / delta + 4 }
    let lightness = min(max((high + low) / 2, range.lowerBound), range.upperBound)
    let source = delta == 0 ? 0 : delta / (1 - abs(high + low - 1))
    let saturation = min(source, 0.35)
    // HSL back to RGB.
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let sector = (hue < 0 ? hue + 6 : hue)
    let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (CGFloat, CGFloat, CGFloat) =
      switch Int(sector) {
      case 0: (chroma, second, 0)
      case 1: (second, chroma, 0)
      case 2: (0, chroma, second)
      case 3: (0, second, chroma)
      case 4: (second, 0, chroma)
      default: (chroma, 0, second)
      }
    let m = lightness - chroma / 2
    return NSColor(srgbRed: r1 + m, green: g1 + m, blue: b1 + m, alpha: 1)
  }

  private static func dynamic(
    light: Int, dark: Int, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
  ) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
      })
  }

  private static func rgb(_ hex: Int, alpha: CGFloat) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}
