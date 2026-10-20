import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationSplitView {
      // Week, Month and Lines join with their slices (S4-2, S5).
      List(selection: $model.selection) {
        Label("Today", systemImage: "sun.max").tag(SidebarItem.today)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    } detail: {
      content
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
    }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .loaded(let screen):
      // Dates follow the workspace's zone, so Demo reads the same on any Mac.
      TodayView(screen: screen)
        .environment(\.timeZone, screen.timeZone)
        .environment(\.calendar, TodayFormat.calendar(screen.timeZone))
    case .unavailable:
      ContentUnavailableView("Demo data could not be loaded.", systemImage: "tray")
    }
  }
}

/// Source and freshness; "updated N min ago" comes with the imports table (S4-4a).
struct StatusBar: View {
  var body: some View {
    HStack {
      Text("Demo data")
      Spacer()
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }
}
