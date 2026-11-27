import SwiftUI

/// The View menu's screen commands; a plain path for auto-merge (scripts/guard/plain-rules.mjs),
/// so a slice that adds a screen and its shortcut need not touch MoonShineApp.swift.
struct ViewCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandGroup(before: .sidebar) {
      // ⌘3 comes with Month in the usage period.
      Button("Today") { model.selection = .today }
        .keyboardShortcut("1", modifiers: .command)
      Button("Week") { model.selection = .week }
        .keyboardShortcut("2", modifiers: .command)
      Button("Lines") { model.selection = .lines }
        .keyboardShortcut("4", modifiers: .command)
      Divider()
    }
  }
}
