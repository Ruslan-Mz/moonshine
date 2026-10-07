import MoonShineCore

enum BudgetNote {
  static let markerKey = "moonshine"

  /// Every note with `moonshine: budget` at the top of its frontmatter, in path order; the
  /// first is the budget note (contract §1). A file name never marks it: names are owner data.
  static func marked(in notes: [ScannedNote]) -> [ScannedNote] {
    notes.filter { $0.frontmatter[markerKey]?.scalar == "budget" }
  }

  /// `budgetNoteMissing` without a path, or `budgetNoteDuplicate` on each note after the first.
  static func issues(for marked: [ScannedNote]) -> [ImportIssue] {
    guard !marked.isEmpty else { return [.vaultWide(VaultProblem(.budgetNoteMissing))] }
    return marked.dropFirst().map { note in
      .vault(
        path: note.path, line: note.frontmatter[markerKey]?.line,
        problem: VaultProblem(.budgetNoteDuplicate, key: markerKey))
    }
  }
}
