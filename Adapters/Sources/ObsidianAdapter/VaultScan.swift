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
    /// Accepted notes whose frontmatter has anchor-like text (and so no alias).
    let anchorLikeAccepted: Int
    /// Rejected notes whose frontmatter text has the budget-note marker.
    let rejectedMarks: [RejectedMark]
    /// Paths that exist and were not read: what the walk skipped, and rejected notes.
    let unread: Set<String>
    /// Paths of notes without frontmatter.
    let withoutFrontmatter: Set<String>

    var issues: [ImportIssue] { walkIssues + noteIssues }
  }

  /// Every note under `root` that has frontmatter, in path order. A note that cannot be read
  /// becomes an issue with its relative path and kind; the rest of the vault still loads.
  static func notes(
    in root: URL, limits: VaultLimits = VaultLimits()
  ) throws(VaultReadError) -> Result {
    let (files, walkIssues, skipped) = try VaultWalk.markdownFiles(in: root, limits: limits)
    var unread = skipped
    var withoutFrontmatter: Set<String> = []
    var noteIssues: [ImportIssue] = []
    var notes: [ScannedNote] = []
    var anchorLikeAccepted = 0
    var rejectedMarks: [RejectedMark] = []
    for file in files {
      let text: String
      do {
        guard let read = try Frontmatter.text(of: file.url, limit: limits.maxFrontmatterBytes)
        else {
          withoutFrontmatter.insert(file.path)
          continue
        }
        text = read
      } catch {
        // No text to search: a budget note rejected here is reported as missing.
        noteIssues.append(
          .vault(path: file.path, line: error.line, problem: VaultProblem(error.kind)))
        unread.insert(file.path)
        continue
      }
      do {
        notes.append(
          ScannedNote(path: file.path, frontmatter: try FrontNode.parse(text, limits: limits)))
        if FrontNode.hasAnchor(text) { anchorLikeAccepted += 1 }
      } catch {
        noteIssues.append(
          .vault(path: file.path, line: error.line, problem: VaultProblem(error.kind)))
        unread.insert(file.path)
        if let line = BudgetNote.markerLine(in: text) {
          rejectedMarks.append(RejectedMark(path: file.path, line: line, kind: error.kind))
        }
      }
    }
    return Result(
      notes: notes, noteCount: files.count, walkIssues: walkIssues, noteIssues: noteIssues,
      anchorLikeAccepted: anchorLikeAccepted, rejectedMarks: rejectedMarks, unread: unread,
      withoutFrontmatter: withoutFrontmatter)
  }
}
