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

  static func production(vault: VaultFolder) -> LinkOpener {
    LinkOpener(
      opening: WorkspaceOpening(), vault: vault, noticeDelay: .seconds(5),
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

  /// Opens `target` from the workspace shown; any outcome but `.opened` becomes the notice.
  @discardableResult
  func open(_ target: OpenTarget, in overview: Overview, isDemo: Bool) async -> OpenOutcome {
    let outcome: OpenOutcome
    if isDemo {
      outcome = .demo
    } else {
      switch await url(target, in: overview.workspace) {
      case .success(let url): outcome = opening.open(url) ? .opened : .notOpened
      case .failure(let refusal): outcome = refusal.outcome
      }
    }
    if outcome != .opened { show(outcome) }
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
    }
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
      let scoped = root.startAccessingSecurityScopedResource()
      defer { if scoped { root.stopAccessingSecurityScopedResource() } }
      guard VaultFolder.isVault(root) else {
        return .failure(Refusal(outcome: .vaultUnavailable(.unreadable)))
      }
      guard Self.noteExists(root: root, path: note.path) else {
        return .failure(Refusal(outcome: .noteNotFound))
      }
      return ObsidianLink.open(vault: root.lastPathComponent, file: note.path).map { .success($0) }
        ?? .failure(notOpened)
    }
  }

  private static func omniFocusID(_ refs: [ExternalRef]?) -> String? {
    refs?.first { $0.provider == .omnifocus }?.externalId
  }

  /// The note's file, walked from the vault root one component at a time: each is listed in
  /// its folder byte for byte (APFS ignores case and Unicode form, Obsidian does not), none is
  /// hidden (Obsidian indexes no hidden folder), `.` or `..`, or a symbolic link, and the last
  /// is a regular file. Folders are listed as URLs, as the vault walk lists them
  /// (`ObsidianAdapter/VaultWalk.swift`), so a stored path reads back in the form it was stored.
  nonisolated static func noteExists(root: URL, path: String) -> Bool {
    guard !path.hasPrefix("/") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
    var folder = root
    for (index, component) in components.enumerated() {
      guard !component.isEmpty, !component.hasPrefix("."),
        let items = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: keys),
        let item = items.first(where: {
          $0.lastPathComponent.unicodeScalars.elementsEqual(component.unicodeScalars)
        }),
        let values = try? item.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true
      else { return false }
      if index == components.count - 1 { return values.isRegularFile == true }
      guard values.isDirectory == true else { return false }
      folder = item
    }
    return false
  }
}

extension EnvironmentValues {
  /// Opens a task, project or note through the one opener; set at each scene's root.
  @Entry var openTarget: @MainActor (OpenTarget) -> Void = { _ in
    assertionFailure("a view outside linksThroughOpener asked to open")
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

/// A double-click anywhere on the view opens `target`; a single click keeps its own action.
private struct OpensOnDoubleClick: ViewModifier {
  let target: OpenTarget
  @Environment(\.openTarget) private var openTarget

  func body(content: Content) -> some View {
    content.simultaneousGesture(TapGesture(count: 2).onEnded { openTarget(target) })
  }
}

extension View {
  func linksThroughOpener(_ model: AppModel) -> some View {
    modifier(LinksThroughOpener(opener: model.linkOpener, open: model.open))
  }

  func opensOnDoubleClick(_ target: OpenTarget) -> some View {
    modifier(OpensOnDoubleClick(target: target))
  }
}
