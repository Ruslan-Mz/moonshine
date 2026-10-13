import Foundation
import MoonShineCore

/// The budget note's `lines:` block (contract §1), checked item by item. Any invalid value
/// skips its item, so a stored line is never overwritten with less than it had.
struct BudgetLines: Equatable {
  let lines: VaultLines
  let issues: [ImportIssue]
  /// Line items skipped; each duplicate counts.
  let skipped: Int

  static func read(_ note: ScannedNote) -> BudgetLines {
    let root = note.frontmatter
    guard let list = root["lines"], list.value != .null else {
      return unavailable(note.path, .missingKey, line: root.line)
    }
    // An empty list is more often a broken edit than "no lines": it would remove them all.
    guard case .sequence(let items) = list.value, !items.isEmpty else {
      return unavailable(note.path, .invalidValue, line: list.line)
    }
    let ids = Dictionary(items.compactMap { $0["id"]?.scalar }.map { ($0, 1) }, uniquingKeysWith: +)
    let duplicates = Set(ids.filter { $0.value > 1 }.keys)
    var lines: [SourceLine] = []
    var issues: [ImportIssue] = []
    for node in items {
      var item = Item(path: note.path, node: node)
      if let line = item.line(duplicates: duplicates) { lines.append(line) }
      issues += item.issues
    }
    let skipped = items.count - lines.count
    return BudgetLines(
      lines: .read(lines, complete: skipped == 0), issues: issues, skipped: skipped)
  }

  private static func unavailable(
    _ path: String, _ kind: VaultProblem.Kind, line: Int
  ) -> BudgetLines {
    BudgetLines(
      lines: .unavailable,
      issues: [.vault(path: path, line: line, problem: VaultProblem(kind, key: "lines"))],
      skipped: 0)
  }
}

/// One `lines:` item. Every problem is reported, so the owner can fix them in one pass; any
/// missing, invalid or duplicate value skips the item.
private struct Item {
  var fields: Fields

  init(path: String, node: FrontNode) {
    fields = Fields(path: path, node: node, schema: "lines")
  }

  var issues: [ImportIssue] { fields.issues }

  mutating func line(duplicates: Set<String>) -> SourceLine? {
    guard case .mapping = fields.node.value else {
      fields.report(.invalidValue, "lines", fields.node.line)
      return nil
    }
    let id = fields.required("id", Fields.isID)
    if let id, duplicates.contains(id) {
      fields.report(.duplicateLineId, "lines.id", fields.line(of: "id"))
    }
    let name = fields.required("name") { Fields.text($0, characters: 120, bytes: 1024) }
    let block = fields.required("block") { Fields.text($0, characters: 60, bytes: 512) }
    let state = fields.required("state") { LineState(rawValue: $0) != nil }.flatMap {
      LineState(rawValue: $0)
    }
    let emoji = fields.optional("emoji") { Fields.text($0, characters: 8, bytes: 256) }
    let budget = fields.optional("budget_h_week") { Fields.number($0, max: 168) != nil }
    let parent = fields.optional("parent") { !Fields.hasControl($0) }
    let foundation = fields.optional("foundation") { $0 == "true" || $0 == "false" } == "true"
    let floor = fields.optional("floor_h_day") { Fields.number($0, max: 24) != nil }
    let language = fields.optional("language") {
      $0.utf8.count <= 35 && $0.allSatisfy(\.isASCII) && !Fields.hasControl($0)
        && $0.wholeMatch(of: #/[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*/#) != nil
    }
    let rules = taskRules()
    guard !fields.skip, let id, let name, let block, let state else { return nil }
    return SourceLine(
      key: LineKey(id), name: name, emoji: emoji, block: block, state: state,
      budgetHoursPerWeek: budget.flatMap { Fields.number($0, max: 168) }, parentLink: parent,
      tags: rules.tags, folders: rules.folders, projects: rules.projects,
      foundation: foundation, floorHoursPerDay: floor.flatMap { Fields.number($0, max: 24) },
      language: language)
  }

  /// `omnifocus:`: each list at most 100 names of at most 200 characters and 1 KiB, no control.
  private mutating func taskRules() -> LineTaskRules {
    guard let rules = fields.present("omnifocus") else { return LineTaskRules() }
    guard case .mapping = rules.value else {
      fields.report(.invalidValue, "lines.omnifocus", rules.line)
      return LineTaskRules()
    }
    return LineTaskRules(
      tags: names("tags", in: rules), folders: names("folders", in: rules),
      projects: names("projects", in: rules))
  }

  private mutating func names(_ list: String, in rules: FrontNode) -> [String] {
    guard let node = rules[list], node.value != .null else { return [] }
    guard case .sequence(let items) = node.value, items.count <= 100,
      items.allSatisfy({
        $0.scalar.map { $0.count <= 200 && $0.utf8.count <= 1024 && !Fields.hasControl($0) }
          ?? false
      })
    else {
      fields.report(.invalidValue, "lines.omnifocus.\(list)", node.line)
      return []
    }
    return items.compactMap(\.scalar)
  }
}
