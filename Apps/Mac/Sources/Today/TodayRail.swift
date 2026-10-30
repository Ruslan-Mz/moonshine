import MoonShineCore
import SwiftUI

/// `design/screens/today.md` § Right rail: Quarter focus, Touched today, Quiet lines, Paused on
/// purpose. The Day rail comes with S4-3b; "Open in OmniFocus" and "Open quarter note" come with
/// the link opener (S4-5).
struct TodayRail: View {
  let screen: TodayScreen

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if screen.railIsEmpty {
          Text("Nothing on the rail today").foregroundStyle(.secondary)
        }
        if let focus = screen.quarterFocus { QuarterFocusCard(focus: focus) }
        if !screen.touched.isEmpty { touched }
        if !screen.quiet.isEmpty || !screen.noActivity.isEmpty { quiet }
        if !screen.paused.isEmpty { paused }
      }
      .font(.system(size: 12))
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Rhythm and progress in their own columns, never summed (decision O1).
  private var touched: some View {
    RailSection("Touched today") {
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
        GridRow {
          Text("Line")
          Text("Rhythm")
          Text("Progress")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        ForEach(screen.touched) { row in
          GridRow {
            LineName(emoji: row.emoji, name: row.name)
            CountText(kind: .sessions, value: row.sessions)
            CountText(kind: .tasks, value: row.tasks)
          }
        }
      }
    }
  }

  private var quiet: some View {
    RailSection("Quiet lines") {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(screen.quiet) {
          QuietLineCard(line: $0, today: screen.day, timeZone: screen.timeZone)
        }
        ForEach(screen.noActivity) { NoActivityCard(line: $0) }
        Text(
          "Quiet: an active line with no completed task for \(Overview.quietAfterDays) days or more. Foundation, maintenance and paused lines are never quiet."
        )
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var paused: some View {
    RailSection("Paused on purpose") {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(screen.paused) { line in
          HStack(spacing: 6) {
            if let emoji = line.emoji { Text(verbatim: emoji).opacity(0.5) }
            Text(verbatim: line.name)
          }
          .foregroundStyle(Tokens.paused)
        }
      }
    }
  }
}

private struct RailSection<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder let content: Content

  init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 12, weight: .semibold))
      content
    }
  }
}

/// A line's emoji and name; Life ops in the UI language.
private struct LineName: View {
  let emoji: String?
  let name: String?

  var body: some View {
    if let name {
      Text(verbatim: [emoji, name].compactMap { $0 }.joined(separator: " ")).lineLimit(1)
    } else {
      Text("\(Text(verbatim: emoji ?? "🧺")) Life ops").lineLimit(1)
    }
  }
}

/// `1 session`, `0 tasks` as `—` in tertiary (`design/screens/today.md` § Right rail).
private struct CountText: View {
  enum Kind { case sessions, tasks }

  let kind: Kind
  let value: Int

  var body: some View {
    if value == 0 {
      Text(verbatim: "—").foregroundStyle(.tertiary)
    } else {
      switch kind {
      case .sessions: Text("\(value) sessions").foregroundStyle(Tokens.rhythm)
      case .tasks: Text("\(value) tasks").foregroundStyle(Tokens.progress)
      }
    }
  }
}

/// `design/components.md` § QuarterFocusCard: a neutral done / not-done glyph, no bars and no
/// percentages.
private struct QuarterFocusCard: View {
  let focus: TodayScreen.QuarterFocus

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Q\(focus.quarter) focus").font(.system(size: 13, weight: .semibold))
        Spacer(minLength: 6)
        Text("\(focus.done) of \(focus.rows.count) quarter artifacts done")
          .foregroundStyle(.tertiary)
      }
      ForEach(focus.rows) { row in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: row.isDone ? "checkmark.circle" : "circle")
            .foregroundStyle(.secondary)
            .accessibilityLabel(row.isDone ? Text("Completed") : Text("Not completed"))
          if let emoji = row.emoji { Text(verbatim: emoji) }
          Text(verbatim: row.title).font(.system(size: 12.5)).lineLimit(2)
        }
      }
    }
    .padding(14)
    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.cardBorder))
  }
}

/// `design/components.md` § QuietLineCard: a fact, then a next step.
private struct QuietLineCard: View {
  let line: TodayScreen.Quiet
  let today: Date
  let timeZone: TimeZone
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        LineName(emoji: line.emoji, name: line.name).fontWeight(.semibold)
        Spacer(minLength: 6)
        Label("quiet for \(line.days) days", systemImage: "moon")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text(
        "Last: \(line.lastTitle), \(TodayFormat.lastDate(line.lastDate, today: today, timeZone: timeZone, locale: locale))"
      )
      .foregroundStyle(.secondary)
      Divider()
      NextStepBlock(label: "Suggested next step", next: line.next)
    }
    .padding(14)
    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.cardBorder))
  }
}

/// `design/components.md` § NoActivityCard: dashed border, no fill.
private struct NoActivityCard: View {
  let line: TodayScreen.NoActivity

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        LineName(emoji: line.emoji, name: line.name).fontWeight(.semibold)
        Spacer(minLength: 6)
        Text("no activity yet").foregroundStyle(.secondary).lineLimit(1)
      }
      NextStepBlock(label: "First step", next: line.next)
    }
    .padding(14)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Tokens.checkboxStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
  }
}

/// The next step and its estimate, or `no next action` when the line has none.
private struct NextStepBlock: View {
  let label: LocalizedStringKey
  let next: TodayScreen.NextStep?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let next {
        Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        Text(next.title).font(.system(size: 13))
        if let estimate = TodayFormat.estimate(next.estimateMinutes) {
          EstimateText.text(estimate, total: true).foregroundStyle(.secondary)
        }
      } else {
        Text("no next action").foregroundStyle(.secondary)
      }
    }
  }
}
