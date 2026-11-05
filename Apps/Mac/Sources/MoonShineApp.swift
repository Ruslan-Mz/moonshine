import SwiftUI

@main
struct MoonShineApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .task { model.start() }
    }
    .defaultSize(width: 1440, height: 900)
    .commands {
      CommandGroup(before: .sidebar) {
        // ⌘2–⌘4 come with the views they open (S4-2, S5).
        Button("Today") { model.selection = .today }
          .keyboardShortcut("1", modifiers: .command)
        Divider()
      }
      CommandGroup(after: .toolbar) {
        Button("Refresh") { model.refresh() }
          .keyboardShortcut("r", modifiers: .command)
      }
      TodayCommands()
      // Show / Hide Inspector, ⌃⌘I, in the View menu.
      InspectorCommands()
    }
  }
}
