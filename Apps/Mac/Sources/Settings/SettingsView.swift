import MoonShineCore
import SwiftUI

/// Settings (⌘,), applied at once (`design/screens/settings.md`). The Data group only; the
/// other groups come with S4-3c.
struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Data") {
        Picker(
          "Source",
          selection: Binding(get: { model.source }, set: { model.select($0) })
        ) {
          Text("Demo").tag(AppModel.Source.demo)
          Text("Live").tag(AppModel.Source.live)
        }
        .pickerStyle(.segmented)
        LabeledContent("OmniFocus") {
          line(
            OmniFocusLine(
              source: model.source, lastImport: model.lastImport, note: model.omniFocusNote,
              unavailable: TodayPlaceholder(model) == .liveUnavailable))
        }
        LabeledContent("Tag groups") {
          line(TagGroupsLine(model))
        }
        Text(
          "Demo shows bundled sample data — nothing is read from OmniFocus or your vault."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 580)
  }

  private func line(_ line: OmniFocusLine) -> Text {
    switch line {
    case .notReadInDemo: Text("not read in Demo mode")
    case .lastImport(let duration?):
      Text("last full import \(Double(duration / .milliseconds(1)) / 1_000, specifier: "%.1f") s")
    case .lastImport(nil): Text("last full import")
    case .notReadYet: Text("not read yet")
    case .unavailable: Text("Live data could not be opened.")
    case .note(let note): OmniFocusWords.text(note)
    }
  }

  private func line(_ line: TagGroupsLine) -> Text {
    switch line {
    case .found(let found, let of): Text("groups found: \(found) of \(of)")
    case .notCountedYet: Text("not counted yet")
    case .missing:
      Text(
        "no mapping file — no tag group is read as attributes. Add mapping.yaml to the data folder, then reopen MoonShine."
      )
    case .invalid: Text("mapping.yaml cannot be read — fix it, then reopen MoonShine")
    case .liveUnavailable: Text("Live data could not be opened.")
    case .demoUnavailable: Text("Demo data could not be loaded.")
    }
  }
}

/// The Tag groups line of the Data group: how many of the mapped groups a top-level tag was
/// found for, counted from the workspace shown (S4-4c-2).
enum TagGroupsLine: Equatable {
  case found(Int, of: Int)
  /// Nothing imported yet to count in.
  case notCountedYet
  case missing
  case invalid
  case liveUnavailable
  case demoUnavailable

  @MainActor init(_ model: AppModel) {
    var workspace: Workspace?
    if case .loaded(let overview) = model.state { workspace = overview.workspace }
    self.init(source: model.source, mapping: model.mapping, workspace: workspace)
  }

  init(source: AppModel.Source, mapping: MappingState?, workspace: Workspace?) {
    switch mapping {
    case nil: self = source == .live ? .liveUnavailable : .demoUnavailable
    case .missing: self = .missing
    case .invalid: self = .invalid
    case .demo(let groups), .groups(let groups):
      self = workspace.map { .found($0.metaGroupsFound, of: groups) } ?? .notCountedYet
    }
  }
}

/// The OmniFocus line of the Data group.
enum OmniFocusLine: Equatable {
  case notReadInDemo
  /// Nil when the duration could not be measured: no number, never 0.
  case lastImport(Duration?)
  case notReadYet
  /// Where Today says `Live data could not be opened.`: never "not read yet".
  case unavailable
  case note(SourceFeed.OmniFocusNote)

  init(
    source: AppModel.Source, lastImport: ImportRun?, note: SourceFeed.OmniFocusNote?,
    unavailable: Bool = false
  ) {
    if source == .demo {
      self = .notReadInDemo
    } else if unavailable {
      self = .unavailable
    } else if let note {
      self = .note(note)
    } else if let lastImport {
      self = .lastImport(lastImport.duration)
    } else {
      self = .notReadYet
    }
  }
}
