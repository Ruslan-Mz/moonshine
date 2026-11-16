import MoonShineCore
import SwiftUI

/// The widths the narrowest Line detail needs: two cards side by side; the inspector at its
/// minimum beside it.
enum LineDetailColumns {
  static let padding: CGFloat = 20
  static let cardSpacing: CGFloat = 12
  static let inspectorMinimum: CGFloat = 280
  static let inspectorIdeal: CGFloat = 360

  static var minimumWidth: CGFloat {
    2 * MetricCard.minimumWidth + cardSpacing + 2 * padding
  }
}

/// Line detail pushed from Lines: its own back button, `Lines` with ⌘[ (rule 9).
struct LineDetailDestination: View {
  let overview: Overview
  let id: LineID
  @Binding var path: [LineID]

  var body: some View {
    Group {
      if let screen = LineDetailScreen(overview, line: id) {
        LineDetailView(screen: screen)
      } else {
        // A line an import removed while its detail was open.
        ContentUnavailableView("This line is not in the data shown.", systemImage: "tray")
      }
    }
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          if !path.isEmpty { path.removeLast() }
        } label: {
          Label("Lines", systemImage: "chevron.left")
        }
        .keyboardShortcut("[", modifiers: .command)
        .help(Text("Back to Lines (⌘[)"))
      }
    }
  }
}

/// `design/screens/line-detail.md`, draft-1 for S4-2b: header, the two cards, Projects, Next
/// actions; the inspector holds the parent and the last completions. Opening a task or a note
/// comes with the link opener (S4-5).
struct LineDetailView: View {
  let screen: LineDetailScreen
  /// Shown by default, as Today's rail; ⌃⌘I hides it (`InspectorCommands`).
  @SceneStorage("lineDetail.inspectorShown") private var inspectorShown = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        HStack(alignment: .top, spacing: LineDetailColumns.cardSpacing) {
          MetricCard(kind: .rhythm, metric: screen.rhythm, weeks: screen.weeks)
          MetricCard(kind: .progress, metric: screen.progress, weeks: screen.weeks)
        }
        projects
        nextActions
      }
      .padding(LineDetailColumns.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: LineDetailColumns.minimumWidth)
    .navigationTitle(Text("Lines › \(screen.title)"))
    .navigationSubtitle(LinesView.joined([Text("Line detail")] + screen.counts.map(Self.count)))
    .inspector(isPresented: $inspectorShown) {
      LineDetailInspector(screen: screen)
        .inspectorColumnWidth(
          min: LineDetailColumns.inspectorMinimum, ideal: LineDetailColumns.inspectorIdeal)
    }
    .toolbar {
      Button {
        inspectorShown.toggle()
      } label: {
        Label("Inspector", systemImage: "sidebar.trailing")
      }
      .help(Text("Show or hide the inspector (⌃⌘I)"))
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        if let emoji = screen.emoji { Text(verbatim: emoji).font(.system(size: 34)) }
        Text(verbatim: screen.name).font(.system(size: 24, weight: .bold))
      }
      HStack(spacing: 6) {
        Text(verbatim: screen.block)
        Text(verbatim: "·")
        StateText(state: screen.state, isFoundation: screen.isFoundation)
        if screen.budget != .none {
          Text(verbatim: "·")
          BudgetText(budget: screen.budget)
        }
        Text(verbatim: "·")
        Text("last activity")
        LastActivityText(last: screen.last, today: screen.today, timeZone: screen.timeZone)
      }
      .foregroundStyle(.secondary)
    }
  }

  private var projects: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Projects").font(.headline)
      if screen.projects.isEmpty {
        Text("No projects").foregroundStyle(.secondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
          GridRow {
            Text("Project")
            Text("Kind")
            Text("Next actions").gridColumnAlignment(.trailing)
            Text("Remaining")
          }
          .font(.caption).foregroundStyle(.secondary)
          Divider()
          ForEach(screen.projects) { row in
            GridRow {
              Label {
                Text(verbatim: row.title).lineLimit(1)
              } icon: {
                Image(systemName: "folder").foregroundStyle(.secondary)
              }
              switch row.kind {
              case .repeatingSessions: Text("repeating sessions")
              case .oneOffTasks: Text("one-off tasks")
              }
              Text(row.nextActions, format: .number).monospacedDigit()
              remaining(row.remainingMinutes)
            }
          }
        }
      }
    }
  }

  private func remaining(_ minutes: Int) -> some View {
    Group {
      if let estimate = TodayFormat.estimate(minutes) {
        EstimateText.text(estimate, total: true)
      } else {
        Text(verbatim: "—")
      }
    }
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }

  private var nextActions: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Next actions (\(screen.nextActions.count))").font(.headline)
      if screen.nextActions.isEmpty {
        Text("No next actions").foregroundStyle(.secondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
          ForEach(screen.nextActions) { row in
            GridRow {
              Text(verbatim: row.title).lineLimit(1)
              Text(verbatim: row.project ?? "").foregroundStyle(.secondary).lineLimit(1)
              EstimateText(minutes: row.estimateMinutes)
              LineDetailWhenText(when: row.when, timeZone: screen.timeZone)
            }
          }
        }
      }
    }
  }

  private static func count(_ count: LineDetailScreen.Count) -> Text {
    switch count {
    case .projects(let n): Text("\(n) projects")
    case .nextActions(let n): Text("\(n) next actions")
    }
  }
}

extension LineDetailScreen {
  /// `🎻 Violin`.
  var title: String { [emoji, name].compactMap { $0 }.joined(separator: " ") }
}

/// `design/components.md` § LineStateLabel, in words only.
struct StateText: View {
  let state: LineState
  let isFoundation: Bool

  var body: some View {
    switch state {
    case .paused: Text("paused on purpose")
    case _ where isFoundation: Text("foundation")
    case .active: Text("active")
    case .maintenance: Text("maintenance")
    }
  }
}

/// `today` / `Fri` / `12 Oct` / `no date`, or the due badge of Today (`WhenText`).
private struct LineDetailWhenText: View {
  let when: LineDetailFormat.When
  let timeZone: TimeZone
  @Environment(\.locale) private var locale

  var body: some View {
    switch when {
    case .due(let due, let urgent):
      let date = TodayFormat.dueDate(due, timeZone: timeZone, locale: locale)
      switch TodayFormat.dueStyle(isUrgent: urgent) {
      case .deadline:
        Text("Due \(date)")
          .fontWeight(.semibold)
          .foregroundStyle(Tokens.dueText)
          .padding(.horizontal, 5)
          .background(Tokens.dueFill, in: RoundedRectangle(cornerRadius: 4))
      case .plain:
        Text("due \(date)").foregroundStyle(.secondary)
      }
    case .today: Text("today")
    case .weekday(let date):
      Text(verbatim: LineDetailFormat.weekday(date, timeZone: timeZone, locale: locale))
    case .date(let date):
      Text(verbatim: TodayFormat.dueDate(date, timeZone: timeZone, locale: locale))
    case .none: Text("no date").foregroundStyle(.secondary)
    }
  }
}

/// The parent card and the last 10 completions.
private struct LineDetailInspector: View {
  let screen: LineDetailScreen
  @Environment(\.locale) private var locale

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        parentCard
        Text("Last 10 completions").font(.headline)
        if screen.completions.isEmpty {
          // The line's own last-activity words: `no completions since 6 July`, or `—`.
          LastActivityText(last: screen.last, today: screen.today, timeZone: screen.timeZone)
            .foregroundStyle(.secondary)
        } else {
          Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(screen.completions) { row in
              GridRow {
                day(row.completedAt).foregroundStyle(.secondary).monospacedDigit()
                Text(verbatim: row.title).lineLimit(2)
                switch row.kind {
                case .session: Text("session").foregroundStyle(Tokens.rhythm)
                case .oneOff: Text("task").foregroundStyle(Tokens.progress)
                }
              }
              .font(.callout)
            }
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder private var parentCard: some View {
    if let parent = screen.parent {
      VStack(alignment: .leading, spacing: 8) {
        Text(parent.isArtifact ? "Parent artifact" : "Parent note")
          .font(.caption).foregroundStyle(.secondary)
        Text(verbatim: parent.title).font(.system(size: 17, weight: .bold))
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
          if let status = parent.status {
            GridRow {
              Text("Status").foregroundStyle(.secondary)
              switch status {
              case .planned: Text("planned")
              case .inProgress: Text("in progress")
              case .done: Text("done")
              case .dropped: Text("dropped")
              }
            }
          }
          if let horizon = parent.horizon {
            GridRow {
              Text("Horizon").foregroundStyle(.secondary)
              switch horizon {
              case .year(let year): Text(verbatim: String(year))
              case .quarter(let quarter, let year): Text("Q\(quarter) \(String(year))")
              }
            }
          }
          if let path = parent.path {
            GridRow {
              Text("Note").foregroundStyle(.secondary)
              Text(verbatim: path).lineLimit(2).truncationMode(.middle)
            }
          }
        }
        .font(.callout)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Tokens.card, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.cardBorder))
    } else {
      Text("The line has no parent artifact or note.").foregroundStyle(.secondary)
    }
  }

  private func day(_ date: Date) -> Text {
    if TodayFormat.calendar(screen.timeZone).isDate(date, inSameDayAs: screen.today) {
      return Text("Today")
    }
    return Text(
      verbatim: LineDetailFormat.completionDay(date, timeZone: screen.timeZone, locale: locale))
  }
}
