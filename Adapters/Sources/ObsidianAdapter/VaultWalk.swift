import Foundation
import MoonShineCore

/// The reader's caps. The vault is user data that may be synced or pasted from elsewhere, so
/// each threat has one guard: the note count, the frontmatter size, and YAML nodes and depth.
public struct VaultLimits: Sendable {
  public var maxNotes = 20_000
  public var maxFrontmatterBytes = 64 * 1024
  /// Nodes per note after parsing; bounds document size. Expansion is prevented earlier: an
  /// anchor together with an alias, and any directive, are rejected before Yams parses
  /// (`FrontNode.preParseFailure`, contract §3).
  public var maxNodes = 10_000
  /// Nesting of YAML collections, bounded before parsing for block and flow style together
  /// (S4-4d) and checked after it for all.
  public var maxDepth = 32

  public init() {}
}

/// Fatal for a whole read: nothing from the vault is imported.
public enum VaultReadError: Error, Equatable, Sendable {
  case rootUnreadable
  case tooManyNotes(limit: Int)
}

/// A markdown note under the vault root; `path` is vault-relative.
struct VaultFile: Equatable {
  let path: String
  let url: URL
}

enum VaultWalk {
  /// Every `.md` file under `root` in path order, skipping hidden entries and symbolic links.
  /// `unread` names every entry that was skipped or could not be entered: it exists, and
  /// nothing under it was read.
  static func markdownFiles(
    in root: URL, limits: VaultLimits
  ) throws(VaultReadError) -> (files: [VaultFile], issues: [ImportIssue], unread: Set<String>) {
    let root = root.resolvingSymlinksInPath().standardizedFileURL
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey]
    // A folder the walk cannot enter is an issue, not a silent hole in the vault; the root
    // itself (permissions, macOS privacy protection) fails the whole read.
    let unreadable = UnreadablePaths()
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder),
      isFolder.boolValue,
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { url, _ in
          if let path = relativePath(of: url, under: root) {
            unreadable.paths.append(path)
          } else {
            unreadable.root = true
          }
          return true
        })
    else { throw .rootUnreadable }

    var files: [VaultFile] = []
    var issues: [ImportIssue] = []
    var unread: Set<String> = []
    for case let url as URL in walker {
      guard let path = relativePath(of: url, under: root) else { continue }
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isSymbolicLink == true {
        walker.skipDescendants()
        issues.append(.vault(path: path, line: nil, problem: VaultProblem(.symlinkSkipped)))
        unread.insert(path)
        continue
      }
      guard values?.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
      // Defence in depth behind the symlink skip (a link swapped in during the walk).
      guard relativePath(of: url.resolvingSymlinksInPath(), under: root) != nil else {
        issues.append(.vault(path: path, line: nil, problem: VaultProblem(.outsideVault)))
        unread.insert(path)
        continue
      }
      guard files.count < limits.maxNotes else { throw .tooManyNotes(limit: limits.maxNotes) }
      files.append(VaultFile(path: path, url: url))
    }
    guard !unreadable.root else { throw .rootUnreadable }
    issues += unreadable.paths.map {
      .vault(path: $0, line: nil, problem: VaultProblem(.unreadable))
    }
    unread.formUnion(unreadable.paths)
    return (files.sorted { $0.path < $1.path }, issues.sorted { "\($0)" < "\($1)" }, unread)
  }

  /// Collects what the enumerator's error handler reports; the walk is synchronous.
  private final class UnreadablePaths {
    var paths: [String] = []
    var root = false
  }

  /// The path of `url` relative to `root`, or nil when it is not inside `root`.
  static func relativePath(of url: URL, under root: URL) -> String? {
    let base = root.standardizedFileURL.path
    let prefix = base.hasSuffix("/") ? base : base + "/"
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
    return String(path.dropFirst(prefix.count))
  }
}
