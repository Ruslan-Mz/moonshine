import SwiftUI

/// The View menu's screen commands; a plain path for auto-merge (scripts/guard/plain-rules.mjs),
/// so a slice that adds a screen and its shortcut need not touch MoonShineApp.swift.
struct ViewCommands: Commands {
  let model: AppModel
  @FocusedValue(\.weekStepper) private var weekStepper

  var body: some Commands {
    CommandGroup(before: .sidebar) {
      // ⌘3 comes with Month in the usage period.
      Button("Today") { model.selection = .today }
        .keyboardShortcut("1", modifiers: .command)
      Button("Week") {
        model.selection = .week
        // ⌘2 on Week goes back to this week, as it opens Week on it.
        weekStepper?.goToToday()
      }
      .keyboardShortcut("2", modifiers: .command)
      Button("Lines") { model.selection = .lines }
        .keyboardShortcut("4", modifiers: .command)
      Divider()
      // Week's steps (owner, 2026-11-28, as Month and Time step): disabled on other screens.
      Button("Previous Week") { weekStepper?.step(by: -1) }
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .disabled(!(weekStepper?.canStep(by: -1) ?? false))
      Button("Next Week") { weekStepper?.step(by: 1) }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(!(weekStepper?.canStep(by: 1) ?? false))
      Button("Go to Today") { weekStepper?.goToToday() }
        .disabled(weekStepper?.isCurrent ?? true)
      Divider()
    }
  }
}

extension FocusedValues {
  /// Set by Week only, so its steps are disabled on every other screen.
  @Entry var weekStepper: WeekStepper?
}
