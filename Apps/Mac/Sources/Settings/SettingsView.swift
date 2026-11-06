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
              source: model.source, lastImport: model.lastImport, note: model.omniFocusNote))
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
    case .note(let note): OmniFocusWords.text(note)
    }
  }
}

/// The OmniFocus line of the Data group.
enum OmniFocusLine: Equatable {
  case notReadInDemo
  /// Nil when the duration could not be measured: no number, never 0.
  case lastImport(Duration?)
  case notReadYet
  case note(SourceFeed.OmniFocusNote)

  init(source: AppModel.Source, lastImport: ImportRun?, note: SourceFeed.OmniFocusNote?) {
    if source == .demo {
      self = .notReadInDemo
    } else if let note {
      self = .note(note)
    } else if let lastImport {
      self = .lastImport(lastImport.duration)
    } else {
      self = .notReadYet
    }
  }
}
