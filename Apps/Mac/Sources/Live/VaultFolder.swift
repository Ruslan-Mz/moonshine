import Foundation
import MoonShineCore
import Observation
import ObsidianAdapter

/// The vault folder the owner chose (S4-4d; `design/screens/settings.md`, Data group): a
/// security-scoped, read-only bookmark kept in `AppSettings`, never a path in a file. Every
/// read and write of it runs on the main actor, so a choice and a refresh never interleave.
/// The path is never logged, printed or put into an error.
@MainActor @Observable
final class VaultFolder {
  /// How a bookmark is made and resolved; tests pass fakes.
  struct Bookmarks: Sendable {
    let make: @Sendable (URL) throws -> Data
    let resolve: @Sendable (Data) throws -> (url: URL, isStale: Bool)

    static let securityScoped = Bookmarks(
      make: { url in
        try url.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil, relativeTo: nil)
      },
      resolve: { data in
        var isStale = false
        let url = try URL(
          resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
          bookmarkDataIsStale: &isStale)
        return (url, isStale)
      })
  }

  /// Why a picked folder was not kept; nothing is saved.
  enum Refusal: Error, Equatable {
    /// No `.obsidian` folder in it (owner, 2026-10-28).
    case notAVault
    case bookmarkFailed
  }

  enum Resolved: Equatable, Sendable {
    case notChosen
    /// The bookmark does not resolve, or a stale one cannot be made again.
    case unreadable
    case folder(URL)
  }

  /// What the Settings row shows.
  private(set) var chosen: StoredBookmark?
  private let settings: any AppSettings
  private let bookmarks: Bookmarks
  private let now: () -> Date

  init(
    settings: any AppSettings, bookmarks: Bookmarks = .securityScoped,
    now: @escaping () -> Date = Date.init
  ) {
    self.settings = settings
    self.bookmarks = bookmarks
    self.now = now
    chosen = settings.vaultBookmark
  }

  /// Keeps the folder a picker returned, if it holds `.obsidian`.
  func choose(_ url: URL) throws(Refusal) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard Self.isVault(url) else { throw .notAVault }
    guard let data = try? bookmarks.make(url) else { throw .bookmarkFailed }
    save(StoredBookmark(data: data, name: url.lastPathComponent, savedAt: now()))
  }

  /// The folder for one import. A stale bookmark is made again and saved only if the stored one
  /// is still the one resolved (compare-and-set), keeping the time it was chosen.
  func resolve() -> Resolved {
    guard let stored = settings.vaultBookmark else { return .notChosen }
    guard let resolved = try? bookmarks.resolve(stored.data) else { return .unreadable }
    guard resolved.isStale else { return .folder(resolved.url) }
    let url = resolved.url
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? bookmarks.make(url) else { return .unreadable }
    if settings.vaultBookmark == stored {
      save(StoredBookmark(data: data, name: url.lastPathComponent, savedAt: stored.savedAt))
    }
    return .folder(url)
  }

  private func save(_ bookmark: StoredBookmark) {
    settings.setVaultBookmark(bookmark)
    chosen = bookmark
  }

  /// Whether `url` holds an `.obsidian` folder.
  nonisolated static func isVault(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: url.appending(path: ".obsidian").path(percentEncoded: false),
      isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
  }
}

/// The import's vault (S4-4d): the chosen folder, read through its bookmark. It never throws:
/// a folder that cannot be read is not read, and every stored line, note and artifact stays.
struct BookmarkedVault: NoteProvider {
  let folder: VaultFolder
  var limits = VaultLimits()

  private static let unreadable = VaultSnapshot.notRead(
    issues: [.vaultWide(VaultProblem(.vaultUnreadable))])

  func vault(timeZone: TimeZone) async -> VaultSnapshot {
    switch await folder.resolve() {
    case .notChosen: return .notRead(issues: [.vaultWide(VaultProblem(.vaultNotChosen))])
    case .unreadable: return Self.unreadable
    case .folder(let url):
      // Unsandboxed, the scope may not open; that is no failure (`project.yml`).
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      // A folder a sync emptied or replaced is not an empty vault: nothing is soft-deleted
      // (owner, 2026-11-10).
      guard VaultFolder.isVault(url) else { return Self.unreadable }
      return await ObsidianVault(root: url, timeZone: timeZone, limits: limits)
        .vault(timeZone: timeZone)
    }
  }
}
