import Foundation
import MoonShineCore

/// What Week shows, as values (`design/screens/week.md`). Dates are formatted in `timeZone`,
/// the workspace's zone.
struct WeekScreen: Equatable {
  /// A task card: in a day column, or compact in the No plan tray.
  struct Card: Identifiable, Hashable {
    let id: TaskItemID
    let title: String
    let emoji: String?
    /// Nil for Life ops.
    let lineName: String?
    let estimateMinutes: Int?
    let due: Due?
    let isCompleted: Bool
  }

  /// A due date inside the week: amber only for a deadline (CLAUDE.md rule 8).
  struct Due: Hashable {
    let date: Date
    let hasTime: Bool
    let isDeadline: Bool
  }

  /// One term of a day's header; zero terms are left out (owner, 2026-11-27).
  enum Summary: Hashable {
    case done(Int)
    case estimate(Int)
  }

  struct Day: Identifiable, Hashable {
    let start: Date
    let isToday: Bool
    let isPast: Bool
    let cards: [Card]
    let summary: [Summary]
    var id: Date { start }

    /// More than this many cards end in `+ N more` (`week.md` § Layout).
    static let cardsShown = 6

    var shown: [Card] { Array(cards.prefix(Self.cardsShown)) }
    var more: [Card] { Array(cards.dropFirst(Self.cardsShown)) }
  }

  /// A line's cell in the strip.
  struct Cell: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
    let thisWeek: WeekCounts
    let average: WeekAverage
    let hasRhythm: Bool
    let hasProgress: Bool

    /// No completion in the store: the cell reads `no completions since …` (`copy.md`).
    var hasNoCompletions: Bool { !hasRhythm && !hasProgress }
  }

  let week: Int
  let firstDay: Date
  let lastDay: Date
  /// Today, the last day of the partial week's legend.
  let today: Date
  let cells: [Cell]
  let days: [Day]
  let noPlan: [Card]
  /// The start of the task provider's completion window, nil when not known.
  let completedSince: Date?
  let timeZone: TimeZone

  init(_ overview: Overview) {
    let week = overview.week()
    let workspace = overview.workspace
    let lines = Dictionary(
      workspace.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let defaultTimes = workspace.defaultTimes
    var range: DateInterval?
    if let first = week.days.first, let last = week.days.last {
      range = DateInterval(start: first.day.start, end: last.day.end)
    }

    func card(_ item: WeekItem) -> Card {
      var line: Line?
      if case .line(let id) = item.task.line { line = lines[id] }
      let due = item.task.effectiveDueAt.flatMap { date -> Due? in
        // Half-open, as Core's weeks: a due date at next Monday 00:00 is next week's.
        guard !item.isCompleted, let range, range.start <= date, date < range.end else {
          return nil
        }
        return Due(
          date: date, hasTime: !defaultTimes.isDateOnly(date, kind: .due),
          isDeadline: item.hasDueBadge)
      }
      return Card(
        id: item.task.id, title: item.task.title,
        emoji: line == nil ? "🧺" : line?.emoji,
        lineName: line?.name, estimateMinutes: item.task.estimateMinutes, due: due,
        isCompleted: item.isCompleted)
    }

    let todayStart = overview.calendar.startOfDay(for: overview.now)
    self.week = week.week.week
    firstDay = week.days.first?.day.start ?? todayStart
    lastDay = week.days.last?.day.start ?? todayStart
    today = overview.now
    cells = week.header.compactMap { header in
      guard case .line(let id) = header.line, let line = lines[id] else { return nil }
      return Cell(
        id: id, emoji: line.emoji, name: line.name, thisWeek: header.thisWeek,
        average: header.previousAverage, hasRhythm: header.hasRhythm,
        hasProgress: header.hasProgress)
    }
    days = week.days.map { day in
      let isToday = day.day.contains(overview.now)
      let isPast = day.day.end <= todayStart
      var summary: [Summary] = []
      if (isPast || isToday) && day.doneCount > 0 { summary.append(.done(day.doneCount)) }
      if !isPast && day.estimateMinutes > 0 { summary.append(.estimate(day.estimateMinutes)) }
      return Day(
        start: day.day.start, isToday: isToday, isPast: isPast, cards: day.items.map(card),
        summary: summary)
    }
    noPlan = week.noPlan.map(card)
    completedSince = workspace.completedSince
    timeZone = workspace.timeZone
  }
}
