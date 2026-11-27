import Foundation

/// A time of day, `HH:mm`.
public struct TimeOfDay: Hashable, Sendable {
  public let hour: Int
  public let minute: Int

  /// Nil outside 00:00–23:59.
  public init?(hour: Int, minute: Int) {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    self.hour = hour
    self.minute = minute
  }
}

/// OmniFocus' default times of day as the snapshot exports them, without a zone: a workspace
/// reads them in its own (`Workspace.defaultTimes`). A nil time is an absent setting.
public struct DefaultTimeSettings: Hashable, Sendable {
  public let due: TimeOfDay?
  public let `defer`: TimeOfDay?
  public let planned: TimeOfDay?

  public init(due: TimeOfDay? = nil, defer: TimeOfDay? = nil, planned: TimeOfDay? = nil) {
    self.due = due
    self.defer = `defer`
    self.planned = planned
  }
}

/// OmniFocus' default times (`docs/discovery/snapshot-contract.md` § Default times), in the
/// snapshot's time zone. A nil time is an absent setting: then only 00:00 counts as date only.
public struct DefaultTimes: Hashable, Sendable {
  public enum Kind: Sendable {
    case due, `defer`, planned
  }

  public let timeZone: TimeZone
  public let due: TimeOfDay?
  public let `defer`: TimeOfDay?
  public let planned: TimeOfDay?

  /// With no times, as when the snapshot has no `defaultTimes`.
  public init(
    timeZone: TimeZone, due: TimeOfDay? = nil, defer: TimeOfDay? = nil, planned: TimeOfDay? = nil
  ) {
    self.timeZone = timeZone
    self.due = due
    self.defer = `defer`
    self.planned = planned
  }

  public init(timeZone: TimeZone, _ settings: DefaultTimeSettings) {
    self.init(
      timeZone: timeZone, due: settings.due, defer: settings.defer, planned: settings.planned)
  }

  /// "A day, no particular time": the date's time in the snapshot's zone equals the default
  /// time of its kind, or 00:00 when that default is absent.
  public func isDateOnly(_ date: Date, kind: Kind) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
    let time: TimeOfDay? =
      switch kind {
      case .due: due
      case .defer: self.defer
      case .planned: planned
      }
    let expected = time ?? TimeOfDay(hour: 0, minute: 0)!
    return parts.hour == expected.hour && parts.minute == expected.minute && parts.second == 0
  }
}

/// The span of the day rail and of the free-time fact (Settings → Calendars), in minutes from
/// local midnight.
public struct DayWindow: Hashable, Sendable {
  public let startMinute: Int
  public let endMinute: Int

  public static let standard = DayWindow(startMinute: 8 * 60, endMinute: 22 * 60)!

  /// Nil unless `0 ≤ start < end ≤ 1440`.
  public init?(startMinute: Int, endMinute: Int) {
    guard 0 <= startMinute, startMinute < endMinute, endMinute <= 24 * 60 else { return nil }
    self.startMinute = startMinute
    self.endMinute = endMinute
  }

  /// The window on the day that holds `day`, by wall clock: 08:00–22:00 is 14 h on a
  /// daylight-saving day too; 24:00 is the end of the day, also where the next day starts at
  /// 01:00 (daylight saving at midnight).
  public func interval(on day: Date, calendar: Calendar) -> DateInterval {
    let midnight = calendar.startOfDay(for: day)
    func time(_ minute: Int) -> Date {
      if minute == 24 * 60 {
        return calendar.dateInterval(of: .day, for: day)?.end
          ?? midnight.addingTimeInterval(86_400)
      }
      return calendar.date(
        bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight)
        ?? midnight.addingTimeInterval(TimeInterval(minute * 60))
    }
    return DateInterval(start: time(startMinute), end: max(time(startMinute), time(endMinute)))
  }
}

/// Busy, planned and free time of one day (`design/screens/today.md` § Calendar). Whole
/// minutes: event and task bounds and "now" are floored to the minute before the union.
public struct DayLoad: Hashable, Sendable {
  public let window: DateInterval
  /// Event rows shown on the day (Show on, tentative and all-day included), identical copies as
  /// one; nil without access.
  public let eventCount: Int?
  /// The union of busy events inside the window; nil without access.
  public let inCalendarMinutes: Int?
  /// Planned-task time inside the window not covered by a busy event.
  public let plannedMinutes: Int
  /// The window minus busy and planned time; nil without access.
  public let freeWholeWindowMinutes: Int?
  /// From now to the window's end; the whole window before it opens; nil after it closes or
  /// without access.
  public let freeFromNowMinutes: Int?

  /// `tasks` are the counted tasks only: the Today list's tasks plus completed ones, without
  /// reminders (S4, ADR-0017). A task occupies `[planned, planned + estimate)` when its
  /// `effectivePlannedAt` is on the day (a task planned the day before that runs past midnight
  /// counts nothing; owner, 2026-10-17) and not date only and its estimate is above zero;
  /// children that inherit a timed parent overlap and count once.
  public static func compute(
    day: Date, now: Date, window: DayWindow, events: CalendarRead<[CalendarEvent]>,
    visibility: CalendarVisibility, tasks: [TaskItem],
    defaultTimes: DefaultTimes, calendar: Calendar
  ) -> DayLoad {
    let dayInterval =
      calendar.dateInterval(of: .day, for: day)
      ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
    let span = window.interval(on: day, calendar: calendar)

    let planned: [DateInterval] = tasks.compactMap { task in
      guard let at = task.effectivePlannedAt, at >= dayInterval.start, at < dayInterval.end,
        !defaultTimes.isDateOnly(at, kind: .planned), let estimate = task.estimateMinutes,
        estimate > 0
      else { return nil }
      let start = floorMinute(at)
      return clip(start, start.addingTimeInterval(TimeInterval(min(estimate, 24 * 60) * 60)), span)
    }

    guard let read = events.value else {
      return DayLoad(
        window: span, eventCount: nil, inCalendarMinutes: nil,
        plannedMinutes: minutes(union(planned)), freeWholeWindowMinutes: nil,
        freeFromNowMinutes: nil)
    }

    func setting(_ event: CalendarEvent) -> CalendarSetting {
      visibility.setting(for: event.calendarID, kind: event.calendarKind)
    }
    let shown = read.filter { $0.overlaps(dayInterval) && setting($0).show }
    let counts = { (event: CalendarEvent) in Self.counts(event, visibility) }
    let busy: [DateInterval] = shown.compactMap { event in
      guard counts(event) else { return nil }
      return clip(floorMinute(event.start), floorMinute(event.end), span)
    }

    let busyUnion = union(busy)
    let taken = union(busy + planned)
    let wholeFree = minutes([span]) - minutes(taken)
    let from = floorMinute(now)
    let freeFromNow: Int? =
      if from < span.start {
        wholeFree
      } else if from >= span.end {
        nil
      } else {
        minutes([DateInterval(start: from, end: span.end)])
          - minutes(
            taken.compactMap { clip($0.start, $0.end, DateInterval(start: from, end: span.end)) })
      }
    return DayLoad(
      window: span, eventCount: EventCopies.collapse(shown, counts: counts).count,
      inCalendarMinutes: minutes(busyUnion),
      plannedMinutes: minutes(taken) - minutes(busyUnion), freeWholeWindowMinutes: wholeFree,
      freeFromNowMinutes: freeFromNow)
  }

  /// A timed event that takes time, from a calendar that counts as busy.
  fileprivate static func counts(_ event: CalendarEvent, _ visibility: CalendarVisibility) -> Bool {
    !event.isAllDay && event.occupiesTime
      && visibility.setting(for: event.calendarID, kind: event.calendarKind).occupiesTime
  }

  fileprivate static func floorMinute(_ date: Date) -> Date {
    Date(
      timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    )
  }

  /// `[start, end)` cut to `span`; nil when nothing of it is inside.
  fileprivate static func clip(_ start: Date, _ end: Date, _ span: DateInterval) -> DateInterval? {
    let from = max(start, span.start)
    let to = min(end, span.end)
    return from < to ? DateInterval(start: from, end: to) : nil
  }

  /// Disjoint intervals covering the same time; overlaps count once.
  private static func union(_ intervals: [DateInterval]) -> [DateInterval] {
    var merged: [DateInterval] = []
    for interval in intervals.sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, interval.start <= last.end {
        merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
      } else {
        merged.append(interval)
      }
    }
    return merged
  }

  /// Total length of disjoint intervals in whole minutes.
  private static func minutes(_ intervals: [DateInterval]) -> Int {
    Int((intervals.reduce(0) { $0 + $1.duration } / 60).rounded(.down))
  }
}

/// The Day section of Today's rail (`design/screens/today.md` § Calendar): the day's events of
/// Show-on calendars and its tasks with a time, each on the window's timeline or pinned above or
/// below it. Times are floored to the minute, as in `DayLoad`.
public struct DayRail: Hashable, Sendable {
  public struct Mark: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
      /// A timed event; a tentative one is drawn hatched.
      case event(CalendarEvent)
      /// A task with a planned time: `[planned, planned + estimate)`, no length without one.
      case planned(TaskItem)
      /// A task with a due time on the day: an instant.
      case due(TaskItem, isDeadline: Bool)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    /// An event or an estimated task: it has a length.
    public var isSpan: Bool { end > start }
  }

  public let load: DayLoad
  /// All-day events of Show-on calendars, as one-line rows above the timeline (owner, 2026-10-30).
  public let allDay: [CalendarEvent]
  /// Before the window's start; time order.
  public let above: [Mark]
  /// On the timeline, in time order; an item that crosses an edge is here.
  public let marks: [Mark]
  /// At or after the window's end; time order.
  public let below: [Mark]
  /// How many identical events a shown event stands for, where more than one.
  public let copies: [CalendarEvent: Int]

  /// 1 for an event that stands for itself alone.
  public func copies(of event: CalendarEvent) -> Int { copies[event] ?? 1 }

  /// `tasks` as for `DayLoad.compute`; `deadlines` are the tasks whose due mark is amber.
  public static func compute(
    day: Date, now: Date, window: DayWindow, events: CalendarRead<[CalendarEvent]>,
    visibility: CalendarVisibility, tasks: [TaskItem], deadlines: Set<TaskItemID>,
    defaultTimes: DefaultTimes, calendar: Calendar
  ) -> DayRail {
    let load = DayLoad.compute(
      day: day, now: now, window: window, events: events, visibility: visibility, tasks: tasks,
      defaultTimes: defaultTimes, calendar: calendar)
    let dayInterval =
      calendar.dateInterval(of: .day, for: day)
      ?? DateInterval(start: calendar.startOfDay(for: day), duration: 86_400)
    let span = load.window
    func onDay(_ date: Date) -> Bool { date >= dayInterval.start && date < dayInterval.end }

    let rows = EventCopies.collapse(
      (events.value ?? []).filter {
        $0.overlaps(dayInterval)
          && visibility.setting(for: $0.calendarID, kind: $0.calendarKind).show
      }, counts: { DayLoad.counts($0, visibility) })
    let shown = rows.map(\.event)
    var items: [Mark] = shown.filter { !$0.isAllDay }.map {
      Mark(kind: .event($0), start: DayLoad.floorMinute($0.start), end: DayLoad.floorMinute($0.end))
    }
    for item in tasks {
      if let at = item.effectivePlannedAt, onDay(at), !defaultTimes.isDateOnly(at, kind: .planned) {
        let start = DayLoad.floorMinute(at)
        let minutes = min(max(item.estimateMinutes ?? 0, 0), 24 * 60)
        items.append(
          Mark(
            kind: .planned(item), start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60))))
      }
      if let due = item.effectiveDueAt, onDay(due), !defaultTimes.isDateOnly(due, kind: .due) {
        let at = DayLoad.floorMinute(due)
        items.append(
          Mark(kind: .due(item, isDeadline: deadlines.contains(item.id)), start: at, end: at))
      }
    }
    // Time order; the same start keeps input order (events first).
    let ordered = items.enumerated().sorted {
      $0.element.start != $1.element.start
        ? $0.element.start < $1.element.start : $0.offset < $1.offset
    }.map(\.element)

    // Over before the window opens (an instant at its start is on the timeline); from its end on.
    let isAbove = { (mark: Mark) in mark.start < span.start && mark.end <= span.start }
    return DayRail(
      load: load, allDay: shown.filter(\.isAllDay), above: ordered.filter(isAbove),
      marks: ordered.filter { !isAbove($0) && $0.start < span.end },
      below: ordered.filter { !isAbove($0) && $0.start >= span.end },
      copies: Dictionary(
        rows.filter { $0.copies > 1 }.map { ($0.event, $0.copies) },
        uniquingKeysWith: { first, _ in first }))
  }
}

/// Events with the same title, start, end and all-day flag, whatever their calendar, are one
/// row (owner, 2026-11-27): an account that copies one meeting into a calendar three times shows
/// it once. EventKit gives events in no set order, so the copy that stands for the others is
/// chosen, not found first: one that counts as busy, then one drawn normal, then by calendar
/// and event id. The busy union still takes every copy.
private struct EventCopies {
  var event: CalendarEvent
  var copies: Int

  private struct Key: Hashable {
    let title: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
  }

  /// `counts`: the event takes busy time (its own rule and its calendar's).
  static func collapse(_ events: [CalendarEvent], counts: (CalendarEvent) -> Bool)
    -> [EventCopies]
  {
    var rows: [EventCopies] = []
    var index: [Key: Int] = [:]
    for event in events {
      let key = Key(
        title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay)
      if let row = index[key] {
        rows[row].copies += 1
        if precedes(event, rows[row].event, counts) { rows[row].event = event }
      } else {
        index[key] = rows.count
        rows.append(EventCopies(event: event, copies: 1))
      }
    }
    return rows
  }

  private static func precedes(
    _ a: CalendarEvent, _ b: CalendarEvent, _ counts: (CalendarEvent) -> Bool
  ) -> Bool {
    func rank(_ event: CalendarEvent) -> (Int, Int) {
      (counts(event) ? 0 : 1, event.display == .normal ? 0 : 1)
    }
    if rank(a) != rank(b) { return rank(a) < rank(b) }
    if a.calendarID.rawValue != b.calendarID.rawValue {
      return a.calendarID.rawValue < b.calendarID.rawValue
    }
    return a.id < b.id
  }
}

/// The compressed timeline of the Day rail (`design/screens/day-rail-dense.md`, direction 1,
/// owner 2026-11-17 and 2026-11-21): the rail's marks as full-width rows in time order; an empty
/// stretch of more than an hour is one gap. Positions are points down from the window's start
/// line.
public struct DayTimeline: Hashable, Sendable {
  /// The design's sizes, in points (`day-rail-dense.md` § Components and tokens).
  public struct Metrics: Hashable, Sendable {
    public let pointsPerHour: Double
    public let row: Double
    public let rowSpacing: Double
    public let gap: Double
    public let gapWithNow: Double
    public let gapSpacing: Double
    public let nowSlot: Double
    public let longestDrawn: TimeInterval
    /// The least block height that shows its end time.
    public let blockEndLabel: Double
    /// Where the gutter's times are drawn, as the view draws them: a row's start from its top,
    /// a block's end from its top, each `timeLabel` high; a line's end and the window's edges
    /// centred on their place, `edgeLabelHalf` either way; the now label centred on now.
    public let startLabelTop: Double
    public let endLabelTop: Double
    public let timeLabel: Double
    public let edgeLabelHalf: Double
    public let nowLabelHalf: Double

    public static let standard = Metrics(
      pointsPerHour: 30, row: 22, rowSpacing: 2, gap: 18, gapWithNow: 40, gapSpacing: 4,
      nowSlot: 24, longestDrawn: 3600, blockEndLabel: 34, startLabelTop: 4, endLabelTop: 18,
      timeLabel: 13, edgeLabelHalf: 6, nowLabelHalf: 12)
  }

  public struct Row: Hashable, Sendable {
    public let mark: DayRail.Mark
    public let top: Double
    public let height: Double
    /// An outer span with no row inside, drawn for its duration.
    public let isBlock: Bool
    /// Its range in the row: a span inside another, or a row that began before the window.
    public let showsRange: Bool
    /// Its start in the gutter: not for a due row, a row that began before the window, or a time
    /// the now label covers (owner, 2026-11-21).
    public let showsStart: Bool
    /// A block's end time under its start.
    public let showsEnd: Bool
    /// An outer span's duration line, when rows are inside it.
    public let line: Line?
    /// The marks inside an outer span, in time order.
    public let inside: [DayRail.Mark]
  }

  /// To the latest end of every span that starts inside the outer one (owner, 2026-11-21).
  public struct Line: Hashable, Sendable {
    public let end: Double
    /// Its end time in the gutter; nil where the line ends at a gap or at the window's end, or
    /// where the now label covers it.
    public let endTime: Date?
  }

  public struct Gap: Hashable, Sendable {
    public let from: Date
    public let to: Date
    public let top: Double
    public let height: Double
  }

  public enum Item: Hashable, Sendable {
    case row(Row)
    case gap(Gap)
  }

  /// Where now is drawn (owner, 2026-11-20); its label is always in the gutter, centred on `y`.
  public struct Now: Hashable, Sendable {
    public enum Place: Hashable, Sendable {
      /// In a gap, which grows to `gapWithNow`; a line across the rows.
      case gap
      /// In a slot of its own after a row, or under the start line; a line across the rows.
      case slot
      /// A dot on an ongoing span's duration line.
      case line
      /// A dot on an ongoing block's edge.
      case block
    }

    public let place: Place
    public let y: Double
    /// The span still running at now; the outer one when several are (owner, 2026-11-21).
    public let during: DayRail.Mark?
  }

  public let items: [Item]
  /// From the window's start line to its end line.
  public let height: Double
  /// Nil outside the window.
  public let now: Now?
  /// The window's start and end times at its lines; each gives way to the now label.
  public let showsStartEdge: Bool
  public let showsEndEdge: Bool

  public var gaps: [Gap] { items.compactMap { if case .gap(let gap) = $0 { gap } else { nil } } }

  /// The rules of `day-rail-dense.md` § Layout:
  /// - a row starts its top time (its start, or the window's start when it began before) after
  ///   the previous row's at 30 pt/h, but never closer than 2 pt below the item above;
  /// - a span is an event or an estimated task; a row that starts before an outer span's reach
  ///   (the latest end of it and of every span starting inside it) is inside it; an outer span
  ///   with no row inside is a block of its duration, at least 22; one with rows inside is a
  ///   one-line row with a duration line; a span inside another shows its range, with no line;
  /// - a stretch no mark covers that is longer than an hour is a gap, 6 pt below the row above
  ///   (its 2-pt spacing and 4) and 4 pt above the next (none at the start line); an hour or
  ///   less stays to scale;
  /// - a gutter time the now label covers gives way (owner, 2026-11-21).
  public static func layout(_ rail: DayRail, now: Date, metrics m: Metrics = .standard)
    -> DayTimeline
  {
    let window = rail.load.window
    let marks = rail.marks
    let rate = m.pointsPerHour / 3600
    func top(_ index: Int) -> Date { max(marks[index].start, window.start) }

    // Who is inside whom, by time alone.
    var outer: [Int?] = Array(repeating: nil, count: marks.count)
    var reach: [Int: Date] = [:]
    var open: Int?
    for index in marks.indices {
      if let span = open, let until = reach[span], top(index) < until {
        outer[index] = span
        if marks[index].isSpan { reach[span] = max(until, marks[index].end) }
      } else {
        open = marks[index].isSpan ? index : nil
        if marks[index].isSpan { reach[index] = marks[index].end }
      }
    }
    func members(_ span: Int) -> [Int] { marks.indices.filter { outer[$0] == span } }
    let isBlock = marks.indices.map { outer[$0] == nil && marks[$0].isSpan && members($0).isEmpty }

    // The empty stretches over an hour, and the order of gaps and rows.
    var gapBefore: [(from: Date, to: Date)?] = Array(repeating: nil, count: marks.count)
    var latest = window.start
    for index in marks.indices {
      if top(index).timeIntervalSince(latest) > m.longestDrawn {
        gapBefore[index] = (latest, top(index))
      }
      latest = max(latest, marks[index].end, top(index))
    }
    let closing: (from: Date, to: Date)? =
      window.end.timeIntervalSince(latest) > m.longestDrawn ? (latest, window.end) : nil

    // Where now falls, before any position is known.
    enum Place {
      case span(Int)
      case gap(Date)
      case slot(after: Int?)
    }
    var place: Place?
    if window.start <= now && now < window.end {
      if let span = marks.indices.first(where: {
        outer[$0] == nil && marks[$0].isSpan && marks[$0].start <= now && now < (reach[$0] ?? now)
      }) {
        place = .span(span)
      } else if let gap = (gapBefore.compactMap { $0 } + [closing].compactMap { $0 })
        .first(where: { $0.from <= now && now < $0.to })
      {
        place = .gap(gap.from)
      } else {
        place = .slot(after: marks.indices.last { top($0) <= now })
      }
    }
    let during: DayRail.Mark? = {
      guard case .span(let span) = place else { return nil }
      let running = ([span] + members(span)).filter {
        marks[$0].isSpan && marks[$0].start <= now && now < marks[$0].end
      }
      return running.first.map { marks[$0] }
    }()

    // Positions, in the order the items are drawn.
    enum Placed {
      case gap(Gap)
      case row(Int)
    }
    var placed: [Placed] = []
    var tops: [Double] = Array(repeating: 0, count: marks.count)
    var heights: [Double] = Array(repeating: 0, count: marks.count)
    var cursor = 0.0
    var anchor = (time: window.start, y: 0.0)
    var nowY: Double?
    var lineEnds: [Int: Double] = [:]
    /// Now's slot after a row inside a span that has ended: it waits for the span's line.
    var slotAfterLine = false

    func addGap(_ from: Date, _ to: Date) {
      let holdsNow: Bool = if case .gap(let start) = place { start == from } else { false }
      let gapTop = placed.isEmpty && cursor == 0 ? 0 : cursor + m.gapSpacing
      let height = holdsNow ? m.gapWithNow : m.gap
      placed.append(.gap(Gap(from: from, to: to, top: gapTop, height: height)))
      if holdsNow {
        let share = now.timeIntervalSince(from) / to.timeIntervalSince(from)
        nowY = gapTop + m.gap + share * (m.gapWithNow - m.gap)
      }
      cursor = gapTop + height + m.gapSpacing
    }
    func addSlot() {
      let slotTop = cursor
      nowY = slotTop + m.nowSlot / 2
      cursor = slotTop + m.nowSlot + m.rowSpacing
    }
    /// The end of the outer span `span`'s line, once its last row is placed.
    func close(_ span: Int) {
      guard let last = members(span).last, let until = reach[span] else { return }
      let rest = min(until, window.end).timeIntervalSince(top(last))
      let end = max(tops[last] + heights[last], tops[last] + rest * rate)
      lineEnds[span] = end
      cursor = max(cursor, end)
      if slotAfterLine {
        // Below the line and its end time.
        cursor = max(cursor, end + m.edgeLabelHalf + m.rowSpacing)
        addSlot()
        slotAfterLine = false
      }
    }

    if case .slot(after: nil) = place { addSlot() }
    var group: Int?
    for index in marks.indices {
      if outer[index] == nil, let span = group {
        close(span)
        group = nil
      }
      let y: Double
      if let gap = gapBefore[index] {
        addGap(gap.from, gap.to)
        y = cursor
      } else {
        y = max(cursor, anchor.y + top(index).timeIntervalSince(anchor.time) * rate)
      }
      let length = min(marks[index].end, window.end).timeIntervalSince(top(index))
      let height = isBlock[index] ? max(length * rate, m.row) : m.row
      tops[index] = y
      heights[index] = height
      placed.append(.row(index))
      cursor = y + height + m.rowSpacing
      anchor = (top(index), y)
      if outer[index] == nil, !members(index).isEmpty { group = index }
      if case .slot(after: index) = place {
        if outer[index] == nil { addSlot() } else { slotAfterLine = true }
      }
    }
    if let span = group { close(span) }
    let height: Double
    if let closing {
      addGap(closing.from, closing.to)
      height = cursor
    } else {
      let lastBottom = marks.indices.last.map { tops[$0] + heights[$0] } ?? 0
      height = max(
        anchor.y + window.end.timeIntervalSince(anchor.time) * rate, lastBottom,
        lineEnds.values.max() ?? 0, nowY.map { $0 + m.nowSlot / 2 } ?? 0)
    }

    if case .span(let span) = place {
      if isBlock[span] {
        // Over the part drawn: from the window's start to its end at most.
        let drawn = min(marks[span].end, window.end).timeIntervalSince(top(span))
        let share = drawn > 0 ? now.timeIntervalSince(top(span)) / drawn : 0
        nowY = tops[span] + share * heights[span]
      } else if let end = lineEnds[span], let until = reach[span] {
        // Along the line: its top, each row inside, its end.
        let points =
          [(top(span), tops[span])] + members(span).map { (top($0), tops[$0]) }
          + [(min(until, window.end), end)]
        let after = points.lastIndex { $0.0 <= now } ?? 0
        let (from, to) = (points[after], points[min(after + 1, points.count - 1)])
        let length = to.0.timeIntervalSince(from.0)
        nowY = from.1 + (length > 0 ? now.timeIntervalSince(from.0) / length : 0) * (to.1 - from.1)
      }
    }

    // The rows, with what the gutter shows.
    let gapStarts = Set((gapBefore.compactMap { $0 } + [closing].compactMap { $0 }).map(\.from))
    /// The now label covers a gutter time drawn from `from` to `to`.
    func covered(_ from: Double, _ to: Double) -> Bool {
      guard let y = nowY else { return false }
      return from < y + m.nowLabelHalf && to > y - m.nowLabelHalf
    }
    func row(_ index: Int) -> Row {
      let mark = marks[index]
      let isDue: Bool = if case .due = mark.kind { true } else { false }
      let startLabel = tops[index] + m.startLabelTop
      let endLabel = tops[index] + m.endLabelTop
      let nowInBlock: Bool = if case .span(index) = place { true } else { false }
      let line = lineEnds[index].map { end in
        let until = reach[index] ?? mark.end
        let shown =
          until < window.end && !gapStarts.contains(until)
          && !covered(end - m.edgeLabelHalf, end + m.edgeLabelHalf)
        return Line(end: end, endTime: shown ? until : nil)
      }
      return Row(
        mark: mark, top: tops[index], height: heights[index], isBlock: isBlock[index],
        showsRange: outer[index] != nil && mark.isSpan || mark.start < window.start,
        showsStart: !isDue && mark.start >= window.start
          && !covered(startLabel, startLabel + m.timeLabel),
        showsEnd: isBlock[index] && heights[index] >= m.blockEndLabel && mark.end <= window.end
          && !nowInBlock && !covered(endLabel, endLabel + m.timeLabel),
        line: line, inside: members(index).map { marks[$0] })
    }
    let items: [Item] = placed.map {
      switch $0 {
      case .gap(let gap): .gap(gap)
      case .row(let index): .row(row(index))
      }
    }

    let nowMark = nowY.map { y -> Now in
      let kind: Now.Place =
        switch place {
        case .span(let span): isBlock[span] ? .block : .line
        case .gap: .gap
        case .slot, nil: .slot
        }
      return Now(place: kind, y: y, during: during)
    }
    return DayTimeline(
      items: items, height: height, now: nowMark,
      showsStartEdge: !covered(-m.edgeLabelHalf, m.edgeLabelHalf),
      showsEndEdge: !covered(height - m.edgeLabelHalf, height + m.edgeLabelHalf))
  }
}
