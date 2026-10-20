import MoonShineCore
import SwiftUI

/// One row of the Today table: a task, or the collapsed Life ops summary.
enum TodayTableRow: Identifiable, Hashable {
  case task(TodayScreen.Row)
  case lifeOps(count: Int, estimateMinutes: Int)

  enum ID: Hashable {
    case task(TaskItemID)
    case lifeOps
  }

  var id: ID {
    switch self {
    case .task(let row): .task(row.id)
    case .lifeOps: .lifeOps
    }
  }
}

/// `design/screens/today.md`, draft-2 list. Checkboxes show state only; opening a task in
/// OmniFocus comes with the link opener (S4-5).
struct TodayView: View {
  let screen: TodayScreen
  @SceneStorage("today.lifeOpsExpanded") private var lifeOpsExpanded = false
  @State private var selection: TodayTableRow.ID?
  @Environment(\.locale) private var locale

  var body: some View {
    Table(of: TodayTableRow.self, selection: $selection) {
      TableColumn(Text(verbatim: "")) { row in
        if case .task = row {
          Image(systemName: "circle")
            .foregroundStyle(Tokens.checkboxStroke)
            .accessibilityLabel(Text("Not completed"))
        }
      }
      .width(34)
      TableColumn("Task") { row in
        switch row {
        case .task(let task): Text(task.title)
        case .lifeOps: Text("\(Text(verbatim: "🧺")) Life ops").fontWeight(.semibold)
        }
      }
      TableColumn("Project → Line → Artifact") { row in
        switch row {
        case .task(let task):
          Text(task.trace.joined(separator: " → "))
            .foregroundStyle(Tokens.chipText)
            .lineLimit(1)
        case .lifeOps(let count, _):
          Text("\(count) tasks").foregroundStyle(.secondary)
        }
      }
      .width(290)
      TableColumn("Estimate") { row in
        switch row {
        case .task(let task): EstimateText(minutes: task.estimateMinutes)
        case .lifeOps(_, let minutes): EstimateText(minutes: minutes)
        }
      }
      .width(100)
      TableColumn("When") { row in
        if case .task(let task) = row { WhenText(row: task, timeZone: screen.timeZone) }
      }
      .width(118)
    } rows: {
      ForEach(screen.sections) { section in
        Section {
          ForEach(section.rows) { TableRow(TodayTableRow.task($0)) }
        } header: {
          Text(verbatim: [section.emoji, section.name].compactMap { $0 }.joined(separator: " "))
        }
      }
      if !screen.fromEarlier.isEmpty {
        Section {
          ForEach(screen.fromEarlier) { TableRow(TodayTableRow.task($0)) }
        } header: {
          Label("From earlier", systemImage: "arrow.uturn.backward")
        }
      }
      if !screen.lifeOps.isEmpty {
        DisclosureTableRow(
          TodayTableRow.lifeOps(
            count: screen.lifeOps.count, estimateMinutes: screen.lifeOpsEstimateMinutes),
          isExpanded: $lifeOpsExpanded
        ) {
          ForEach(screen.lifeOps) { TableRow(TodayTableRow.task($0)) }
        }
      }
    }
    .tableStyle(.inset)
    .alternatingRowBackgrounds(.disabled)
    .navigationTitle("Today")
    .navigationSubtitle(
      Text(
        "\(TodayFormat.day(screen.day, timeZone: screen.timeZone, locale: locale)) · Week \(screen.week)"
      ))
  }
}

/// `TodayFormat.estimate`, in the catalog's words; empty without an estimate.
struct EstimateText: View {
  let minutes: Int?

  var body: some View {
    if let estimate = TodayFormat.estimate(minutes) {
      Group {
        switch estimate {
        case .minutes(let minutes): Text("≈ \(minutes) min")
        case .hours(let hours): Text("≈ \(hours) h")
        case .hoursAndMinutes(let hours, let minutes): Text("≈ \(hours) h \(minutes) min")
        }
      }
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
  }
}

/// A due date (amber only when urgent) and, for a task from earlier, its planned age.
struct WhenText: View {
  let row: TodayScreen.Row
  let timeZone: TimeZone
  @Environment(\.locale) private var locale

  var body: some View {
    HStack(spacing: 6) {
      if let days = row.plannedDaysAgo {
        Text("planned \(days) days ago").foregroundStyle(.secondary)
      }
      if let due = row.due {
        let date = TodayFormat.dueDate(due, timeZone: timeZone, locale: locale)
        switch TodayFormat.dueStyle(isUrgent: row.isUrgent) {
        case .deadline:
          Text("Due \(date)")
            .fontWeight(.semibold)
            .foregroundStyle(Tokens.dueText)
            .padding(.horizontal, 5)
            .background(Tokens.dueFill, in: RoundedRectangle(cornerRadius: 4))
        case .plain:
          Text("due \(date)").foregroundStyle(.secondary)
        }
      }
    }
    .lineLimit(1)
  }
}
