import Foundation
import MoonShineCore

/// The `artifacts:` lists of year and quarter notes (contract §2.1 and §2.2). A list that is
/// not read in full is named in `unreadLists`, so the note keeps its stored artifacts.
enum VaultArtifacts {
  /// The note types whose `artifacts:` are read; on any other note it is an unknown key.
  static let types = ["year_artifacts", "quarter_focus"]
  /// Items in one note's list (owner, 2026-10-14).
  static let maxItems = 100
  /// Ids in one item's `lines` (owner, 2026-10-10).
  static let maxLines = 20

  struct Result {
    var artifacts: [SourceArtifact] = []
    var issues: [ImportIssue] = []
    /// Notes whose `artifacts:` list was not read in full.
    var unreadLists: Set<String> = []
    /// Items skipped; each duplicate counts.
    var skipped = 0
    /// Artifacts read whose item has no `status`.
    var withoutStatus = 0
    /// Artifacts read, by a name from `types`.
    var byType: [String: Int] = [:]
  }

  /// `notes` are the notes read, in path order; `frontmatter` holds their frontmatter by path.
  static func read(
    _ notes: [SourceNote], frontmatter: [String: FrontNode], calendar: Calendar
  ) -> Result {
    var lists: [List] = []
    var periods: Set<Horizon> = []
    for note in notes {
      guard let type = note.type, types.contains(type), let period = note.period,
        let node = frontmatter[note.path]
      else { continue }
      var list = List(path: note.path, type: type, period: period)
      // Several notes for one period: the first by path wins (contract §2.1).
      if periods.insert(period).inserted {
        list.read(node, periodKey: periodKey(period, calendar))
      } else {
        list.problem(.duplicatePeriodNote, "notes.period", node.line)
      }
      lists.append(list)
    }
    markDuplicates(&lists)
    var result = Result()
    for list in lists {
      result.issues += list.issues + list.items.flatMap(\.fields.issues)
      let read = list.items.compactMap(\.artifact)
      result.artifacts += read
      result.skipped += list.items.count - read.count
      result.withoutStatus += list.items.count { $0.artifact != nil && !$0.hasStatus }
      result.byType[list.type, default: 0] += read.count
      if !list.isComplete || read.count < list.items.count { result.unreadLists.insert(list.path) }
    }
    return result
  }

  /// The same `id` twice in one note, or in two notes whose periods overlap: every such item
  /// is skipped. Items invalid for another reason count too, so every problem shows at once.
  /// Near-linear in the items: the vault is untrusted, so no pair of places is compared.
  private static func markDuplicates(_ lists: inout [List]) {
    var places: [String: [(list: Int, item: Int)]] = [:]
    for (l, list) in lists.enumerated() {
      for (i, item) in list.items.enumerated() {
        if let id = item.id { places[id, default: []].append((l, i)) }
      }
    }
    for found in places.values where found.count > 1 {
      let byList = Dictionary(grouping: found, by: \.list)
      var clashing = Set(byList.filter { $0.value.count > 1 }.keys)
      // By start: a period overlaps an earlier one when the latest end so far is after its
      // start, and a later one exactly when it overlaps the next.
      let ordered = byList.keys.sorted { lists[$0].period.start < lists[$1].period.start }
      var latestEnd: Date?
      for (n, l) in ordered.enumerated() {
        let period = lists[l].period
        if let latestEnd, latestEnd > period.start { clashing.insert(l) }
        if n + 1 < ordered.count, lists[ordered[n + 1]].period.start < period.end {
          clashing.insert(l)
        }
        latestEnd = max(latestEnd ?? period.end, period.end)
      }
      for place in found where clashing.contains(place.list) {
        lists[place.list].markDuplicate(place.item)
      }
    }
  }

  /// `YYYY` for a year, `YYYY-Qn` for a quarter; nil for a period of another scale.
  private static func periodKey(_ period: Horizon, _ calendar: Calendar) -> String? {
    let year = calendar.component(.year, from: period.start)
    switch period.scale {
    case .year: return "\(year)"
    case .quarter: return "\(year)-Q\((calendar.component(.month, from: period.start) - 1) / 3 + 1)"
    default: return nil
    }
  }
}

/// One note's `artifacts:`.
private struct List {
  let path: String
  let type: String
  let period: Horizon
  private(set) var items: [ArtifactItem] = []
  private(set) var issues: [ImportIssue] = []
  /// False when the list itself was not read: not a list, over the cap, a period with no
  /// key, or a note that is not the first for its period.
  private(set) var isComplete = true

  init(path: String, type: String, period: Horizon) {
    self.path = path
    self.type = type
    self.period = period
  }

  mutating func problem(_ kind: VaultProblem.Kind, _ key: String, _ line: Int) {
    issues.append(.vault(path: path, line: line, problem: VaultProblem(kind, key: key)))
    isComplete = false
  }

  /// Absent, null or empty is a clean read with no artifacts.
  mutating func read(_ frontmatter: FrontNode, periodKey: String?) {
    guard let list = frontmatter["artifacts"], list.value != .null else { return }
    guard case .sequence(let nodes) = list.value, nodes.count <= VaultArtifacts.maxItems,
      nodes.isEmpty || periodKey != nil
    else { return problem(.invalidValue, "notes.artifacts", list.line) }
    items = nodes.map { ArtifactItem(path: path, node: $0, periodKey: periodKey ?? "") }
  }

  mutating func markDuplicate(_ index: Int) { items[index].markDuplicate() }
}

/// One `artifacts:` item. Every problem is reported; any missing, invalid or duplicate value
/// skips the item, so the stored artifact stays as it was.
private struct ArtifactItem {
  var fields: Fields
  /// The item's `id` when it passes the id rule, for the duplicate check.
  private(set) var id: String?
  private(set) var artifact: SourceArtifact?
  private(set) var hasStatus = false

  init(path: String, node: FrontNode, periodKey: String) {
    fields = Fields(path: path, node: node, schema: "artifacts")
    artifact = read(periodKey: periodKey)
  }

  mutating func markDuplicate() {
    fields.report(.duplicateArtifactId, "artifacts.id", fields.line(of: "id"))
    artifact = nil
  }

  private mutating func read(periodKey: String) -> SourceArtifact? {
    guard case .mapping = fields.node.value else {
      fields.report(.invalidValue, "notes.artifacts", fields.node.line)
      return nil
    }
    id = fields.required("id", Fields.isID)
    let title = fields.required("title") { Fields.text($0, characters: 200, bytes: 1024) }
    let lineKeys = lineKeys()
    let status = fields.optional("status") { ArtifactStatus(rawValue: $0) != nil }
    hasStatus = status != nil
    let priority = fields.optional("priority") { $0 == "true" || $0 == "false" }
    guard !fields.skip, let id, let title, let lineKeys else { return nil }
    return SourceArtifact(
      key: id, periodKey: periodKey, title: title, lineKeys: lineKeys,
      status: status.flatMap(ArtifactStatus.init) ?? .planned, priority: priority == "true",
      notePath: fields.path)
  }

  /// `line` (one id) or `lines` (at most 20 different ids), not both; neither means none.
  private mutating func lineKeys() -> [LineKey]? {
    switch (fields.present("line"), fields.present("lines")) {
    case (nil, nil): return []
    case (let one?, nil): return fields.checked("line", one, Fields.isID).map { [LineKey($0)] }
    case (let one, let many?):
      let ids = many.sequenceScalars
      guard one == nil, let ids, ids.count <= VaultArtifacts.maxLines,
        ids.allSatisfy(Fields.isID), Set(ids).count == ids.count
      else {
        fields.report(.invalidValue, "artifacts.lines", many.line)
        return nil
      }
      return ids.map { LineKey($0) }
    }
  }
}

extension FrontNode {
  /// The items of a sequence when every one is a scalar; nil otherwise.
  fileprivate var sequenceScalars: [String]? {
    guard case .sequence(let items) = value else { return nil }
    let scalars = items.compactMap(\.scalar)
    return scalars.count == items.count ? scalars : nil
  }
}
