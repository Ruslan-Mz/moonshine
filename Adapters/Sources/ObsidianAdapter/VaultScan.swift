import Foundation
import MoonShineCore

/// One note's frontmatter, already bounded. The vault schemas (lines, notes, artifacts) read it.
struct ScannedNote: Equatable {
  let path: String
  let frontmatter: FrontNode
}

enum VaultScan {
  struct Result {
    /// Notes with frontmatter, in path order.
    let notes: [ScannedNote]
    /// Markdown notes the walk found.
    let noteCount: Int
    /// Entries the walk skipped or could not open.
    let walkIssues: [ImportIssue]
    /// Notes whose frontmatter was rejected.
    let noteIssues: [ImportIssue]

    var issues: [ImportIssue] { walkIssues + noteIssues }
  }

  /// Every note under `root` that has frontmatter, in path order. A note that cannot be read
  /// becomes an issue with its relative path and kind; the rest of the vault still loads.
  static func notes(
    in root: URL, limits: VaultLimits = VaultLimits()
  ) throws(VaultReadError) -> Result {
    let (files, walkIssues) = try VaultWalk.markdownFiles(in: root, limits: limits)
    var noteIssues: [ImportIssue] = []
    var notes: [ScannedNote] = []
    for file in files {
      do {
        guard let text = try Frontmatter.text(of: file.url, limit: limits.maxFrontmatterBytes)
        else { continue }
        notes.append(
          ScannedNote(path: file.path, frontmatter: try FrontNode.parse(text, limits: limits)))
      } catch {
        noteIssues.append(
          .vault(path: file.path, line: error.line, problem: VaultProblem(error.kind)))
      }
    }
    return Result(
      notes: notes, noteCount: files.count, walkIssues: walkIssues, noteIssues: noteIssues)
  }
}
