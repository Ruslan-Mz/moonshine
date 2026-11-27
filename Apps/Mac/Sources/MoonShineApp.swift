import SwiftUI

@main
struct MoonShineApp: App {
  @State private var model = AppModel.production()

  var body: some Scene {
    WindowGroup {
      // Every link in the window goes through the one opener (S4-5).
      RootView(model: model)
        .linksThroughOpener(model)
        .task { model.start() }
    }
    .defaultSize(width: 1440, height: 900)
    .commands {
      ViewCommands(model: model)
      CommandGroup(after: .toolbar) {
        Button("Refresh") { model.refresh() }
          .keyboardShortcut("r", modifiers: .command)
      }
      OpenCommands(model: model)
      TodayCommands()
      LineRemovalCommands()
      // Show / Hide Inspector, ⌃⌘I, in the View menu.
      InspectorCommands()
    }
    Settings {
      SettingsView(model: model)
        .linksThroughOpener(model)
    }
  }
}
