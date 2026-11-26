import AppKit
import MoonShineCore
import SwiftUI

/// What the app may open: MoonShine's own values, never a URL or a string, so a link taken from
/// note or task text has no way in (ADR-0015, amendments of 2026-10-10 to 2026-10-21).
enum OpenTarget: Hashable {
  case task(TaskItemID)
  case project(ProjectID)
  case note(NoteID)
}

/// What came of one open. None carries a path, a name, an id or a title.
enum OpenOutcome: Hashable {
  case opened
  /// The note's file is not where the store says, byte for byte (ADR-0015, 2026-10-13).
  case noteNotFound
  case vaultUnavailable(VaultReason)
  /// No OmniFocus id, an id outside its alphabet, no URL, or no app took it.
  case notOpened
  /// Demo's ids and paths are invented: nothing opens (owner, 2026-11-25).
  case demo
  /// A newer open started while this one looked its note up: the latest open wins, so this one
  /// opens nothing and leaves the notice alone (PR #73 round 2).
  case superseded

  enum VaultReason: Hashable {
    case notChosen
    case unreadable
  }
}

/// Hands a URL to the app that owns its scheme; a recorder in tests.
protocol URLOpening {
  @MainActor func open(_ url: URL) -> Bool
}

/// The one place the app opens a URL (`scripts/check-vault-writes.mjs` allows this call here
/// once); private, so no other file can reach it without the opener's checks.
private struct WorkspaceOpening: URLOpening {
  func open(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }
}

/// The one opener (S4-5): builds MoonShine's own URL for a stored task, project or note, checks
/// it, and opens it. Nothing about the item is logged or shown; the notice names the outcome only.
@MainActor @Observable
final class LinkOpener {
  /// Shown on the left of the status bar for `noticeDelay`, then the freshness text returns.
  private(set) var notice: OpenOutcome?
  /// The task that clears the notice; a new notice cancels it (owner, 2026-11-25).
  @ObservationIgnored private(set) var clearing: Task<Void, Never>?
  @ObservationIgnored private let opening: any URLOpening
  @ObservationIgnored private let vault: VaultFolder
  @ObservationIgnored private let noticeDelay: Duration
  @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
  /// The newest open's number: only that open may open or touch the notice.
  @ObservationIgnored private var latest = 0

  /// How long a notice stays (owner, 2026-11-25).
  static let noticeDelay: Duration = .seconds(5)

  static func production(vault: VaultFolder) -> LinkOpener {
    LinkOpener(
      opening: WorkspaceOpening(), vault: vault, noticeDelay: noticeDelay,
      sleep: { try? await Task.sleep(for: $0) })
  }

  init(
    opening: any URLOpening, vault: VaultFolder, noticeDelay: Duration,
    sleep: @escaping @Sendable (Duration) async -> Void
  ) {
    self.opening = opening
    self.vault = vault
    self.noticeDelay = noticeDelay
    self.sleep = sleep
  }

  /// Opens `target` from the workspace shown; any outcome but `.opened` becomes the notice, and
  /// `.opened` clears an earlier one, so the bar never reports an older failure. The latest
  /// open wins: one overtaken while it looked its note up is `.superseded` (PR #73 round 2).
  @discardableResult
  func open(_ target: OpenTarget, in overview: Overview, isDemo: Bool) async -> OpenOutcome {
    latest += 1
    let number = latest
    let outcome: OpenOutcome
    if isDemo {
      outcome = .demo
    } else {
      let result = await url(target, in: overview.workspace)
      guard number == latest else { return .superseded }
      switch result {
      case .success(let url): outcome = opening.open(url) ? .opened : .notOpened
      case .failure(let refusal): outcome = refusal.outcome
      }
    }
    if outcome == .opened { hideNotice() } else { show(outcome) }
    return outcome
  }

  /// A link inside text, from the root `openURL` action: in phase 1 every one is dropped,
  /// `http` and `https` included, until a spec shows a URL before it opens (owner, 2026-11-25).
  func openFromText(_ url: URL) -> OpenURLAction.Result {
    .discarded
  }

  /// The notice's words; none holds a path, a name, an id or a title.
  static func text(_ outcome: OpenOutcome) -> String? {
    switch outcome {
    case .opened: nil
    case .noteNotFound: String(localized: "Note not found")
    case .vaultUnavailable(.notChosen): String(localized: "Vault not chosen")
    case .vaultUnavailable(.unreadable): String(localized: "Vault can't be read")
    case .notOpened: String(localized: "Could not open it")
    case .demo: String(localized: "Demo data — opens with Live data")
    case .superseded: nil
    }
  }

  private func hideNotice() {
    clearing?.cancel()
    clearing = nil
    notice = nil
  }

  private func show(_ outcome: OpenOutcome) {
    clearing?.cancel()
    notice = outcome
    if let text = Self.text(outcome) { AccessibilityNotification.Announcement(text).post() }
    let delay = noticeDelay
    let sleep = sleep
    clearing = Task { [weak self] in
      await sleep(delay)
      guard !Task.isCancelled else { return }
      self?.notice = nil
    }
  }

  private struct Refusal: Error {
    let outcome: OpenOutcome
  }

  private func url(_ target: OpenTarget, in workspace: Workspace) async -> Result<URL, Refusal> {
    let notOpened = Refusal(outcome: .notOpened)
    switch target {
    case .task(let id):
      let task = workspace.tasks.first { $0.id == id }
      return Self.omniFocusID(task?.refs).flatMap(OmniFocusLink.task).map { .success($0) }
        ?? .failure(notOpened)
    case .project(let id):
      let project = workspace.projects.first { $0.id == id }
      return Self.omniFocusID(project?.refs).flatMap(OmniFocusLink.project).map { .success($0) }
        ?? .failure(notOpened)
    case .note(let id):
      guard let note = workspace.notes.first(where: { $0.id == id }) else {
        return .failure(Refusal(outcome: .noteNotFound))
      }
      let root: URL
      switch await vault.resolve() {
      case .notChosen: return .failure(Refusal(outcome: .vaultUnavailable(.notChosen)))
      case .unreadable: return .failure(Refusal(outcome: .vaultUnavailable(.unreadable)))
      case .folder(let url): root = url
      }
      switch await Self.locate(path: note.path, in: root) {
      case .vaultUnreadable: return .failure(Refusal(outcome: .vaultUnavailable(.unreadable)))
      case .notFound: return .failure(Refusal(outcome: .noteNotFound))
      case .file(let vault, let path):
        return ObsidianLink.open(vault: vault, file: path).map { .success($0) }
          ?? .failure(notOpened)
      }
    }
  }

  /// Where a stored note path leads in the vault.
  enum NoteLookup: Equatable {
    case vaultUnreadable
    case notFound
    /// The vault's folder name and the vault-relative path, in the names the file system keeps,
    /// for Obsidian's exact lookup (PR #73 rounds 1 and 2).
    case file(vault: String, path: String)
  }

  /// The vault check and the walk, off the main actor: a slow or sleeping volume never holds
  /// the window (PR #73 round 1).
  @concurrent nonisolated static func locate(path: String, in root: URL) async -> NoteLookup {
    let scoped = root.startAccessingSecurityScopedResource()
    defer { if scoped { root.stopAccessingSecurityScopedResource() } }
    // A resolved bookmark's URL is decomposed; the name key gives the folder's name on disk.
    guard VaultFolder.isVault(root), let vault = try? root.resourceValues(forKeys: [.nameKey]).name
    else { return .vaultUnreadable }
    return noteFile(root: root, path: path).map { .file(vault: vault, path: $0) } ?? .notFound
  }

  private static func omniFocusID(_ refs: [ExternalRef]?) -> String? {
    refs?.first { $0.provider == .omnifocus }?.externalId
  }

  /// The note's file, walked from the vault root one component at a time: each is listed in
  /// its folder byte for byte (APFS ignores case and Unicode form, Obsidian does not), none is
  /// hidden (Obsidian indexes no hidden folder), `.` or `..`, or a symbolic link, and the last
  /// is a regular file. An entry is compared in the form the vault walk stores it, the last
  /// component of its standardized path (`ObsidianAdapter/VaultWalk.swift`, `relativePath`),
  /// which Foundation decomposes; the path returned is in the names on disk (PR #73 round 1).
  nonisolated static func noteFile(root: URL, path: String) -> String? {
    guard !path.hasPrefix("/") else { return nil }
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
    var folder = root
    var onDisk: [String] = []
    for (index, component) in components.enumerated() {
      guard !component.isEmpty, !component.hasPrefix("."),
        let items = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: keys),
        let item = items.first(where: {
          storedName($0).unicodeScalars.elementsEqual(component.unicodeScalars)
        }),
        let values = try? item.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true
      else { return nil }
      onDisk.append(item.lastPathComponent)
      if index == components.count - 1 {
        return values.isRegularFile == true ? onDisk.joined(separator: "/") : nil
      }
      guard values.isDirectory == true else { return nil }
      folder = item
    }
    return nil
  }

  /// An entry's name as the vault walk stores it: the last component of its standardized path.
  nonisolated private static func storedName(_ item: URL) -> String {
    item.standardizedFileURL.path.split(separator: "/").last.map(String.init) ?? ""
  }
}

extension EnvironmentValues {
  /// Opens a task, project or note through the one opener; set at each scene's root.
  @Entry var openTarget: @MainActor (OpenTarget) -> Void = { _ in
    assertionFailure("a view outside linksThroughOpener asked to open")
  }
}

extension FocusedValues {
  /// The project ⌘↵ opens: set by Line detail only, so it is nil on every other screen.
  @Entry var lineProject: OpenTarget?
}

/// Open in OmniFocus, ⌘↵, beside Refresh: the line's first project, as Line detail's toolbar
/// opens it; disabled everywhere else, Today included, which has ↵ (owner, 2026-11-26). ⌘↵
/// opens in the other app everywhere (`design/principles.md`).
struct OpenCommands: Commands {
  let model: AppModel
  @FocusedValue(\.lineProject) private var project

  /// ⌘↵: opens in the other app everywhere (design/principles.md).
  static let shortcut = KeyboardShortcut(.return, modifiers: .command)

  /// The first project in Line detail's Projects order; nil with no project or no screen.
  static func target(_ screen: LineDetailScreen?) -> OpenTarget? {
    screen?.projects.first.map { .project($0.id) }
  }

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Button("Open in OmniFocus") {
        if let project { model.open(project) }
      }
      .keyboardShortcut(Self.shortcut)
      .disabled(project == nil)
    }
  }
}

/// Every link in a scene goes through the opener: MoonShine's own targets through
/// `openTarget`, and a link inside any text or catalog string through the `openURL` action,
/// which drops it (`scripts/check-vault-writes.mjs` requires it on both scenes).
private struct LinksThroughOpener: ViewModifier {
  let opener: LinkOpener
  let open: @MainActor (OpenTarget) -> Void

  func body(content: Content) -> some View {
    content
      .environment(\.openURL, OpenURLAction { opener.openFromText($0) })
      .environment(\.openTarget, open)
  }
}

/// A double-click anywhere in the view's frame opens `target`, gaps included; a single click
/// keeps its own action.
private struct OpensOnDoubleClick: ViewModifier {
  let target: OpenTarget
  @Environment(\.openTarget) private var openTarget

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .simultaneousGesture(TapGesture(count: 2).onEnded { openTarget(target) })
  }
}

extension View {
  func linksThroughOpener(_ model: AppModel) -> some View {
    modifier(LinksThroughOpener(opener: model.linkOpener, open: { model.open($0) }))
  }

  func opensOnDoubleClick(_ target: OpenTarget) -> some View {
    modifier(OpensOnDoubleClick(target: target))
  }
}
