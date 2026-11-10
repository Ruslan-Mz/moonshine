import MoonShineCore
import ObsidianAdapter
import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌘,), applied at once (`design/screens/settings.md`). The Data group only; the
/// other groups come with S4-3c.
struct SettingsView: View {
  @Bindable var model: AppModel
  /// The vault picker: `Choose…`, and a switch to Live with no folder chosen (S4-4d).
  @State private var choosingVault = false

  var body: some View {
    Form {
      Section("Data") {
        Picker(
          "Source",
          selection: Binding(
            get: { model.source },
            set: { new in
              model.select(new)
              // Switching to Live without a vault asks for one, not an error (settings.md).
              if model.source == .live, model.vaultFolder.chosen == nil { choosingVault = true }
            })
        ) {
          Text("Demo").tag(AppModel.Source.demo)
          Text("Live").tag(AppModel.Source.live)
        }
        .pickerStyle(.segmented)
        LabeledContent("Obsidian vault") {
          HStack(spacing: 8) {
            line(VaultLine(model))
            Button("Choose…") { choosingVault = true }
              .disabled(model.source != .live)
          }
        }
        if let refusal = model.vaultRefusal {
          Group {
            switch refusal {
            case .notAVault:
              Text(
                "This folder is not an Obsidian vault — choose the folder that holds .obsidian")
            case .bookmarkFailed: Text("Can't be read — choose it again")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        LabeledContent("OmniFocus") {
          line(
            OmniFocusLine(
              source: model.source, lastImport: model.lastImport, note: model.omniFocusNote,
              unavailable: TodayPlaceholder(model) == .liveUnavailable))
        }
        LabeledContent("Tag groups") {
          line(TagGroupsLine(model))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(
            "Demo shows bundled sample data — nothing is read from OmniFocus or your vault."
          )
          Text("The vault is opened read-only through a security-scoped bookmark.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 580)
    .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
      if case .success(let url) = result { model.chooseVault(url) }
    }
  }

  private func line(_ line: VaultLine) -> some View {
    Group {
      switch line {
      case .notReadInDemo: Text("not read in Demo mode")
      case .notChosen: Text("Not chosen")
      case .notReadYet: Text("Not read yet")
      case .unreadable: Text("Can't be read — choose it again")
      case .tooLarge(let limit): Text("More than \(limit) notes — not read")
      case .folder(let name): Label(name, systemImage: "folder")
      }
    }
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
        "no mapping file — no tag group is read as attributes. Add mapping.yaml to the data folder, then quit MoonShine (⌘Q) and open it again."
      )
    // The OmniFocus line's sentence: one sentence for an invalid file.
    case .invalid: OmniFocusWords.text(.failure(.mappingInvalid))
    case .liveUnavailable: Text("Live data could not be opened.")
    case .demoUnavailable: Text("Demo data could not be loaded.")
    }
  }
}

/// The Obsidian vault line of the Data group (S4-4d): the folder's name only, never its path,
/// and never the bookmark in Demo.
enum VaultLine: Equatable {
  case notReadInDemo
  case notChosen
  /// Chosen after the shown import started, or that import had none chosen.
  case notReadYet
  case unreadable
  case tooLarge(Int)
  case folder(String)

  @MainActor init(_ model: AppModel) {
    var workspace: Workspace?
    if case .loaded(let overview) = model.state { workspace = overview.workspace }
    self.init(
      source: model.source, chosen: model.vaultFolder.chosen, workspace: workspace,
      lastImport: model.lastImport)
  }

  init(
    source: AppModel.Source, chosen: StoredBookmark?, workspace: Workspace?,
    lastImport: ImportRun?
  ) {
    guard source == .live else {
      self = .notReadInDemo
      return
    }
    guard let chosen else {
      self = .notChosen
      return
    }
    let kinds = Self.vaultWideKinds(workspace)
    let readBefore = lastImport.map { $0.startedAt >= chosen.savedAt } ?? false
    if workspace == nil || !readBefore || kinds.contains(.vaultNotChosen) {
      self = .notReadYet
    } else if kinds.contains(.vaultUnreadable) {
      self = .unreadable
    } else if kinds.contains(.vaultTooLarge) {
      self = .tooLarge(VaultLimits().maxNotes)
    } else {
      self = .folder(chosen.name)
    }
  }

  /// The shown workspace's vault was not read: none shown, or not chosen, unreadable or too
  /// large.
  static func vaultNotRead(_ workspace: Workspace?) -> Bool {
    guard workspace != nil else { return true }
    return !vaultWideKinds(workspace).isDisjoint(with: [
      .vaultNotChosen, .vaultUnreadable, .vaultTooLarge,
    ])
  }

  private static func vaultWideKinds(_ workspace: Workspace?) -> Set<VaultProblem.Kind> {
    Set(
      (workspace?.issues ?? []).compactMap { issue in
        if case .vaultWide(let problem) = issue { problem.kind } else { nil }
      })
  }
}

/// The Tag groups line of the Data group: how many of the current mapping's groups a top-level
/// tag of the workspace shown has the name of (S4-4c-2), whatever groups it was imported under.
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
      self = workspace.map { .found($0.groupsFound(groups), of: groups.count) } ?? .notCountedYet
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
