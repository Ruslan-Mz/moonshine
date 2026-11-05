import MoonShineCore
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
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
    }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .loaded(let overview):
      // Dates follow the workspace's zone, so Demo reads the same on any Mac.
      let zone = overview.workspace.timeZone
      TodayContainer(overview: overview)
        .environment(\.timeZone, zone)
        .environment(\.calendar, TodayFormat.calendar(zone))
    case .unavailable:
      ContentUnavailableView("Demo data could not be loaded.", systemImage: "tray")
    }
  }
}

/// Source and freshness. The minute's tick only redraws; the time is the model's clock. The
/// tick falls on the clock's whole minutes, so a step can show up to a minute late: the text
/// counts in minutes. A finished import redraws at once: the body reads `lastImport`.
struct StatusBar: View {
  let model: AppModel
  @Environment(\.locale) private var locale

  var body: some View {
    HStack {
      Text("Demo data")
      if case .loaded(let overview) = model.state, model.lastImport != nil {
        TimelineView(.everyMinute) { _ in
          if let freshness = model.freshness() {
            text(freshness, timeZone: overview.workspace.timeZone)
          }
        }
      }
      if model.isImporting {
        ProgressView().controlSize(.mini)
        Text("Updating…")
      }
      Spacer()
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }

  private func text(_ freshness: Freshness, timeZone: TimeZone) -> Text {
    switch freshness {
    case .justNow: Text("Updated just now")
    case .minutes(let minutes): Text("Updated \(minutes) min ago")
    case .hours(let hours): Text("Updated \(hours) h ago")
    case .day(let day):
      Text(
        "Updated on \(TodayFormat.lastDate(day, today: model.clock.wall(), timeZone: timeZone, locale: locale))"
      )
    }
  }
}
