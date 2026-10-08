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
    let marked = BudgetNote.marked(in: scan.notes)
    let budget = BudgetNote.status(marked: marked, rejected: scan.rejectedMarks)
    // Only the one marked note that parsed is read; otherwise the lines are unavailable.
    let lines =
      if budget == .found, let note = marked.first { BudgetLines.read(note) } else {
        BudgetLines(lines: .unavailable, issues: [], skipped: 0)
      }
    return VaultRead(
      lines: lines.lines,
      issues: scan.issues + BudgetNote.issues(marked: marked, rejected: scan.rejectedMarks)
        + lines.issues,
      notesFound: scan.noteCount, frontmatterRead: scan.notes.count,
      rejected: Self.count(scan.noteIssues), skipped: Self.count(scan.walkIssues),
      anchorLikeAccepted: scan.anchorLikeAccepted, budget: budget,
      linesSkipped: lines.skipped, lineProblems: Self.count(lines.issues))
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
  /// The budget note, or why there is none.
  public let budget: BudgetNoteStatus
  /// `lines:` items skipped for a missing, invalid or duplicate value.
  public let linesSkipped: Int
  /// Problems in the budget note's `lines:`, by kind.
  public let lineProblems: [VaultProblem.Kind: Int]

  /// Counts only: never a path, a note name or a value from a note. Every kind is listed,
  /// zeros included, so an anchor rejection can never be missed.
  public var report: [String] {
    let rejectedCount = rejected.values.reduce(0, +)
    let rejectedKinds: [VaultProblem.Kind] = [
      .unreadable, .notUTF8, .frontmatterTooLarge, .malformedYAML, .yamlTooComplex, .yamlAnchor,
      .yamlDirective,
    ]
    return [
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
      "budget note: " + budgetLabel,
      "lines: " + linesLabel,
      "line problems: "
        + Self.list(
          lineProblems,
          [.missingKey, .invalidValue, .duplicateLineId].map { ($0, $0.rawValue) }),
      "foundation lines: \(lines.read.count { $0.foundation })"
        + " · with a floor: \(lines.read.count { $0.floorHoursPerDay != nil })"
        + " · with a language: \(lines.read.count { $0.language != nil })",
    ]
  }

  /// Owner only: each problem's kind, vault-relative path and line, never anything from the
  /// note. Paths are owner data: printed in the owner's own terminal, never logged.
  public var problemLocations: [String] {
    issues.compactMap { issue in
      switch issue {
      case .vault(let path, let line, let problem):
        "\(problem.kind.rawValue) \(Self.printable(path))" + (line.map { ":\($0)" } ?? "")
      case .vaultWide(let problem): problem.kind.rawValue
      default: nil
      }
    }
  }

  /// A file name is untrusted: every control and format character (newlines, ESC, bidi
  /// controls) is shown as `\u{…}`, and a backslash as `\\`, so a name cannot rewrite, hide
  /// or forge a printed line.
  static func printable(_ path: String) -> String {
    path.unicodeScalars.map { scalar in
      switch scalar.properties.generalCategory {
      case .control, .format, .lineSeparator, .paragraphSeparator:
        "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
      default: scalar == "\\" ? "\\\\" : String(scalar)
      }
    }.joined()
  }

  private var budgetLabel: String {
    switch budget {
    case .found: "found"
    case .missing: "missing"
    case .rejected(let kind): "rejected (\(kind.rawValue))"
    case .ambiguous(let marked): "\(marked) marked notes"
    }
  }

  private var linesLabel: String {
    lines == .unavailable ? "unavailable" : "\(lines.read.count) read · \(linesSkipped) skipped"
  }

  /// `name count` for each kind in the given order, zeros included.
  private static func list(
    _ counts: [VaultProblem.Kind: Int], _ names: [(VaultProblem.Kind, String)]
  ) -> String {
    names.map { kind, name in "\(name) \(counts[kind, default: 0])" }.joined(separator: " · ")
  }
}
