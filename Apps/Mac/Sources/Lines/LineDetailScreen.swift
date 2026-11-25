import Foundation
import MoonShineCore

/// What Line detail shows, as values (`design/screens/line-detail.md`). Dates are formatted in
/// `timeZone`, the workspace's zone.
struct LineDetailScreen: Equatable {
  struct ProjectRow: Identifiable, Hashable {
    let id: ProjectID
    let title: String
    let kind: LineProjectRow.Kind
    let nextActions: Int
    let remainingMinutes: Int
  }

  struct ItemRow: Identifiable, Hashable {
    let id: TaskItemID
    let title: String
    let project: String?
    let estimateMinutes: Int?
    let when: LineDetailFormat.When
  }

  struct CompletionRow: Identifiable, Hashable {
    let id: TaskItemID
    let title: String
    let completedAt: Date
    let kind: LineCompletion.Kind
  }

  /// One card: this week's count, the 8 weeks and the mean of the 4 before this one.
  struct Metric: Hashable {
    let values: [Int]
    let average: Double
    var thisWeek: Int { values.last ?? 0 }
  }

  /// The inspector's card: the artifact the line's thread ends at, or its parent note. No
  /// status row: `line-detail.md` has none.
  struct Parent: Hashable {
    let isArtifact: Bool
    let title: String
    let horizon: LineDetailFormat.HorizonLabel?
    let path: String?
    /// The note "Open in Obsidian" opens: the artifact's year note, or the parent note (S4-5).
    let note: NoteID?
  }

  /// One count of the subtitle; zero counts are left out, as on Lines.
  enum Count: Hashable {
    case projects(Int)
    case nextActions(Int)
  }

  let id: LineID
  let emoji: String?
  let name: String
  let block: String
  let state: LineState
  let isFoundation: Bool
  let budget: LinesFormat.Budget
  let last: LastActivity
  let counts: [Count]
  /// The weeks of the cards, oldest first; the last one is the current, partial week.
  let weeks: [Int]
  let rhythm: Metric
  let progress: Metric
  let projects: [ProjectRow]
  let nextActions: [ItemRow]
  let completions: [CompletionRow]
  /// Nil when the thread ends at the line.
  let parent: Parent?
  /// The first day of the current week, for the cards' `Mon–Thu`.
  let weekStart: Date?
  let today: Date
  let timeZone: TimeZone

  /// Nil for a line that is not in the overview.
  init?(_ overview: Overview, line id: LineID) {
    guard let detail = overview.lineDetail(id) else { return nil }
    let line = detail.line
    self.id = id
    emoji = line.emoji
    name = line.name
    block = line.block
    state = line.state
    isFoundation = line.foundation
    budget = LinesFormat.budget(line)
    last = detail.last
    projects = detail.projects.map {
      ProjectRow(
        id: $0.project.id, title: $0.project.title, kind: $0.kind, nextActions: $0.nextActions,
        remainingMinutes: $0.remainingMinutes)
    }
    let week = ISOWeek(containing: overview.now, calendar: overview.calendar)
      .horizon(calendar: overview.calendar)
    nextActions = detail.nextActions.map { item in
      ItemRow(
        id: item.task.id, title: item.task.title, project: item.project?.title,
        estimateMinutes: item.task.estimateMinutes,
        when: LineDetailFormat.when(
          item, now: overview.now, week: week, calendar: overview.calendar,
          defaultTimes: overview.workspace.defaultTimes))
    }
    completions = detail.completions.map {
      CompletionRow(
        id: $0.task.id, title: $0.task.title, completedAt: $0.completedAt, kind: $0.kind)
    }
    counts = [.projects(projects.count), .nextActions(nextActions.count)].filter {
      $0.value > 0
    }
    weeks = detail.weeks.map(\.week.week)
    rhythm = Metric(values: detail.weeks.map(\.counts.rhythm), average: detail.average.rhythm)
    progress = Metric(
      values: detail.weeks.map(\.counts.progress), average: detail.average.progress)
    let horizon = detail.targetNote.flatMap {
      LineDetailFormat.horizon($0.period, timeZone: overview.workspace.timeZone)
    }
    switch detail.target {
    case .artifact(let artifact):
      parent = Parent(
        isArtifact: true, title: artifact.title, horizon: horizon, path: detail.targetNote?.path,
        note: detail.targetNote?.id)
    case .note(let note):
      parent = Parent(
        isArtifact: false, title: note.title, horizon: horizon, path: note.path, note: note.id)
    case nil:
      parent = nil
    }
    weekStart = week?.start
    today = overview.now
    timeZone = overview.workspace.timeZone
  }
}

extension LineDetailScreen.Count {
  var value: Int {
    switch self {
    case .projects(let n), .nextActions(let n): n
    }
  }
}

/// Line detail's When column and the card's horizon, as values.
enum LineDetailFormat {
  enum When: Hashable {
    /// The due badge, amber only when urgent (CLAUDE.md rule 8); its time instead of the date
    /// for a due time today, as Today shows it (owner, 2026-11-16).
    case due(Date, urgent: Bool, showsTime: Bool)
    /// On Today's list by a date (`LineDetailItem.isToday`).
    case today
    /// Later this week: `Fri`.
    case weekday(Date)
    /// Any other placement: `12 Oct`.
    case date(Date)
    case none
  }

  /// A due date first, as Today shows it; then Today's rule; then the placement.
  static func when(
    _ item: LineDetailItem, now: Date, week: Horizon?, calendar: Calendar,
    defaultTimes: DefaultTimes
  ) -> When {
    if let due = item.task.effectiveDueAt {
      return .due(
        due, urgent: item.isUrgent,
        showsTime: TodayFormat.showsDueTime(
          dueHasTime: !defaultTimes.isDateOnly(due, kind: .due),
          dueIsToday: calendar.isDate(due, inSameDayAs: now)))
    }
    if item.isToday { return .today }
    guard let placement = item.placement else { return .none }
    if let week, week.contains(placement), placement > now { return .weekday(placement) }
    return .date(placement)
  }

  enum HorizonLabel: Hashable {
    case year(Int)
    case quarter(Int, year: Int)
  }

  /// A year or a quarter note's period; nil for the other scales.
  static func horizon(_ period: Horizon?, timeZone: TimeZone) -> HorizonLabel? {
    guard let period else { return nil }
    let calendar = TodayFormat.calendar(timeZone)
    let year = calendar.component(.year, from: period.start)
    switch period.scale {
    case .year: return .year(year)
    case .quarter:
      return .quarter((calendar.component(.month, from: period.start) - 1) / 3 + 1, year: year)
    default: return nil
    }
  }

  /// `Fri`.
  static func weekday(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.abbreviated))
  }

  /// `Mon–Thu`, the days of the current week so far; `Mon` on a Monday.
  static func daysSoFar(from start: Date, to today: Date, timeZone: TimeZone, locale: Locale)
    -> String
  {
    let first = weekday(start, timeZone: timeZone, locale: locale)
    if TodayFormat.calendar(timeZone).isDate(start, inSameDayAs: today) { return first }
    return "\(first)–\(weekday(today, timeZone: timeZone, locale: locale))"
  }

  /// `Wed 30 Sep`: a completion's day.
  static func completionDay(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    date.formatted(style(timeZone, locale).weekday(.abbreviated).day().month(.abbreviated))
  }

  private static func style(_ timeZone: TimeZone, _ locale: Locale) -> Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: TodayFormat.calendar(timeZone), timeZone: timeZone)
  }
}
