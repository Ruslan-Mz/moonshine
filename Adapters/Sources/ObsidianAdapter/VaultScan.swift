import Foundation
import MoonShineCore

/// One note's frontmatter, already bounded. The vault schemas (lines, notes, artifacts) read it.
struct ScannedNote: Equatable {
  let path: String
  let frontmatter: FrontNode
}

enum VaultScan {
  /// Every note under `root` that has frontmatter, in path order. A note that cannot be read
  /// becomes an issue with its relative path and kind; the rest of the vault still loads.
  static func notes(
    in root: URL, limits: VaultLimits = VaultLimits()
  ) throws(VaultReadError) -> (notes: [ScannedNote], issues: [ImportIssue]) {
    let (files, walkIssues) = try VaultWalk.markdownFiles(in: root, limits: limits)
    var issues = walkIssues
    var notes: [ScannedNote] = []
    for file in files {
      do {
        guard let text = try Frontmatter.text(of: file.url, limit: limits.maxFrontmatterBytes)
        else { continue }
        notes.append(
          ScannedNote(path: file.path, frontmatter: try FrontNode.parse(text, limits: limits)))
      } catch {
        issues.append(.vault(path: file.path, line: error.line, problem: VaultProblem(error.kind)))
      }
    }
    return (notes, issues)
  }
}
