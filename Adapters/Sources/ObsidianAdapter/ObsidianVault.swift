import Foundation
import MoonShineCore

/// Reads an Obsidian vault folder as the vault contract describes. It only reads: nothing is
/// written to the vault or anywhere else.
public struct ObsidianVault: Sendable {
  public let root: URL
  public let limits: VaultLimits

  public init(root: URL, limits: VaultLimits = VaultLimits()) {
    self.root = root
    self.limits = limits
  }

  public func read() throws(VaultReadError) -> VaultRead {
    let scan = try VaultScan.notes(in: root, limits: limits)
    let budget = BudgetNote.marked(in: scan.notes)
    // `lines:` is read from S3b-2b on; until then the lines are unavailable, never empty.
    return VaultRead(
      lines: .unavailable, issues: scan.issues + BudgetNote.issues(for: budget),
      notesFound: scan.noteCount, frontmatterRead: scan.notes.count,
      rejected: Self.count(scan.noteIssues), skipped: Self.count(scan.walkIssues),
      anchorLikeAccepted: scan.anchorLikeAccepted, budgetNotes: budget.count)
  }

  private static func count(_ issues: [ImportIssue]) -> [VaultProblem.Kind: Int] {
    issues.reduce(into: [:]) { counts, issue in
      if case .vault(_, _, let problem) = issue { counts[problem.kind, default: 0] += 1 }
    }
  }
}

/// One read of the vault: what an import takes, and the counts the live check prints.
public struct VaultRead: Sendable {
  public let lines: VaultLines
  public let issues: [ImportIssue]
  /// Markdown notes the walk found, including those later rejected or unreadable; hidden
  /// folders, symbolic links and files outside the vault are not counted.
  public let notesFound: Int
  /// Notes whose frontmatter was read and parsed; notes without frontmatter and rejected
  /// notes are not counted.
  public let frontmatterRead: Int
  /// Notes rejected while reading their frontmatter, by problem.
  public let rejected: [VaultProblem.Kind: Int]
  /// Entries the walk skipped or could not open, by problem.
  public let skipped: [VaultProblem.Kind: Int]
  /// Notes accepted although their frontmatter has anchor-like text: an `&` that may start an
  /// anchor, with no alias to use it.
  public let anchorLikeAccepted: Int
  /// Notes with `moonshine: budget`; the first by path is the budget note.
  public let budgetNotes: Int

  /// Counts only: never a path, a note name or a value from a note. Every kind is listed,
  /// zeros included, so an anchor rejection can never be missed.
  public var report: [String] {
    let rejectedCount = rejected.values.reduce(0, +)
    let rejectedKinds: [VaultProblem.Kind] = [
      .unreadable, .notUTF8, .frontmatterTooLarge, .malformedYAML, .yamlTooComplex, .yamlAnchor,
      .yamlDirective,
    ]
    var lines = [
      "vault: \(notesFound) notes found · \(frontmatterRead) frontmatter read",
      "rejected notes: \(rejectedCount) ("
        + Self.list(rejected, rejectedKinds.map { ($0, $0.rawValue) }) + ")",
      "notes rejected for an anchor: \(rejected[.yamlAnchor, default: 0])",
      "notes with anchor-like text and no alias, accepted: \(anchorLikeAccepted)",
      "skipped: "
        + Self.list(
          skipped,
          [
            (.symlinkSkipped, "symlinks"), (.outsideVault, "outside vault"),
            (.unreadable, "unreadable entries"),
          ]),
      "budget note: "
        + (budgetNotes == 0
          ? "missing" : budgetNotes == 1 ? "found" : "\(budgetNotes) found, first by path used"),
    ]
    if budgetNotes == 0 && rejectedCount > 0 {
      lines.append("the budget note may be among the rejected notes")
    }
    return lines
  }

  /// `name count` for each kind in the given order, zeros included.
  private static func list(
    _ counts: [VaultProblem.Kind: Int], _ names: [(VaultProblem.Kind, String)]
  ) -> String {
    names.map { kind, name in "\(name) \(counts[kind, default: 0])" }.joined(separator: " · ")
  }
}
