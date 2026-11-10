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
    if case .loaded(let overview) = model.state {
      // Dates follow the workspace's zone, so Demo reads the same on any Mac.
      let zone = overview.workspace.timeZone
      TodayContainer(
        overview: overview,
        removal: LineRemovalHold(
          isApproved: model.removalApproved, omniFocusClosed: model.omniFocusNote == .notRunning,
          keptByIncompleteRead: model.removalKept, approve: { model.approveHeldRemoval() })
      )
      .environment(\.timeZone, zone)
      .environment(\.calendar, TodayFormat.calendar(zone))
    } else {
      switch TodayPlaceholder(model) {
      case .importing, nil:
        ProgressView()
      case .demoUnavailable:
        ContentUnavailableView("Demo data could not be loaded.", systemImage: "tray")
      case .liveUnavailable:
        ContentUnavailableView("Live data could not be opened.", systemImage: "tray")
      case .notReadYet(let note):
        ContentUnavailableView {
          Label("MoonShine has not read OmniFocus yet", systemImage: "tray")
        } description: {
          note.map(OmniFocusWords.text) ?? Text("Press ⌘R to read OmniFocus")
        }
      }
    }
  }
}

/// What Today shows instead of data. Nil when it shows data.
enum TodayPlaceholder: Equatable {
  case importing
  case demoUnavailable
  /// Live's folder, store or script could not be opened, or its store cannot be read: never
  /// "not read yet", which would invite an import over a store that holds history.
  case liveUnavailable
  /// With the note, or none: then ⌘R reads OmniFocus.
  case notReadYet(SourceFeed.OmniFocusNote?)

  @MainActor init?(_ model: AppModel) {
    switch (model.state, model.source) {
    case (.loaded, _): return nil
    case (_, _) where model.isImporting: self = .importing
    case (.loading, .demo): self = .importing
    case (.unavailable, .demo): self = .demoUnavailable
    // Until the store has been looked at, a store with history must not read "not read yet".
    case (.loading, .live):
      self = model.storeChecked ? .notReadYet(model.omniFocusNote) : .importing
    case (.unavailable, .live):
      // A failed first import names its kind; nothing named means Live could not be opened.
      let note = model.omniFocusNote
      self = model.storeUnreadable || note == nil ? .liveUnavailable : .notReadYet(note)
    }
  }
}

/// The words of an OmniFocus note; no "failed" (CLAUDE.md rule 8).
enum OmniFocusWords {
  static func text(_ note: SourceFeed.OmniFocusNote) -> Text {
    switch note {
    case .notRunning: Text("OmniFocus is not running")
    case .failure(.providerNotRunning): Text("OmniFocus is not running")
    case .failure(.permissionDenied):
      Text(
        "MoonShine is not allowed to read OmniFocus yet — allow it in System Settings → Privacy & Security → Automation"
      )
    case .failure(.timedOut):
      Text(
        "OmniFocus did not answer in time. If macOS is asking for permission, answer it, then press ⌘R."
      )
    case .failure(.invalidSnapshot), .failure(.partialSnapshot):
      Text("OmniFocus sent data MoonShine cannot read")
    case .failure(.mappingInvalid):
      Text("The mapping file cannot be read — fix it, then quit MoonShine (⌘Q) and open it again")
    case .failure(.other): Text("The last import did not finish")
    }
  }
}

/// Live's sentences in the status bar, in order, beside its data.
enum LiveNote: Hashable {
  case notRunning
  /// Shown whatever OmniFocus' state: no import runs until a valid file and a relaunch (⌘Q,
  /// then open: reopening a running app keeps the file it read).
  case mappingInvalid
  case vaultNotRead

  @MainActor static func notes(_ model: AppModel) -> [LiveNote] {
    guard model.source == .live else { return [] }
    var notes: [LiveNote] = []
    if case .loaded = model.state, model.omniFocusNote == .notRunning { notes.append(.notRunning) }
    if model.mapping == .invalid { notes.append(.mappingInvalid) }
    // Only while the shown import did not read the vault; Settings says why (owner, 2026-11-10).
    var workspace: Workspace?
    if case .loaded(let overview) = model.state { workspace = overview.workspace }
    if VaultLine.vaultNotRead(workspace) { notes.append(.vaultNotRead) }
    return notes
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
      // In the order of `design/screens/settings.md` § Status bar.
      Text(model.source == .live ? "Live" : "Demo data")
      if case .loaded(let overview) = model.state, model.lastImport != nil {
        TimelineView(.everyMinute) { _ in
          if let freshness = model.freshness() {
            text(freshness, timeZone: overview.workspace.timeZone)
          }
        }
      }
      ForEach(LiveNote.notes(model), id: \.self) { note in
        switch note {
        case .notRunning: Text("OmniFocus is not running — showing the last import")
        // The one sentence for an invalid file, here and in Settings.
        case .mappingInvalid: OmniFocusWords.text(.failure(.mappingInvalid))
        case .vaultNotRead: Text("Vault not read yet")
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
