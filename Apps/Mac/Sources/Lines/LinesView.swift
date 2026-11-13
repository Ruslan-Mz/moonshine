import MoonShineCore
import SwiftUI

/// One row of the Lines table: a line, or the paused tier's disclosure row.
enum LinesTableRow: Identifiable, Hashable {
  case line(LinesScreen.Row)
  case paused(count: Int)

  enum ID: Hashable {
    case line(LineID)
    case paused
  }

  var id: ID {
    switch self {
    case .line(let row): .line(row.id)
    case .paused: .paused
    }
  }
}

/// Column widths (`design/screens/lines.md` § What S4-2 builds) as ideals. On a narrow window
/// the Line and Last activity columns give way first; the sparkline keeps its width.
enum LinesColumns {
  static let lineMinimum: CGFloat = 150
  static let lineIdeal: CGFloat = 214
  static let stateMinimum: CGFloat = 96
  static let stateIdeal: CGFloat = 112
  static let budgetMinimum: CGFloat = 110
  static let budgetIdeal: CGFloat = 124
  static let sparkline: CGFloat = 176
  static let lastMinimum: CGFloat = 130
  static let lastIdeal: CGFloat = 150
  static let nextMinimum: CGFloat = 64
  static let nextIdeal: CGFloat = 76
  static let estimatedMinimum: CGFloat = 110
  /// The inset table style's side margins and the spacing between seven columns.
  static let margins: CGFloat = 56

  /// The narrowest Lines: every column at its minimum.
  static var minimumWidth: CGFloat {
    lineMinimum + stateMinimum + budgetMinimum + sparkline + lastMinimum + nextMinimum
      + estimatedMinimum + margins
  }
}

/// Lines in the detail column, from the store's overview.
struct LinesDetail: View {
  let overview: Overview

  var body: some View { LinesView(screen: LinesScreen(overview)) }
}

/// `design/screens/lines.md`, draft-5 for S4-2a: tiers, the eight-week sparkline and the
/// week's facts. Line detail and ↵ come with S4-2b.
struct LinesView: View {
  let screen: LinesScreen
  @SceneStorage("lines.pausedExpanded") private var pausedExpanded = false
  @State private var selection: LinesTableRow.ID?
  @FocusState private var listFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      legend
      Divider()
      table
    }
    .frame(minWidth: LinesColumns.minimumWidth)
    .navigationTitle("Lines")
    .navigationSubtitle(Self.joined(screen.counts.map(Self.count)))
  }

  private var legend: some View {
    HStack(spacing: 16) {
      Swatch(color: Tokens.rhythm, text: Text("Rhythm — repeated sessions per week"))
      Swatch(color: Tokens.progress, text: Text("Progress — one-off tasks done per week"))
      Text("current week, partial")
      Spacer()
      if let first = screen.weeks.first, let last = screen.weeks.last {
        Text("Weeks \(first)–\(last)")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
  }

  private var table: some View {
    Table(of: LinesTableRow.self, selection: $selection) {
      TableColumn("Line") { row in
        switch row {
        case .line(let line): LineCell(row: line)
        case .paused(let count):
          Text("Not in focus — on purpose (\(count))").fontWeight(.semibold)
        }
      }
      .width(min: LinesColumns.lineMinimum, ideal: LinesColumns.lineIdeal)
      TableColumn("State") { row in
        if case .line(let line) = row { StateLabel(row: line) }
      }
      .width(min: LinesColumns.stateMinimum, ideal: LinesColumns.stateIdeal)
      TableColumn("Budget") { row in
        if case .line(let line) = row { BudgetText(budget: line.budget).dimmed(line) }
      }
      .width(min: LinesColumns.budgetMinimum, ideal: LinesColumns.budgetIdeal)
      TableColumn("Last 8 weeks") { row in
        if case .line(let line) = row { Sparkline(points: line.sparkline) }
      }
      .width(LinesColumns.sparkline)
      TableColumn("Last activity") { row in
        if case .line(let line) = row {
          LastActivityText(last: line.last, today: screen.today, timeZone: screen.timeZone)
            .dimmed(line)
        }
      }
      .width(min: LinesColumns.lastMinimum, ideal: LinesColumns.lastIdeal)
      TableColumn("Next actions") { row in
        if case .line(let line) = row {
          Text(line.nextActions, format: .number).monospacedDigit().dimmed(line)
        }
      }
      .width(min: LinesColumns.nextMinimum, ideal: LinesColumns.nextIdeal)
      TableColumn("Estimated this week") { row in
        if case .line(let line) = row {
          Group {
            if let estimate = TodayFormat.estimate(line.estimateMinutes) {
              EstimateText.text(estimate, total: true)
            } else {
              Text(verbatim: "—")
            }
          }
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
      }
      .width(min: LinesColumns.estimatedMinimum)
    } rows: {
      ForEach(screen.tiers) { tier in
        if tier.kind == .paused {
          DisclosureTableRow(
            LinesTableRow.paused(count: tier.rows.count), isExpanded: $pausedExpanded
          ) {
            ForEach(tier.rows) { TableRow(LinesTableRow.line($0)) }
          }
        } else {
          Section {
            ForEach(tier.rows) { TableRow(LinesTableRow.line($0)) }
          } header: {
            Self.joined(Self.header(tier))
          }
        }
      }
    }
    .tableStyle(.inset)
    .alternatingRowBackgrounds(.disabled)
    .focused($listFocused)
    .defaultFocus($listFocused, true)
    .onChange(of: selection) { _, selected in
      if selected != nil { listFocused = true }
    }
  }

  /// `Foundation · 2 lines · floor 4 h/day`, `Active this season · 7 lines · 22 h / week`.
  private static func header(_ tier: LinesScreen.Tier) -> [Text] {
    var parts: [Text] = []
    switch tier.kind {
    case .foundation: parts.append(Text("Foundation"))
    case .active: parts.append(Text("Active this season"))
    case .maintenance: parts.append(Text("Maintenance"))
    case .paused: parts.append(Text("Not in focus — on purpose"))
    }
    parts.append(Text("\(tier.rows.count) lines").fontWeight(.regular))
    if let floor = tier.floor {
      parts.append(BudgetText.floor(floor).fontWeight(.regular))
    } else if let hours = tier.weeklyBudgetHours {
      parts.append(BudgetText.weekly(hours).fontWeight(.regular))
    }
    return parts
  }

  private static func count(_ count: LinesScreen.Count) -> Text {
    switch count {
    case .lines(let n): Text("\(n) lines")
    case .foundation(let n): Text("\(n) foundation")
    case .active(let n): Text("\(n) active")
    case .maintenance(let n): Text("\(n) maintenance")
    case .paused(let n): Text("\(n) paused")
    }
  }

  /// The parts with ` · ` between them, in the catalog's `%@ · %@`.
  private static func joined(_ parts: [Text]) -> Text {
    guard let first = parts.first else { return Text(verbatim: "") }
    return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
  }
}

private struct Swatch: View {
  let color: Color
  let text: Text

  var body: some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
      text
    }
  }
}

/// Emoji and name over the block; a held line also says it is no longer in the budget note.
private struct LineCell: View {
  let row: LinesScreen.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 4) {
        if let emoji = row.emoji {
          Text(verbatim: emoji).opacity(row.state == .paused ? 0.5 : 1)
        }
        Text(verbatim: row.name).fontWeight(.semibold).lineLimit(1)
      }
      Text(verbatim: row.block).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
      if row.isHeld {
        Text("not in the budget note").font(.caption).foregroundStyle(.secondary)
      }
    }
    .dimmed(row)
  }
}

/// `design/components.md` § LineStateLabel.
private struct StateLabel: View {
  let row: LinesScreen.Row

  var body: some View {
    switch row.state {
    case .paused:
      Label("paused on purpose", systemImage: "pause").foregroundStyle(Tokens.paused)
    case _ where row.isFoundation: Text("foundation")
    case .active:
      Text("active").foregroundStyle(
        row.isStateSecondary ? HierarchicalShapeStyle.secondary : .primary)
    case .maintenance: Text("maintenance").foregroundStyle(.secondary)
    }
  }
}

/// `design/components.md` § BudgetCell (draft-5).
struct BudgetText: View {
  let budget: LinesFormat.Budget

  var body: some View {
    switch budget {
    case .weekly(let hours): Self.weekly(hours).monospacedDigit()
    case .floor(let floor): Self.floor(floor).monospacedDigit()
    case .weeklyOverFloor(let hours, let floor):
      VStack(alignment: .leading, spacing: 1) {
        Self.weekly(hours)
        Self.floor(floor).font(.caption).foregroundStyle(.secondary)
      }
      .monospacedDigit()
    case .none: Text(verbatim: "—").foregroundStyle(.secondary)
    }
  }

  static func weekly(_ hours: Double) -> Text {
    Text("\(hours, format: LinesFormat.hours) h / week")
  }

  static func floor(_ floor: LinesFormat.Floor) -> Text {
    switch floor {
    case .minutes(let minutes): Text("floor \(minutes) min/day")
    case .hours(let hours):
      Text("floor \(hours, format: LinesFormat.hours) h/day")
    }
  }
}

/// `today`, `yesterday`, `N days ago`, moon + `quiet for N days`, `no completions since 6 July`,
/// a paused line's `last 14 July` (Q1.1, owner 2026-10-30).
private struct LastActivityText: View {
  let last: LastActivity
  let today: Date
  let timeZone: TimeZone
  @Environment(\.locale) private var locale

  var body: some View {
    switch last {
    case .today: Text("today")
    case .yesterday: Text("yesterday")
    case .daysAgo(let days): Text("\(days) days ago")
    case .quiet(let days):
      Label("quiet for \(days) days", systemImage: "moon").foregroundStyle(.secondary)
    case .noCompletions(let since?):
      Text("no completions since \(date(since))").foregroundStyle(.secondary)
    case .noCompletions(nil): Text("no activity yet").foregroundStyle(.secondary)
    case .paused(let last?): Text("last \(date(last))")
    case .paused(nil): Text(verbatim: "—")
    }
  }

  private func date(_ date: Date) -> String {
    TodayFormat.lastDate(date, today: today, timeZone: timeZone, locale: locale)
  }
}

extension View {
  /// A paused line's whole row reads in `Tokens.paused` (`design/components.md` § LineStateLabel).
  fileprivate func dimmed(_ row: LinesScreen.Row) -> some View {
    foregroundStyle(row.state == .paused ? AnyShapeStyle(Tokens.paused) : AnyShapeStyle(.primary))
  }
}
