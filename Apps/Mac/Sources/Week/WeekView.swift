import MoonShineCore
import SwiftUI

/// `design/screens/week.md`, draft-2: the line strip, seven day columns and the No plan tray,
/// with ‹ Today › and the View menu's Previous Week (⌘←), Next Week (⌘→) and Go to Today (S5-1b).
/// Checkboxes show state only and write nothing; a card opens its task in OmniFocus on a
/// double-click or its accessibility action, through the opener.
struct WeekView: View {
  let overview: Overview
  /// Nil is this week; held as the week, so midnight cannot move it.
  @State private var shown: ISOWeek?

  var body: some View {
    let screen = WeekScreen(overview, week: shown)
    let stepper = WeekStepper(navigation: screen.navigation, shown: $shown)
    WeekContent(screen: screen)
      .toolbar {
        ToolbarItem(placement: .navigation) {
          ControlGroup {
            Button {
              stepper.step(by: -1)
            } label: {
              Label("Previous Week", systemImage: "chevron.left")
            }
            .help(Text("Previous week (⌘←)"))
            .disabled(!stepper.canStep(by: -1))
            Button("Today") { stepper.goToToday() }
              .disabled(stepper.isCurrent)
            Button {
              stepper.step(by: 1)
            } label: {
              Label("Next Week", systemImage: "chevron.right")
            }
            .help(Text("Next week (⌘→)"))
            .disabled(!stepper.canStep(by: 1))
          }
        }
      }
      .focusedSceneValue(\.weekStepper, stepper)
  }
}

private struct WeekContent: View {
  let screen: WeekScreen
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      strip
      Divider()
      HStack(spacing: 0) {
        ForEach(screen.days) { day in
          DayColumn(day: day, timeZone: screen.timeZone)
          if day.id != screen.days.last?.id { Divider() }
        }
      }
      .frame(maxHeight: .infinity)
      Divider()
      tray
    }
    .frame(minWidth: WeekView.minimumWidth)
    .navigationTitle(Text("Week \(screen.week)"))
    .navigationSubtitle(Text("\(range) · ISO week"))
  }

  private var range: String {
    WeekFormat.range(screen.firstDay, screen.lastDay, timeZone: screen.timeZone, locale: locale)
  }

  // MARK: Line strip

  private var strip: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 16) {
        WeekSwatch(color: Tokens.rhythm, text: Text("Rhythm"))
        WeekSwatch(color: Tokens.progress, text: Text("Progress"))
        // A past week is whole, and a future one has not started.
        if screen.isCurrent { legend }
        Spacer()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 9),
        alignment: .leading, spacing: 8
      ) {
        ForEach(screen.cells) { cell in
          StripCell(cell: cell, screen: screen)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  /// `Week in progress — Mon to Thu`; on Monday `Week in progress — Mon`.
  @ViewBuilder private var legend: some View {
    let days = WeekFormat.daysSoFar(
      first: screen.firstDay, today: screen.today, timeZone: screen.timeZone, locale: locale)
    if let today = days.today {
      Text("Week in progress — \(days.first) to \(today)")
    } else {
      Text("Week in progress — \(days.first)")
    }
  }

  // MARK: No plan tray

  private var tray: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("No plan").font(.headline)
        Text(verbatim: "\(screen.noPlan.count)").foregroundStyle(.secondary).monospacedDigit()
        Spacer()
        Text("Drag onto a day to plan — comes with the Act phase")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8
        ) {
          ForEach(screen.noPlan) { card in
            CardView(card: card, timeZone: screen.timeZone, isCompact: true)
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .frame(height: WeekView.trayHeight)
  }
}

extension WeekView {
  /// Seven columns need this much before the cards' titles wrap to nothing.
  static let minimumWidth: CGFloat = 760
  static let trayHeight: CGFloat = 188
}

/// A day: weekday, date and summary, then its cards; today's column is tinted.
private struct DayColumn: View {
  let day: WeekScreen.Day
  let timeZone: TimeZone
  @Environment(\.locale) private var locale
  @State private var showsMore = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(day.shown) { card in
            CardView(card: card, timeZone: timeZone)
          }
          if !day.more.isEmpty {
            Button {
              showsMore = true
            } label: {
              Text("+ \(day.more.count) more")
            }
            .buttonStyle(.link)
            // Tab reaches it without Full Keyboard Access; ↵ or Space opens the popover.
            .focusable()
            .onKeyPress(keys: [.return, .space]) { _ in
              showsMore = true
              return .handled
            }
            .popover(isPresented: $showsMore) { MoreList(cards: day.more, timeZone: timeZone) }
          }
        }
        .padding(6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(day.isToday ? Tokens.selection : Color.clear)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(verbatim: WeekFormat.weekday(day.start, timeZone: timeZone, locale: locale))
          .foregroundStyle(.secondary)
        dayNumber
      }
      .font(.callout.weight(.semibold))
      summary
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(day.isToday ? .isSelected : [])
  }

  @ViewBuilder private var dayNumber: some View {
    let number = Text(verbatim: WeekFormat.dayNumber(day.start, timeZone: timeZone, locale: locale))
      .monospacedDigit()
    if day.isToday {
      number
        .foregroundStyle(Color.white)
        .padding(.horizontal, 5)
        .background(Color.accentColor, in: Capsule())
    } else {
      number
    }
  }

  /// `5 done`, `3 done · ≈ 8 h`, `≈ 2 h 50 min`; an empty line keeps the columns aligned.
  private var summary: Text {
    let terms = day.summary.map { term -> Text in
      switch term {
      case .done(let count): Text("\(count) done")
      case .estimate(let minutes): EstimateText.text(TodayFormat.duration(minutes))
      }
    }
    guard let first = terms.first else { return Text(verbatim: " ") }
    return terms.dropFirst().reduce(first) { Text("\($0) · \($1)") }
  }

}

/// The day's cards after the first six, in the same order: arrows select, ⌘↵ opens the selected
/// task in OmniFocus, as everywhere (`design/principles.md`), and Esc closes.
private struct MoreList: View {
  let cards: [WeekScreen.Card]
  let timeZone: TimeZone
  @State private var selection: TaskItemID?
  @FocusState private var isFocused: Bool
  @Environment(\.openTarget) private var openTarget

  var body: some View {
    VStack(spacing: 0) {
      List(cards, selection: $selection) { card in
        CardView(card: card, timeZone: timeZone)
      }
      .focused($isFocused)
      Divider()
      HStack {
        Spacer()
        Button("Open in OmniFocus") {
          if let selection { openTarget(.task(selection)) }
        }
        .keyboardShortcut(OpenCommands.shortcut)
        .disabled(selection == nil)
      }
      .padding(8)
    }
    .frame(width: 280, height: 380)
    .onAppear {
      selection = cards.first?.id
      isFocused = true
    }
  }
}

/// A task: the checkbox and two lines of title, then its line, estimate and due date. In the
/// tray: emoji, title and estimate on one line.
private struct CardView: View {
  let card: WeekScreen.Card
  let timeZone: TimeZone
  var isCompact = false
  @Environment(\.locale) private var locale
  @Environment(\.openTarget) private var openTarget

  var body: some View {
    Group {
      if isCompact {
        HStack(spacing: 6) {
          Text(verbatim: card.emoji ?? "")
          Text(verbatim: card.title).lineLimit(1)
          Spacer(minLength: 4)
          EstimateText(minutes: card.estimateMinutes).font(.caption)
        }
      } else {
        HStack(alignment: .top, spacing: 6) {
          Checkbox(isDone: card.isCompleted)
          VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: card.title)
              .lineLimit(2)
              .strikethrough(card.isCompleted)
              .foregroundStyle(
                card.isCompleted ? AnyShapeStyle(Tokens.doneText) : AnyShapeStyle(.primary))
            facts.font(.caption)
          }
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.cardBorder))
    .opacity(card.isCompleted ? 0.55 : 1)
    .opensOnDoubleClick(.task(card.id))
    .accessibilityElement(children: .combine)
    .accessibilityAction(named: Text("Open in OmniFocus")) { openTarget(.task(card.id)) }
  }

  private var facts: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        WeekLineName(emoji: card.emoji, name: card.lineName)
        EstimateText(minutes: card.estimateMinutes)
      }
      .foregroundStyle(.secondary)
      if let due = card.due {
        let date = WeekFormat.due(due, timeZone: timeZone, locale: locale)
        if due.isDeadline {
          Text("Due \(date)")
            .fontWeight(.semibold)
            .foregroundStyle(Tokens.dueText)
            .padding(.horizontal, 5)
            .background(Tokens.dueFill, in: RoundedRectangle(cornerRadius: 4))
        } else {
          Text("due \(date)").foregroundStyle(.secondary)
        }
      }
    }
    .lineLimit(1)
  }
}

/// A line's emoji and name in the strip: rhythm and progress against the 4-week average, `—`
/// for a series that does not apply, or `no completions since …` for a line without any.
private struct StripCell: View {
  let cell: WeekScreen.Cell
  let screen: WeekScreen

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: [cell.emoji, cell.name].compactMap { $0 }.joined(separator: " "))
        .fontWeight(.semibold)
        .lineLimit(1)
      if cell.hasNoCompletions {
        LastActivityText(
          last: .noCompletions(since: screen.completedSince), today: screen.today,
          timeZone: screen.timeZone)
      } else {
        Series(
          color: Tokens.rhythm, applies: cell.hasRhythm, count: cell.thisWeek?.rhythm,
          average: cell.average.rhythm, kind: .rhythm)
        Series(
          color: Tokens.progress, applies: cell.hasProgress, count: cell.thisWeek?.progress,
          average: cell.average.progress, kind: .progress)
      }
    }
    .font(.caption)
    .accessibilityElement(children: .combine)
  }
}

/// `■ 4  avg 4.0`: plain numbers, no colour for up or down (`week.md` § Acceptance).
private struct Series: View {
  enum Kind { case rhythm, progress }

  let color: Color
  let applies: Bool
  /// Nil on a future week: the average only (owner, 2026-11-28).
  let count: Int?
  let average: Double
  let kind: Kind
  @Environment(\.locale) private var locale

  var body: some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
      if applies {
        if let count { Text(verbatim: "\(count)").monospacedDigit() }
        Text("avg \(WeekFormat.average(average, locale: locale))")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      } else {
        Text(verbatim: "—").foregroundStyle(.tertiary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private var label: Text {
    let shown = WeekFormat.average(average, locale: locale)
    switch (kind, applies, count) {
    case (.rhythm, true, let count?): return Text("rhythm \(count), average \(shown)")
    case (.progress, true, let count?): return Text("progress \(count), average \(shown)")
    case (.rhythm, true, nil): return Text("rhythm average \(shown)")
    case (.progress, true, nil): return Text("progress average \(shown)")
    case (.rhythm, false, _): return Text("rhythm not applicable")
    case (.progress, false, _): return Text("progress not applicable")
    }
  }
}

private struct WeekSwatch: View {
  let color: Color
  let text: Text

  var body: some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
      text
    }
  }
}

/// The line's emoji and name; Life ops by its name in the catalog.
private struct WeekLineName: View {
  let emoji: String?
  let name: String?

  var body: some View {
    if let name {
      Text(verbatim: [emoji, name].compactMap { $0 }.joined(separator: " "))
    } else {
      Text("\(Text(verbatim: emoji ?? "🧺")) Life ops")
    }
  }
}
