import SwiftUI

/// The View menu's screen commands; a plain path for auto-merge (scripts/guard/plain-rules.mjs),
/// so a slice that adds a screen and its shortcut need not touch MoonShineApp.swift.
struct ViewCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(before: .sidebar) {
      // ⌘2–⌘4 come with their views (S4-2, S5).
      Button("Today") { model.selection = .today }
        .keyboardShortcut("1", modifiers: .command)
      Divider()
    }
  }
}
