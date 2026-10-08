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

/// One `lines:` item. Every problem is reported, so the owner can fix them in one pass; a
/// missing, invalid or duplicate value skips the item, an ignored one does not.
private struct Item {
  let path: String
  let node: FrontNode
  private(set) var issues: [ImportIssue] = []
  private var skip = false

  init(path: String, node: FrontNode) {
    self.path = path
    self.node = node
  }

  mutating func line(duplicates: Set<String>) -> SourceLine? {
    guard case .mapping = node.value else {
      report(.invalidValue, "lines", node.line)
      return nil
    }
    let id = required("id") {
      (1...64).contains($0.utf8.count) && $0.utf8.allSatisfy(Self.isSlug)
    }
    if let id, duplicates.contains(id) { report(.duplicateLineId, "lines.id", line(of: "id")) }
    let name = required("name") { !$0.isEmpty && $0.count <= 120 }
    let block = required("block") { !$0.isEmpty && $0.count <= 60 }
    let state = required("state") { LineState(rawValue: $0) != nil }.flatMap {
      LineState(rawValue: $0)
    }
    let emoji = optional("emoji") { !$0.isEmpty && $0.count <= 8 }
    let budget = optional("budget_h_week") { Self.number($0, max: 168) != nil }
    let parent = optional("parent") { _ in true }
    let foundation = optional("foundation") { $0 == "true" || $0 == "false" } == "true"
    var floor = optional("floor_h_day") { Self.number($0, max: 24) != nil }
    if floor != nil, !foundation {
      report(.keyIgnored, "lines.floor_h_day", line(of: "floor_h_day"), skips: false)
      floor = nil
    }
    let language = optional("language") {
      $0.utf8.count <= 35 && $0.allSatisfy(\.isASCII)
        && $0.wholeMatch(of: #/[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*/#) != nil
    }
    let rules = taskRules()
    guard !skip, let id, let name, let block, let state else { return nil }
    return SourceLine(
      key: LineKey(id), name: name, emoji: emoji, block: block, state: state,
      budgetHoursPerWeek: budget.flatMap { Self.number($0, max: 168) }, parentLink: parent,
      tags: rules.tags, folders: rules.folders, projects: rules.projects,
      foundation: foundation, floorHoursPerDay: floor.flatMap { Self.number($0, max: 24) },
      language: language)
  }

  /// A plain decimal from 0 to `max`: no sign, exponent, hex, `nan`, `inf` or decimal comma.
  private static func number(_ text: String, max: Double) -> Double? {
    guard text.allSatisfy(\.isASCII), text.wholeMatch(of: #/[0-9]+(\.[0-9]+)?/#) != nil,
      let value = Double(text),
      value <= max
    else { return nil }
    return value
  }

  /// `[a-z0-9-]`, byte by byte: a Character range would let a decomposed `á` through.
  private static func isSlug(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-")
  }

  /// `omnifocus:`: each list at most 100 names of at most 200 characters.
  private mutating func taskRules() -> LineTaskRules {
    guard let rules = present("omnifocus") else { return LineTaskRules() }
    guard case .mapping = rules.value else {
      report(.invalidValue, "lines.omnifocus", rules.line)
      return LineTaskRules()
    }
    return LineTaskRules(
      tags: names("tags", in: rules), folders: names("folders", in: rules),
      projects: names("projects", in: rules))
  }

  private mutating func names(_ list: String, in rules: FrontNode) -> [String] {
    guard let node = rules[list], node.value != .null else { return [] }
    guard case .sequence(let items) = node.value, items.count <= 100,
      items.allSatisfy({ $0.scalar.map { $0.count <= 200 } ?? false })
    else {
      report(.invalidValue, "lines.omnifocus.\(list)", node.line)
      return []
    }
    return items.compactMap(\.scalar)
  }

  private func line(of key: String) -> Int { node[key]?.line ?? node.line }

  /// The value of `key`; nil when absent or null.
  private func present(_ key: String) -> FrontNode? {
    guard let child = node[key], child.value != .null else { return nil }
    return child
  }

  private mutating func required(_ key: String, _ valid: (String) -> Bool) -> String? {
    guard let child = present(key) else {
      report(.missingKey, "lines.\(key)", node.line)
      return nil
    }
    return checked(key, child, valid)
  }

  private mutating func optional(_ key: String, _ valid: (String) -> Bool) -> String? {
    present(key).flatMap { checked(key, $0, valid) }
  }

  private mutating func checked(
    _ key: String, _ child: FrontNode, _ valid: (String) -> Bool
  ) -> String? {
    guard let text = child.scalar, valid(text) else {
      report(.invalidValue, "lines.\(key)", child.line)
      return nil
    }
    return text
  }

  private mutating func report(
    _ kind: VaultProblem.Kind, _ key: String, _ line: Int, skips: Bool = true
  ) {
    issues.append(.vault(path: path, line: line, problem: VaultProblem(kind, key: key)))
    if skips { skip = true }
  }
}
