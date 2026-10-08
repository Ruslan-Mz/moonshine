import MoonShineCore

/// Which note is the budget note (contract §1), or why none is.
public enum BudgetNoteStatus: Equatable, Sendable {
  /// Exactly one note carries the marker, and it parsed.
  case found
  /// No note carries the marker.
  case missing
  /// Exactly one note carries the marker, and it was rejected for this kind.
  case rejected(VaultProblem.Kind)
  /// More than one note carries the marker, parsed or not.
  case ambiguous(marked: Int)
}

/// A rejected note whose frontmatter text has a top-level `moonshine: budget` line.
struct RejectedMark: Equatable {
  let path: String
  let line: Int
  let kind: VaultProblem.Kind
}

enum BudgetNote {
  static let markerKey = "moonshine"

  /// Every note with `moonshine: budget` at the top of its frontmatter, in path order. A file
  /// name never marks it: names are owner data.
  static func marked(in notes: [ScannedNote]) -> [ScannedNote] {
    notes.filter { $0.frontmatter[markerKey]?.scalar == "budget" }
  }

  /// The note line of a top-level `moonshine: budget` line in frontmatter text that failed to
  /// parse; quotes around the key or the value and a trailing comment are allowed.
  static func markerLine(in text: String) -> Int? {
    let marker =
      #/(?:moonshine|"moonshine"|'moonshine')[ \t]*:[ \t]+(?:budget|"budget"|'budget')(?:[ \t]+#.*)?[ \t\r]*/#
    // Lines end at LF, as `Frontmatter` reads them; Swift keeps CR LF as one character.
    let lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
    return lines.firstIndex { (try? marker.wholeMatch(in: $0)) != nil }.map { $0 + 2 }
  }

  /// One marked note that parsed is the budget note; one that was rejected leaves the lines
  /// unavailable; more than one, parsed or not, is ambiguous and none wins.
  static func status(marked: [ScannedNote], rejected: [RejectedMark]) -> BudgetNoteStatus {
    switch (marked.count, rejected.first) {
    case (0, nil): .missing
    case (1, nil): .found
    case (0, let mark?) where rejected.count == 1: .rejected(mark.kind)
    default: .ambiguous(marked: marked.count + rejected.count)
    }
  }

  /// `budgetNoteMissing` without a path; `budgetNoteRejected` on the one marked note that was
  /// rejected; `budgetNoteDuplicate` on each marked note when more than one is marked.
  static func issues(marked: [ScannedNote], rejected: [RejectedMark]) -> [ImportIssue] {
    let notes =
      marked.map { ($0.path, $0.frontmatter[markerKey]?.line) }
      + rejected.map { ($0.path, $0.line) }
    switch status(marked: marked, rejected: rejected) {
    case .found: return []
    case .missing: return [.vaultWide(VaultProblem(.budgetNoteMissing))]
    case .rejected: return notes.map { issue(.budgetNoteRejected, path: $0, line: $1) }
    case .ambiguous:
      return notes.sorted { $0.0 < $1.0 }.map { issue(.budgetNoteDuplicate, path: $0, line: $1) }
    }
  }

  private static func issue(_ kind: VaultProblem.Kind, path: String, line: Int?) -> ImportIssue {
    .vault(path: path, line: line, problem: VaultProblem(kind, key: markerKey))
  }
}
