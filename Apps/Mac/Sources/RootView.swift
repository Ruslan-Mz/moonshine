import MoonShineCore
import SwiftUI

/// The sidebar's entries; a plain path for auto-merge (scripts/guard/plain-rules.mjs), so a slice
/// that adds a screen need not touch AppModel.swift.
enum SidebarItem: Hashable {
  case today
  case lines
}

struct RootView: View {
  @Bindable var model: AppModel

  /// The sidebar's ideal width.
  static let sidebarWidth: CGFloat = 200

  var body: some View {
    NavigationSplitView {
      // Week and Month join with their slices (S5).
      List(selection: $model.selection) {
        Label("Today", systemImage: "sun.max").tag(SidebarItem.today)
        Label("Lines", systemImage: "chart.bar").tag(SidebarItem.lines)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: Self.sidebarWidth)
    } detail: {
      // The bar takes its own height, so no row ends under it (owner, 2026-11-11).
      VStack(spacing: 0) {
        content.frame(maxHeight: .infinity)
        StatusBar(model: model)
      }
      .toolbar {
        // The same request as ⌘R, whose shortcut stays on the menu item (S4-3c-2).
        Button {
          model.refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help(Text("Refresh (⌘R)"))
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .help(Text("Settings (⌘,)"))
      }
    }
  }

  @ViewBuilder private var content: some View {
    if case .loaded(let overview) = model.state {
      // Dates follow the workspace's zone, so Demo reads the same on any Mac.
      let zone = overview.workspace.timeZone
      Group {
        switch model.selection {
        case .lines: LinesDetail(overview: overview)
        case .today, nil: TodayDetail(model: model, overview: overview)
        }
      }
      .environment(\.timeZone, zone)
      .environment(\.calendar, TodayFormat.calendar(zone))
      .environment(\.dayRailInput, model.dayRailInput(calendar: overview.calendar))
      .onChange(of: overview.calendar.dateInterval(of: .day, for: overview.now), initial: true) {
        _, day in
        if let day { model.showCalendarDay(day) }
      }
      // Another source is another workspace: an open Line detail goes back to Lines.
      .id(model.source)
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
  /// The last run could not read OmniFocus; Settings says why (owner, 2026-11-24).
  case omniFocusUnreadable
  case importUnfinished
  /// Shown whatever OmniFocus' state: no import runs until a valid file and a relaunch (⌘Q,
  /// then open: reopening a running app keeps the file it read).
  case mappingInvalid
  case vault(VaultReason)

  /// Why the vault was not read for the workspace shown, in the words of the Settings row.
  enum VaultReason: Hashable {
    case notChosen
    case unreadable
    case tooLarge
    case notReadYet
  }

  @MainActor static func notes(_ model: AppModel) -> [LiveNote] {
    var workspace: Workspace?
    if case .loaded(let overview) = model.state { workspace = overview.workspace }
    return notes(
      source: model.source, workspace: workspace, vault: VaultLine(model),
      omniFocusNote: model.omniFocusNote, mapping: model.mapping)
  }

  /// `workspace` is the one shown, nil while none is.
  static func notes(
    source: AppModel.Source, workspace: Workspace?, vault: VaultLine,
    omniFocusNote: SourceFeed.OmniFocusNote?, mapping: MappingState?
  ) -> [LiveNote] {
    guard source == .live else { return [] }
    var notes: [LiveNote] = []
    // With nothing shown, Today's placeholder says what OmniFocus did.
    if workspace != nil, let omniFocusNote, let note = note(omniFocusNote) { notes.append(note) }
    if mapping == .invalid { notes.append(.mappingInvalid) }
    // Only while the vault was not read for the workspace shown (owner, 2026-11-10), in the
    // Settings row's words (owner, 2026-11-24).
    if VaultLine.vaultNotRead(workspace) { notes.append(.vault(VaultReason(vault))) }
    return notes
  }

  /// An invalid file has its own note, from the mapping.
  private static func note(_ note: SourceFeed.OmniFocusNote) -> LiveNote? {
    switch note {
    case .notRunning, .failure(.providerNotRunning): .notRunning
    case .failure(.permissionDenied), .failure(.timedOut), .failure(.invalidSnapshot),
      .failure(.partialSnapshot):
      .omniFocusUnreadable
    case .failure(.other): .importUnfinished
    case .failure(.mappingInvalid): nil
    }
  }
}

extension LiveNote.VaultReason {
  /// Under `VaultLine.vaultNotRead` the row is one of the first three or not read yet.
  init(_ line: VaultLine) {
    switch line {
    case .notChosen: self = .notChosen
    case .unreadable: self = .unreadable
    case .tooLarge: self = .tooLarge
    case .notReadYet, .notReadInDemo, .folder: self = .notReadYet
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
      // In the order of `design/screens/settings.md` § Status bar.
      Text(model.source == .live ? "Live" : "Demo data")
      // An open that did not open says so for a few seconds in the freshness text's place
      // (owner, 2026-11-25, S4-5).
      if let notice = model.linkOpener.notice.flatMap(LinkOpener.text) {
        Text(verbatim: notice)
      } else if case .loaded(let overview) = model.state, model.lastImport != nil {
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
        case .omniFocusUnreadable: Text("OmniFocus can't be read — see Settings")
        case .importUnfinished: OmniFocusWords.text(.failure(.other))
        case .vault(.notChosen): Text("Vault not chosen")
        case .vault(.unreadable): Text("Vault can't be read")
        case .vault(.tooLarge): Text("Vault too large to read")
        case .vault(.notReadYet): Text("Vault not read yet")
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
