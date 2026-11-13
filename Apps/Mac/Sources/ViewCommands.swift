import SwiftUI

/// The View menu's screen commands; a plain path for auto-merge (scripts/guard/plain-rules.mjs),
/// so a slice that adds a screen and its shortcut need not touch MoonShineApp.swift.
struct ViewCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(before: .sidebar) {
      // ⌘2 and ⌘3 come with their views (S5).
      Button("Today") { model.selection = .today }
        .keyboardShortcut("1", modifiers: .command)
      Button("Lines") { model.selection = .lines }
        .keyboardShortcut("4", modifiers: .command)
      Divider()
    }
  }
}
