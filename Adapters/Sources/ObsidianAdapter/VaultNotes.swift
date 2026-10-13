import Foundation
import MoonShineCore

/// The notes MoonShine stores (contract §2): the recognised types and the budget note.
enum VaultNotes {
  /// The recognised values of `type`, in the order the live check prints them.
  static let types = [
    "month_plan", "quarter_focus", "year_artifacts", "horizon_corridor", "yearly-goals", "focus",
    "lifetime",
  ]
  /// What the live check calls the budget note, whatever its `type`.
  static let budgetName = "budget note"
  /// Every key a note problem can name, after `notes.`.
  static let keys = [
    "title", "type", "parent", "line", "status", "scale", "period", "month", "quarter", "year",
    "period_start", "period_end",
  ]

  struct Result {
    var notes: [SourceNote] = []
    var issues: [ImportIssue] = []
    /// Notes skipped for an invalid or missing value: they exist and were not read.
    var skipped: Set<String> = []
    /// Notes of another type, or with none.
    var notRecognised: Set<String> = []
    /// Notes read, by a name from `types` or `budgetName`.
    var byType: [String: Int] = [:]
  }

  /// `scanned` in path order, and so are the notes. `budget` holds the paths of the notes
  /// with the budget marker: each is stored as a note, whatever its type.
  static func read(_ scanned: [ScannedNote], budget: Set<String>, calendar: Calendar) -> Result {
    var result = Result()
    for scannedNote in scanned {
      let isBudget = budget.contains(scannedNote.path)
      let type = firstType(of: scannedNote.frontmatter)
      guard isBudget || type.map(types.contains) == true else {
        result.notRecognised.insert(scannedNote.path)
        continue
      }
      var item = NoteItem(note: scannedNote, calendar: calendar)
      if let note = item.note() {
        result.notes.append(note)
        result.byType[isBudget ? budgetName : type ?? "", default: 0] += 1
      } else {
        result.skipped.insert(scannedNote.path)
      }
      result.issues += item.fields.issues
    }
    return result
  }

  /// The first item of `type`, which may be a comma list (`"month_plan, journal"`).
  static func firstType(of frontmatter: FrontNode) -> String? {
    frontmatter["type"]?.scalar.map(firstItem)
  }

  static func firstItem(_ list: String) -> String {
    let first = list.split(separator: ",", omittingEmptySubsequences: false).first ?? ""
    return first.trimmingCharacters(in: .whitespaces)
  }
}

/// One note's fields. Every problem is reported; any invalid value skips the note, so the
/// stored note stays as it was.
private struct NoteItem {
  var fields: Fields
  let calendar: Calendar

  init(note: ScannedNote, calendar: Calendar) {
    fields = Fields(path: note.path, node: note.frontmatter, schema: "notes")
    self.calendar = calendar
  }

  /// The file name without its `.md`, in any case.
  private var fileName: String {
    String((fields.path.split(separator: "/").last ?? "").dropLast(3))
  }

  mutating func note() -> SourceNote? {
    let title = title()
    // The budget note may have any type; a recognised one always passes these caps.
    let type = fields.optional("type") {
      let type = VaultNotes.firstItem($0)
      return type.count <= 60 && type.utf8.count <= 512 && !Fields.hasControl(type)
    }.map(VaultNotes.firstItem)
    let parent = fields.optional("parent") { $0.utf8.count <= 1024 && !Fields.hasControl($0) }
    let line = fields.optional("line", Fields.isID)
    let status = fields.optional("status") { Fields.text($0, characters: 60, bytes: 512) }
    let span = span(type: type)
    guard !fields.skip, let title else { return nil }
    return SourceNote(
      path: fields.path, title: title, type: type.flatMap { $0.isEmpty ? nil : $0 },
      scale: span.scale, period: span.period, parentLink: parent,
      lineKey: line.map { LineKey($0) }, status: status)
  }

  /// `title`, or the file name when it is absent; a file name over the caps skips the note.
  private mutating func title() -> String? {
    let valid = { Fields.text($0, characters: 200, bytes: 1024) }
    guard fields.present("title") == nil else { return fields.optional("title", valid) }
    guard valid(fileName) else {
      fields.report(.invalidValue, "notes.title", fields.node.line)
      return nil
    }
    return fileName
  }

  // MARK: Scale and period (contract §2)

  private typealias Span = (scale: Scale?, period: Horizon?)

  /// The period, explicit or derived from the type's own keys, and its scale. An explicit
  /// `scale` is only checked against that scale: `years` has no count of its own to store.
  private mutating func span(type: String?) -> Span {
    let words = ["week", "month", "quarter", "year", "years", "lifetime"]
    let written = fields.optional("scale") { words.contains($0) }
    let span = fields.present("period").map { explicit($0) } ?? derived(type: type)
    if let written, let scale = span.scale, written != Self.word(scale) {
      fields.report(.invalidValue, "notes.scale", fields.line(of: "scale"))
    }
    return span
  }

  private static func word(_ scale: Scale) -> String {
    switch scale {
    case .day: "day"
    case .week: "week"
    case .month: "month"
    case .quarter: "quarter"
    case .year: "year"
    case .years: "years"
    case .lifetime: "lifetime"
    }
  }

  /// `period`: a week, month, quarter or year, a range of years (`2026..2030`), or a list of
  /// target years (`2036,2041`), which gives no scale and no period until the Zoom out phase.
  private mutating func explicit(_ node: FrontNode) -> Span {
    let text = node.scalar ?? ""
    let calendar = calendar
    let years = { (parts: [String]) in parts.map { Self.date($0, [.year], calendar) } }
    let range = years(text.components(separatedBy: ".."))
    if range.count == 2, let first = range[0], let last = range[1],
      let span = self.years(from: first, to: last)
    {
      return span
    }
    let list = years(
      text.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
      })
    if list.count > 1, !list.contains(nil) { return (nil, nil) }
    if let one = Self.date(text, [.week, .month, .quarter, .year], calendar) {
      return self.span(one)
    }
    fields.report(.invalidValue, "notes.period", node.line)
    return (nil, nil)
  }

  private mutating func derived(type: String?) -> Span {
    switch type {
    case "month_plan":
      return required(.month, [("month", [.month]), ("period_start", [.day, .month])])
    case "quarter_focus":
      return required(.quarter, [("quarter", [.quarter]), ("period_start", [.day, .month])])
    case "year_artifacts": return required(.year, [("year", [.year])])
    case "yearly-goals": return legacyYear(reportsMissing: true)
    // A `focus` note without a year is the current one, by design (owner, 2026-10-13).
    case "focus": return legacyYear(reportsMissing: false)
    case "horizon_corridor": return corridor()
    case "lifetime": return (.lifetime, nil)
    // The budget note of another type.
    default: return (nil, nil)
    }
  }

  /// The period from the first source key that is present; a later key is not read. Nil when
  /// none is present; a key in another shape is reported and gives no period.
  private mutating func first(
    _ scale: Scale, _ sources: [(key: String, shapes: [WrittenDate.Shape])]
  ) -> Span? {
    for source in sources {
      guard let node = fields.present(source.key) else { continue }
      guard let written = keyed(source.key, node, source.shapes),
        let period = Horizon.containing(written.start, scale: scale, calendar: calendar)
      else { return (nil, nil) }
      return (scale, period)
    }
    return nil
  }

  /// A month, quarter or year note cannot be placed without its period: it is skipped.
  private mutating func required(
    _ scale: Scale, _ sources: [(key: String, shapes: [WrittenDate.Shape])]
  ) -> Span {
    if let span = first(scale, sources) { return span }
    fields.report(.missingKey, "notes.period", fields.node.line)
    return (nil, nil)
  }

  /// `year`, else the first run of exactly four digits in the file name that is a year in
  /// range. With neither the note is read with its scale alone; `reportsMissing` says whether
  /// that is a problem.
  private mutating func legacyYear(reportsMissing: Bool) -> Span {
    if let span = first(.year, [("year", [.year])]) { return span }
    let calendar = calendar
    let runs = fileName.split { !("0"..."9").contains($0) }
    if let year = runs.compactMap({ Self.date(String($0), [.year], calendar) }).first {
      return span(year)
    }
    if reportsMissing {
      fields.report(.missingKey, "notes.period", fields.node.line, skips: false)
    }
    return (.year, nil)
  }

  /// `period_start` and `period_end`, each a year, a month or a day. Without both the note is
  /// read with no scale and no period: no problem with `horizons`, `missingKey` without it.
  private mutating func corridor() -> Span {
    let shapes: [WrittenDate.Shape] = [.year, .month, .day]
    let start = fields.present("period_start")
    let end = fields.present("period_end")
    let first = start.flatMap { keyed("period_start", $0, shapes) }
    let last = end.flatMap { keyed("period_end", $0, shapes) }
    switch (start, end) {
    case (nil, nil):
      if fields.present("horizons") == nil {
        fields.report(.missingKey, "notes.period", fields.node.line, skips: false)
      }
    case (_?, nil):
      fields.report(.missingKey, "notes.period_end", fields.node.line, skips: false)
    case (nil, _?):
      fields.report(.missingKey, "notes.period_start", fields.node.line, skips: false)
    case (_?, let end?):
      guard let first, let last else { break }
      if let span = years(from: first, to: last) { return span }
      fields.report(.invalidValue, "notes.period_end", end.line)
    }
    return (nil, nil)
  }

  /// From the start of `first` to the end of `last`, counted in calendar years; nil when the
  /// end is not after the start or the range is over 200 years.
  private func years(from first: WrittenDate, to last: WrittenDate) -> Span? {
    let count = last.year - first.year + 1
    guard first.start < last.end, (1...200).contains(count) else { return nil }
    return (.years(count), Horizon(scale: .years(count), start: first.start, end: last.end))
  }

  private func span(_ written: WrittenDate) -> Span {
    let scale: Scale =
      switch written.shape {
      case .year: .year
      case .month: .month
      case .day: .day
      case .week: .week
      case .quarter: .quarter
      }
    return (scale, Horizon(scale: scale, start: written.start, end: written.end))
  }

  /// `text` as a date in one of `shapes`.
  private static func date(
    _ text: String, _ shapes: [WrittenDate.Shape], _ calendar: Calendar
  ) -> WrittenDate? {
    WrittenDate.parse(text, calendar: calendar).flatMap { shapes.contains($0.shape) ? $0 : nil }
  }

  /// The value of a source key as a date in one of `shapes`; anything else is `invalidValue`.
  private mutating func keyed(
    _ key: String, _ node: FrontNode, _ shapes: [WrittenDate.Shape]
  ) -> WrittenDate? {
    guard let written = node.scalar.flatMap({ Self.date($0, shapes, calendar) }) else {
      fields.report(.invalidValue, "notes.\(key)", node.line)
      return nil
    }
    return written
  }
}
