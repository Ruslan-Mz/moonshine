import MoonShineCore
import SwiftUI

/// One row of the Today table: a task, or a collapsed summary (Life ops, the older done tasks).
enum TodayTableRow: Identifiable, Hashable {
  case task(TodayScreen.Row)
  case lifeOps(count: Int, estimateMinutes: Int)
  case moreDone(count: Int)

  enum ID: Hashable {
    case task(TaskItemID)
    case lifeOps
    case moreDone
  }

  var id: ID {
    switch self {
    case .task(let row): .task(row.id)
    case .lifeOps: .lifeOps
    case .moreDone: .moreDone
    }
  }
}

/// Builds Today from the store's overview with the scene's own state, so "Show all" and a
/// stored choice take effect.
struct TodayContainer: View {
  let overview: Overview
  @SceneStorage("today.showAllFlagged") private var showAllFlagged = false

  var body: some View {
    TodayView(
      screen: TodayScreen(overview, showAllFlagged: showAllFlagged),
      showAllFlagged: $showAllFlagged)
  }
}

/// `design/screens/today.md`, draft-2 list. Checkboxes show state only; opening a task in
/// OmniFocus comes with the link opener (S4-5).
struct TodayView: View {
  let screen: TodayScreen
  @Binding var showAllFlagged: Bool
  @SceneStorage("today.lifeOpsExpanded") private var lifeOpsExpanded = false
  @SceneStorage("today.moreDoneExpanded") private var moreDoneExpanded = false
  @State private var selection: TodayTableRow.ID?
  @Environment(\.locale) private var locale

  /// Done today shows the most recent ones; the rest sit behind "N more".
  static let doneShown = 3

  var body: some View {
    VStack(spacing: 0) {
      if !screen.anchors.isEmpty {
        AnchorStrip(anchors: screen.anchors, total: screen.anchorsTotal, done: screen.anchorsDone)
        Divider()
      }
      table
    }
    .navigationTitle("Today")
    .navigationSubtitle(subtitle)
  }

  private var table: some View {
    Table(of: TodayTableRow.self, selection: $selection) {
      TableColumn(Text(verbatim: "")) { row in
        if case .task(let task) = row { Checkbox(isDone: task.isDone) }
      }
      .width(34)
      TableColumn("Task") { row in
        switch row {
        case .task(let task):
          Text(task.title)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? Tokens.doneText : Color.primary)
        case .lifeOps: Text("\(Text(verbatim: "🧺")) Life ops").fontWeight(.semibold)
        case .moreDone(let count): Text("\(count) more").foregroundStyle(.secondary)
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
        case .moreDone: EmptyView()
        }
      }
      .width(290)
      TableColumn("Estimate") { row in
        switch row {
        case .task(let task): EstimateText(minutes: task.estimateMinutes)
        case .lifeOps(_, let minutes): EstimateText(minutes: minutes)
        case .moreDone: EmptyView()
        }
      }
      .width(100)
      TableColumn("When") { row in
        if case .task(let task) = row { WhenText(row: task, timeZone: screen.timeZone) }
      }
      .width(118)
    } rows: {
      if !screen.top.isEmpty {
        Section {
          ForEach(screen.top) { TableRow(TodayTableRow.task($0)) }
        } header: {
          topHeader
        }
      }
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
      if !screen.doneToday.isEmpty {
        Section {
          ForEach(Array(screen.doneToday.prefix(Self.doneShown))) {
            TableRow(TodayTableRow.task($0))
          }
          if screen.doneToday.count > Self.doneShown {
            DisclosureTableRow(
              TodayTableRow.moreDone(count: screen.doneToday.count - Self.doneShown),
              isExpanded: $moreDoneExpanded
            ) {
              ForEach(Array(screen.doneToday.dropFirst(Self.doneShown))) {
                TableRow(TodayTableRow.task($0))
              }
            }
          }
        } header: {
          Label("Done today", systemImage: "checkmark.circle")
        }
      }
    }
    .tableStyle(.inset)
    .alternatingRowBackgrounds(.disabled)
  }

  /// `Top 3 today`, and with more flagged tasks than that, the caption and its toggle (⌥⌘F).
  private var topHeader: some View {
    HStack(spacing: 8) {
      Text("Top 3 today")
      Spacer()
      if screen.flaggedCount > Overview.topShown {
        Text("\(screen.flaggedCount) flagged — \(screen.top.count) shown")
          .fontWeight(.regular)
          .foregroundStyle(.secondary)
        Button {
          showAllFlagged.toggle()
        } label: {
          if showAllFlagged { Text("Show fewer") } else { Text("Show all") }
        }
        .buttonStyle(.link)
        .keyboardShortcut("f", modifiers: [.option, .command])
      }
    }
  }

  /// `Thursday 1 October · Week 40 · 23 open · 6 done · ≈ 11 h 15 min est.`; the estimate is
  /// left out when no open task has one.
  private var subtitle: Text {
    let day = TodayFormat.day(screen.day, timeZone: screen.timeZone, locale: locale)
    let open = Text("\(screen.totals.open) open")
    let done = Text("\(screen.totals.done) done")
    let facts = Text("\(day) · Week \(screen.week) · \(open) · \(done)")
    guard let estimate = TodayFormat.estimate(screen.totals.estimateMinutes) else { return facts }
    return Text("\(facts) · \(EstimateText.text(estimate, total: true))")
  }
}

/// Read-only in phase 1: it shows the state and writes nothing.
struct Checkbox: View {
  let isDone: Bool

  var body: some View {
    if isDone {
      Image(systemName: "checkmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, Color.accentColor)
        .accessibilityLabel(Text("Completed"))
    } else {
      Image(systemName: "circle")
        .foregroundStyle(Tokens.checkboxStroke)
        .accessibilityLabel(Text("Not completed"))
    }
  }
}

/// `TodayFormat.estimate`, in the catalog's words; empty without an estimate.
struct EstimateText: View {
  let minutes: Int?

  var body: some View {
    if let estimate = TodayFormat.estimate(minutes) {
      Self.text(estimate)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  /// A cell reads `≈ 45 min`; a total names itself an estimate, `≈ 1 h 15 min est.`.
  static func text(_ estimate: TodayFormat.Estimate, total: Bool = false) -> Text {
    switch (estimate, total) {
    case (.minutes(let minutes), false): Text("≈ \(minutes) min")
    case (.hours(let hours), false): Text("≈ \(hours) h")
    case (.hoursAndMinutes(let hours, let minutes), false): Text("≈ \(hours) h \(minutes) min")
    case (.minutes(let minutes), true): Text("≈ \(minutes) min est.")
    case (.hours(let hours), true): Text("≈ \(hours) h est.")
    case (.hoursAndMinutes(let hours, let minutes), true): Text("≈ \(hours) h \(minutes) min est.")
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
