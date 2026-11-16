import MoonShineCore
import MoonShineFixtures
import SwiftUI

/// The calendar the Day rail reads, set by `RootView` from the app's source.
struct DayRailInput {
  let events: CalendarRead<[CalendarEvent]>
  let visibility: CalendarVisibility
  /// For the bar colours.
  let calendars: [CalendarInfo]
  /// Demo's clock stands still at the overview's `now`; Live's runs.
  let isFrozen: Bool

  /// The fixture calendar's week, read here until S4-3d moves the read behind the calendar
  /// provider (owner, 2026-11-16).
  static let demo = DayRailInput(
    events: .read(DemoCalendar.events, skipped: 0), visibility: DemoCalendar.visibility,
    calendars: DemoCalendar.calendars, isFrozen: true)

  /// No calendar read before S4-3d: the rail shows the tasks with a time and no calendar fact.
  static let live = DayRailInput(
    events: .unavailable(.notDetermined), visibility: CalendarVisibility(), calendars: [],
    isFrozen: false)
}

extension EnvironmentValues {
  @Entry var dayRailInput = DayRailInput.live
}

extension DayRail {
  /// Absent with no calendar fact and no task with a time today (`today.md` § Calendar).
  var isShown: Bool {
    load.eventCount != nil || !(above.isEmpty && marks.isEmpty && below.isEmpty)
  }
}

/// The Day section at the top of Today's rail: `design/screens/today.md` § Calendar,
/// `design/components.md` § Day rail marks. Read only: a task mark selects its row in the list;
/// opening a task in OmniFocus comes with the link opener (S4-5).
struct DayRailView: View {
  let rail: DayRail
  let now: Date
  let screen: TodayScreen
  let calendars: [CalendarInfo]
  /// A click on a task mark: the list selects its row.
  let reveal: (TaskItemID) -> Void
  @Environment(\.locale) private var locale

  static let hourHeight: CGFloat = 26
  static let labelWidth: CGFloat = 40

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Day").font(.system(size: 12, weight: .semibold))
        if let facts = DayFactText.joined(
          facts.filter(\.isCalendar), timeZone: zone, locale: locale)
        {
          facts.foregroundStyle(.secondary)
        }
      }
      ForEach(rail.allDay) { event in
        HStack(spacing: 6) {
          CalendarBar(color: color(event))
          title(event)
          Text("all day").foregroundStyle(.tertiary)
        }
        .frame(height: 16)
        .lineLimit(1)
      }
      ForEach(Array(rail.above.enumerated()), id: \.offset) { pinned($0.element) }
      scale
      ForEach(Array(rail.below.enumerated()), id: \.offset) { pinned($0.element) }
      VStack(alignment: .leading, spacing: 2) {
        if let facts = DayFactText.joined(
          facts.filter { !$0.isCalendar }, timeZone: zone, locale: locale)
        {
          facts
        }
        Text("day window \(hour(rail.load.window.start))–\(hour(rail.load.window.end))")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    }
    .font(.system(size: 10.5))
    .accessibilityElement(children: .contain)
  }

  private var zone: TimeZone { screen.timeZone }
  private var facts: [DayFact] { TodayFormat.dayFact(rail.load) }
  private var window: DateInterval { rail.load.window }

  private var scale: some View {
    let height = y(window.end)
    return GeometryReader { geometry in
      let lane = max(geometry.size.width - Self.labelWidth, 0)
      ZStack(alignment: .topLeading) {
        ForEach(ticks, id: \.self) { tick in
          Text(verbatim: TodayFormat.time(tick, timeZone: zone, locale: locale))
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .offset(y: y(tick) - 6)
          Rectangle()
            .fill(Tokens.cardBorder)
            .frame(width: lane, height: 1)
            .offset(x: Self.labelWidth, y: y(tick))
        }
        ForEach(Array(rail.marks.enumerated()), id: \.offset) { _, mark in
          placed(mark, lane: lane)
        }
        if window.contains(now) && now < window.end {
          HStack(spacing: 4) {
            Text("now \(TodayFormat.time(now, timeZone: zone, locale: locale))")
              .font(.system(size: 10, weight: .semibold))
              .monospacedDigit()
            Rectangle().frame(height: 1)
          }
          .foregroundStyle(Color.accentColor)
          .offset(y: y(now) - 6)
          .zIndex(2)
          .accessibilityHidden(true)
        }
      }
    }
    .frame(height: height)
    .accessibilityElement(children: .contain)
  }

  /// Every two hours from the window's start, its end included.
  private var ticks: [Date] {
    stride(from: 0, through: Int(window.duration / 3600), by: 2).compactMap {
      screen.calendar.date(byAdding: .hour, value: $0, to: window.start)
    }.filter { $0 <= window.end }
  }

  private func y(_ date: Date) -> CGFloat {
    CGFloat(date.timeIntervalSince(window.start) / 3600) * Self.hourHeight
  }

  @ViewBuilder private func placed(_ mark: DayRail.Mark, lane: CGFloat) -> some View {
    let x = Self.labelWidth + lane * mark.leading
    let width = max(lane * mark.width - 2, 0)
    let top = y(max(mark.start, window.start))
    let bottom = y(min(mark.end, window.end))
    switch mark.kind {
    case .event(let event):
      MarkLabel(
        mark: mark, now: now, zone: zone, emoji: nil, color: color(event), reveal: reveal
      )
      .frame(width: width, height: max(bottom - top, 12), alignment: .topLeading)
      .offset(x: x, y: top)
    case .planned:
      MarkLabel(mark: mark, now: now, zone: zone, emoji: emoji(mark), color: nil, reveal: reveal)
        .frame(width: width, height: max(bottom - top, 14), alignment: .topLeading)
        .offset(x: x, y: top)
    case .due:
      MarkLabel(mark: mark, now: now, zone: zone, emoji: emoji(mark), color: nil, reveal: reveal)
        .frame(width: width, height: 13, alignment: .leading)
        .offset(x: x, y: top - 6.5)
        .zIndex(1)
    }
  }

  private func pinned(_ mark: DayRail.Mark) -> some View {
    let color: Color? = if case .event(let event) = mark.kind { color(event) } else { nil }
    return MarkLabel(
      mark: mark, now: now, zone: zone, emoji: emoji(mark), color: color, reveal: reveal
    )
    .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
  }

  private func emoji(_ mark: DayRail.Mark) -> String? {
    switch mark.kind {
    case .event: nil
    case .planned(let item), .due(let item, _): screen.emoji[item.id]
    }
  }

  private func color(_ event: CalendarEvent) -> Color {
    Tokens.calendar(calendars.first { $0.id == event.calendarID }?.colorHex)
  }

  private func title(_ event: CalendarEvent) -> Text {
    event.title.map { Text(verbatim: $0) } ?? Text("Busy")
  }

  private func hour(_ date: Date) -> String {
    TodayFormat.hour(date, timeZone: zone, locale: locale)
  }
}

/// One mark, on the scale or pinned: an event block, a timed task block or a due mark.
private struct MarkLabel: View {
  let mark: DayRail.Mark
  let now: Date
  let zone: TimeZone
  let emoji: String?
  /// The calendar's colour, for an event.
  let color: Color?
  let reveal: (TaskItemID) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    switch mark.kind {
    case .event(let event):
      HStack(alignment: .top, spacing: 4) {
        CalendarBar(color: color ?? Tokens.paused)
        Text(verbatim: time)
          .monospacedDigit()
          .foregroundStyle(.secondary)
        title(event)
      }
      .lineLimit(1)
      .padding(.trailing, 4)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Tokens.chipFill)
      .overlay {
        if event.display == .tentative { Hatch().stroke(Tokens.cardBorder, lineWidth: 1) }
      }
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .opacity(mark.end <= now ? 0.5 : 1)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(eventReading(event))
    case .planned(let item):
      Button {
        reveal(item.id)
      } label: {
        HStack(alignment: .top, spacing: 4) {
          Checkbox(isDone: item.status == .completed).imageScale(.small)
          Text(verbatim: time).monospacedDigit()
          Text(verbatim: item.title).strikethrough(item.status == .completed)
          Spacer(minLength: 0)
          if let emoji { Text(verbatim: emoji) }
        }
        .lineLimit(1)
        .padding(.horizontal, 3)
        .foregroundStyle(item.status == .completed ? Tokens.doneText : Color.primary)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Tokens.checkboxStroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(taskReading(Text(verbatim: time), item, estimate: true))
    case .due(let item, let isDeadline):
      Button {
        reveal(item.id)
      } label: {
        HStack(spacing: 4) {
          Rectangle()
            .fill(isDeadline ? AnyShapeStyle(Tokens.dueText) : AnyShapeStyle(.tertiary))
            .frame(width: 3)
          Checkbox(isDone: item.status == .completed).imageScale(.small)
          due(isDeadline)
          Text(verbatim: item.title)
          Spacer(minLength: 0)
          if let emoji { Text(verbatim: emoji) }
        }
        .lineLimit(1)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(taskReading(due(isDeadline), item, estimate: false))
    }
  }

  private var time: String { TodayFormat.time(mark.start, timeZone: zone, locale: locale) }

  private func due(_ isDeadline: Bool) -> Text {
    isDeadline
      ? Text("Due \(time)").fontWeight(.semibold).foregroundStyle(Tokens.dueText)
      : Text("due \(time)").foregroundStyle(.secondary)
  }

  private func title(_ event: CalendarEvent) -> Text {
    event.title.map { Text(verbatim: $0) } ?? Text("Busy")
  }

  /// "17:00, Violin lesson, event, in 40 minutes" (`today.md` § Calendar, SwiftUI).
  private func eventReading(_ event: CalendarEvent) -> Text {
    let reading = Text("\(time), \(title(event)), event")
    let minutes = Int(mark.start.timeIntervalSince(now) / 60)
    guard mark.start > now, minutes > 0 else { return reading }
    return Text("\(reading), \(Text("in \(minutes) minutes"))")
  }

  /// "20:30, Allemande…, task, estimate 45 minutes, not completed".
  private func taskReading(_ when: Text, _ item: TaskItem, estimate: Bool) -> Text {
    var reading = Text("\(when), \(Text(verbatim: item.title)), task")
    if estimate, let minutes = item.estimateMinutes, minutes > 0 {
      reading = Text("\(reading), \(Text("estimate \(minutes) minutes"))")
    }
    let state = item.status == .completed ? Text("Completed") : Text("Not completed")
    return Text("\(reading), \(state)")
  }
}

/// The 3 pt leading bar in a calendar's colour (`design/components.md` § CalendarDot).
private struct CalendarBar: View {
  let color: Color

  var body: some View {
    Rectangle().fill(color).frame(width: 3)
  }
}

/// Diagonal lines over a tentative event.
private struct Hatch: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    var x = rect.minX - rect.height
    while x < rect.maxX {
      path.move(to: CGPoint(x: x, y: rect.maxY))
      path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
      x += 6
    }
    return path
  }
}

/// Day-fact terms in the catalog's words, joined with ` · `.
enum DayFactText {
  static func joined(_ facts: [DayFact], timeZone: TimeZone, locale: Locale) -> Text? {
    let terms = facts.map { text($0, timeZone: timeZone, locale: locale) }
    guard let first = terms.first else { return nil }
    return terms.dropFirst().reduce(first) { Text("\($0) · \($1)") }
  }

  static func text(_ fact: DayFact, timeZone: TimeZone, locale: Locale) -> Text {
    switch fact {
    case .events(let count): Text("\(count) events")
    case .noEvents: Text("No events today")
    case .inCalendar(let length): Text("\(duration(length)) in calendar")
    case .planned(let length): Text("\(duration(length)) planned")
    case .free(let length, let end):
      Text(
        "≈ \(duration(length)) free until \(TodayFormat.time(end, timeZone: timeZone, locale: locale))"
      )
    }
  }

  static func duration(_ length: TodayFormat.Estimate) -> Text {
    switch length {
    case .minutes(let minutes): Text("\(minutes) min")
    case .hours(let hours): Text("\(hours) h")
    case .hoursAndMinutes(let hours, let minutes): Text("\(hours) h \(minutes) min")
    }
  }
}
