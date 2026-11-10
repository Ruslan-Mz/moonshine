import MoonShineCore
import SwiftUI

/// One row of the Today table: a task, or the summary row of a disclosure (From earlier, Life
/// ops, the older done tasks).
enum TodayTableRow: Identifiable, Hashable {
  case task(TodayScreen.Row)
  case fromEarlier(count: Int)
  case lifeOps(count: Int, estimateMinutes: Int)
  case moreDone(count: Int)

  enum ID: Hashable {
    case task(TaskItemID)
    case fromEarlier
    case lifeOps
    case moreDone
  }

  var id: ID {
    switch self {
    case .task(let row): .task(row.id)
    case .fromEarlier: .fromEarlier
    case .lifeOps: .lifeOps
    case .moreDone: .moreDone
    }
  }
}

/// Column widths (`design/screens/today.md` § SwiftUI). On a narrow window the trace column
/// gives way first, down to its minimum; the task keeps about 15 characters.
enum TodayColumns {
  static let checkbox: CGFloat = 34
  static let taskMinimum: CGFloat = 120
  static let traceMinimum: CGFloat = 120
  static let traceIdeal: CGFloat = 290
  static let estimate: CGFloat = 100
  static let when: CGFloat = 118
  /// The inset table style's side margins and the spacing between five columns.
  static let margins: CGFloat = 40

  /// The narrowest Today: every column at its minimum.
  static var minimumWidth: CGFloat {
    checkbox + taskMinimum + traceMinimum + estimate + when + margins
  }
}

/// "Show all" of Top 3, as the View menu's command sees it in the key window.
struct FlaggedToggle {
  let isAvailable: Bool
  let showsAll: Binding<Bool>
}

/// A held line removal as Today and the menu command see it (S4-4e).
struct LineRemovalHold {
  /// Remove was pressed for exactly the lines held now; they go with the next import.
  let isApproved: Bool
  let omniFocusClosed: Bool
  let approve: () -> Void

  /// The notice names the first three, then `…`.
  static func names(_ lines: [TodayScreen.HeldLine]) -> String {
    let shown = lines.prefix(3).map {
      [$0.emoji, $0.name].compactMap { $0 }.joined(separator: " ")
    }
    return (shown + (lines.count > 3 ? ["…"] : [])).joined(separator: ", ")
  }

  /// The menu command acts while a hold stands unapproved; nil is nothing held.
  static func canApprove(_ removal: LineRemovalHold?) -> Bool {
    removal.map { !$0.isApproved } ?? false
  }
}

extension FocusedValues {
  @Entry var flaggedToggle: FlaggedToggle?
  /// Nil when nothing is held.
  @Entry var lineRemoval: LineRemovalHold?
}

/// ⌥⌘F in the View menu: it works wherever the list is scrolled, unlike a shortcut on the
/// Top 3 header, which is drawn only while visible.
struct TodayCommands: Commands {
  @FocusedValue(\.flaggedToggle) private var toggle
  @FocusedValue(\.lineRemoval) private var removal

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button {
        toggle?.showsAll.wrappedValue.toggle()
      } label: {
        if toggle?.showsAll.wrappedValue == true {
          Text("Show Fewer Flagged Tasks")
        } else {
          Text("Show All Flagged Tasks")
        }
      }
      .keyboardShortcut("f", modifiers: [.option, .command])
      .disabled(toggle?.isAvailable != true)
      Button("Remove Lines No Longer in the Budget Note") { removal?.approve() }
        .disabled(!LineRemovalHold.canApprove(removal))
    }
  }
}

/// Builds Today from the store's overview with the scene's own state, so "Show all" and a
/// stored choice take effect.
struct TodayContainer: View {
  let overview: Overview
  let removal: LineRemovalHold
  @SceneStorage("today.showAllFlagged") private var showAllFlagged = false

  var body: some View {
    let screen = TodayScreen(overview, showAllFlagged: showAllFlagged)
    TodayView(screen: screen, removal: removal, showAllFlagged: $showAllFlagged)
      .focusedSceneValue(
        \.flaggedToggle,
        FlaggedToggle(isAvailable: screen.showsFlaggedCaption, showsAll: $showAllFlagged)
      )
      .focusedSceneValue(\.lineRemoval, screen.heldRemoval.isEmpty ? nil : removal)
  }
}

/// `design/components.md` § LineRemovalNotice: a calm fact above the table, with no dismiss;
/// the lines stay until Remove (S4-4e).
private struct LineRemovalNotice: View {
  let lines: [TodayScreen.HeldLine]
  let removal: LineRemovalHold

  private var names: String { LineRemovalHold.names(lines) }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: "info.circle").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 4) {
        Text(
          "The budget note no longer lists \(lines.count) lines: \(names). They stay in MoonShine until you remove them."
        )
        if removal.isApproved {
          Group {
            if removal.omniFocusClosed {
              Text("They will be removed at the next import, once OmniFocus is open")
            } else {
              Text("They will be removed at the next import")
            }
          }
          .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      if !removal.isApproved {
        Button("Remove \(lines.count) lines") { removal.approve() }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Tokens.card)
  }
}

/// `design/screens/today.md`, draft-2 list. Checkboxes show state only; opening a task in
/// OmniFocus comes with the link opener (S4-5).
struct TodayView: View {
  let screen: TodayScreen
  let removal: LineRemovalHold
  @Binding var showAllFlagged: Bool
  @SceneStorage("today.fromEarlierExpanded") private var fromEarlierExpanded = true
  @SceneStorage("today.lifeOpsExpanded") private var lifeOpsExpanded = false
  @SceneStorage("today.moreDoneExpanded") private var moreDoneExpanded = false
  /// The rail is shown by default, at 1100×700 too (owner, 2026-10-27); ⌃⌘I hides it.
  @SceneStorage("today.railShown") private var railShown = true
  @State private var selection: TodayTableRow.ID?
  /// The list has the keyboard from launch, and again after any row is clicked, so ↑↓ work
  /// even when an earlier click went to the sidebar.
  @FocusState private var listFocused: Bool
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      if !screen.heldRemoval.isEmpty {
        LineRemovalNotice(lines: screen.heldRemoval, removal: removal)
        Divider()
      }
      if !screen.anchors.isEmpty {
        AnchorStrip(anchors: screen.anchors, total: screen.anchorsTotal, done: screen.anchorsDone)
        Divider()
      }
      table
    }
    .frame(minWidth: TodayColumns.minimumWidth)
    .navigationTitle("Today")
    .navigationSubtitle(subtitle)
    .inspector(isPresented: $railShown) {
      TodayRail(screen: screen).inspectorColumnWidth(300)
    }
    .toolbar {
      Button {
        railShown.toggle()
      } label: {
        Label("Right Rail", systemImage: "sidebar.trailing")
      }
      .help(Text("Show or hide the right rail (⌃⌘I)"))
    }
  }

  private var table: some View {
    Table(of: TodayTableRow.self, selection: $selection) {
      TableColumn(Text(verbatim: "")) { row in
        if case .task(let task) = row { Checkbox(isDone: task.isDone) }
      }
      .width(TodayColumns.checkbox)
      TableColumn("Task") { row in
        switch row {
        case .task(let task):
          Text(task.title)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? Tokens.doneText : Color.primary)
        case .fromEarlier(let count):
          Label("From earlier (\(count))", systemImage: "arrow.uturn.backward")
            .fontWeight(.semibold)
        case .lifeOps: Text("\(Text(verbatim: "🧺")) Life ops").fontWeight(.semibold)
        case .moreDone(let count): Text("\(count) more").foregroundStyle(.secondary)
        }
      }
      .width(min: TodayColumns.taskMinimum)
      TableColumn("Project → Line → Artifact") { row in
        switch row {
        case .task(let task):
          Text(task.trace.joined(separator: " → "))
            .foregroundStyle(Tokens.chipText)
            .lineLimit(1)
        case .lifeOps(let count, _):
          Text("\(count) tasks").foregroundStyle(.secondary)
        case .fromEarlier, .moreDone: EmptyView()
        }
      }
      .width(min: TodayColumns.traceMinimum, ideal: TodayColumns.traceIdeal)
      TableColumn("Estimate") { row in
        switch row {
        case .task(let task): EstimateText(minutes: task.estimateMinutes)
        case .lifeOps(_, let minutes): EstimateText(minutes: minutes)
        case .fromEarlier, .moreDone: EmptyView()
        }
      }
      .width(TodayColumns.estimate)
      TableColumn("When") { row in
        if case .task(let task) = row { WhenText(row: task, timeZone: screen.timeZone) }
      }
      .width(TodayColumns.when)
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
        DisclosureTableRow(
          TodayTableRow.fromEarlier(count: screen.fromEarlier.count),
          isExpanded: $fromEarlierExpanded
        ) {
          ForEach(screen.fromEarlier) { TableRow(TodayTableRow.task($0)) }
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
          ForEach(screen.doneVisible) { TableRow(TodayTableRow.task($0)) }
          if !screen.doneMore.isEmpty {
            DisclosureTableRow(
              TodayTableRow.moreDone(count: screen.doneMore.count),
              isExpanded: $moreDoneExpanded
            ) {
              ForEach(screen.doneMore) { TableRow(TodayTableRow.task($0)) }
            }
          }
        } header: {
          Label("Done today", systemImage: "checkmark.circle")
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

  /// `Top 3 today`, and with more flagged tasks than that, the caption and its toggle for the
  /// mouse; the keyboard has ⌥⌘F in the View menu (`TodayCommands`).
  private var topHeader: some View {
    HStack(spacing: 8) {
      Text("Top 3 today")
      Spacer()
      if screen.showsFlaggedCaption {
        Text("\(screen.flaggedCount) flagged — \(screen.top.count) shown")
          .fontWeight(.regular)
          .foregroundStyle(.secondary)
        Button {
          showAllFlagged.toggle()
        } label: {
          if showAllFlagged { Text("Show fewer") } else { Text("Show all") }
        }
        .buttonStyle(.link)
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
