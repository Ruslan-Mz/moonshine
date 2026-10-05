import Foundation
import MoonShineCore

/// The reader's caps. The vault is user data that may be synced or pasted from elsewhere, so
/// each threat has one guard: the note count, the frontmatter size, and YAML nodes and depth.
public struct VaultLimits: Sendable {
  public var maxNotes = 20_000
  public var maxFrontmatterBytes = 64 * 1024
  /// Nodes visited per note, aliases counted at every use; bounds alias expansion.
  public var maxNodes = 10_000
  /// Nesting of YAML collections, checked before parsing for flow style and after it for all.
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
  static func markdownFiles(
    in root: URL, limits: VaultLimits
  ) throws(VaultReadError) -> (files: [VaultFile], issues: [ImportIssue]) {
    let root = root.resolvingSymlinksInPath().standardizedFileURL
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey]
    // A folder the walk cannot enter is an issue, not a silent hole in the vault.
    let unreadable = UnreadablePaths()
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder),
      isFolder.boolValue,
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { url, _ in
          unreadable.paths.append(relativePath(of: url, under: root) ?? "")
          return true
        })
    else { throw .rootUnreadable }

    var files: [VaultFile] = []
    var issues: [ImportIssue] = []
    for case let url as URL in walker {
      guard let path = relativePath(of: url, under: root) else { continue }
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isSymbolicLink == true {
        walker.skipDescendants()
        issues.append(.vault(path: path, line: nil, problem: VaultProblem(.symlinkSkipped)))
        continue
      }
      guard values?.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
      // Defence in depth behind the symlink skip (a link swapped in during the walk).
      guard relativePath(of: url.resolvingSymlinksInPath(), under: root) != nil else {
        issues.append(.vault(path: path, line: nil, problem: VaultProblem(.outsideVault)))
        continue
      }
      guard files.count < limits.maxNotes else { throw .tooManyNotes(limit: limits.maxNotes) }
      files.append(VaultFile(path: path, url: url))
    }
    issues += unreadable.paths.map {
      .vault(path: $0, line: nil, problem: VaultProblem(.unreadable))
    }
    return (files.sorted { $0.path < $1.path }, issues.sorted { "\($0)" < "\($1)" })
  }

  /// Collects what the enumerator's error handler reports; the walk is synchronous.
  private final class UnreadablePaths {
    var paths: [String] = []
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
