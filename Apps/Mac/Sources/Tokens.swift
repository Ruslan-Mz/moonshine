import AppKit
import SwiftUI

/// The colours of `design/tokens.json` this app uses, light and dark. Amber is only for a
/// real due date (CLAUDE.md rule 8); there is no red.
enum Tokens {
  static let dueText = dynamic(light: 0x8A4B00, dark: 0xFFC266)
  static let dueFill = dynamic(light: 0xFFEFD6, dark: 0xFFB040, darkAlpha: 0.15)
  static let chipText = dynamic(light: 0x4F4F57, dark: 0xBDBDC4)
  static let checkboxStroke = dynamic(light: 0xB4B4BB, dark: 0x64646C)

  private static func dynamic(light: Int, dark: Int, darkAlpha: CGFloat = 1) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : 1)
      })
  }

  private static func rgb(_ hex: Int, alpha: CGFloat) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}
