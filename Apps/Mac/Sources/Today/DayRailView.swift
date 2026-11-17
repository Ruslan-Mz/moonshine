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

  nonisolated static let hourHeight: CGFloat = 26
  static let labelWidth: CGFloat = 40
  /// Between marks side by side.
  nonisolated static let gap: CGFloat = 2
  /// Half the height of the two-line now label.
  static let nowHalf: CGFloat = 12

  /// The least heights of the marks (`design/components.md` § Day rail marks).
  enum Height {
    static let event: CGFloat = 12
    static let planned: CGFloat = 14
    static let due: CGFloat = 13
  }

  /// The heights as time on the scale, which the column rule reserves (owner, 2026-11-17).
  nonisolated static let footprint = DayRail.Footprint(
    event: seconds(Height.event), planned: seconds(Height.planned), due: seconds(Height.due))

  private nonisolated static func seconds(_ height: CGFloat) -> TimeInterval {
    TimeInterval(height / hourHeight) * 3600
  }

  /// The narrowest readable column as a fraction of `lane`: the token and the gap; 0 (nothing
  /// collapses) before the lane has a width.
  nonisolated static func minimumWidth(lane: CGFloat) -> Double {
    lane > 0 ? Double((Tokens.railReadableWidth + gap) / lane) : 0
  }

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
  private var dayStart: Date { screen.calendar.startOfDay(for: screen.day) }
  private var facts: [DayFact] { TodayFormat.dayFact(rail.load) }
  private var window: DateInterval { rail.load.window }

  private var scale: some View {
    let height = y(window.end)
    return GeometryReader { geometry in
      let lane = max(geometry.size.width - Self.labelWidth, 0)
      ZStack(alignment: .topLeading) {
        ForEach(ticks, id: \.self) { tick in
          if !hidesTick(tick, height: height) {
            Text(verbatim: TodayFormat.time(tick, timeZone: zone, locale: locale))
              .font(.system(size: 10))
              .monospacedDigit()
              .foregroundStyle(.tertiary)
              .offset(y: y(tick) - 6)
          }
          Rectangle()
            .fill(Tokens.cardBorder)
            .frame(width: lane, height: 1)
            .offset(x: Self.labelWidth, y: y(tick))
        }
        // Behind the marks, its label in the gutter (owner, 2026-11-17).
        if showsNow { nowRule(lane: lane, height: height) }
        let layout = rail.layout(minimumWidth: Self.minimumWidth(lane: lane))
        ForEach(Array(layout.enumerated()), id: \.offset) { _, item in
          switch item {
          case .mark(let mark): placed(mark, lane: lane)
          case .block(let block): placed(block, lane: lane)
          }
        }
      }
    }
    // Room for a mark that hangs past the window's end.
    .frame(height: height + Height.planned, alignment: .top)
    .accessibilityElement(children: .contain)
  }

  private var showsNow: Bool { window.contains(now) && now < window.end }

  /// The now label's centre, kept inside the scale.
  private func nowCentre(height: CGFloat) -> CGFloat {
    min(max(y(now), Self.nowHalf), max(height - Self.nowHalf, Self.nowHalf))
  }

  /// A tick label the now label would cover is not drawn.
  private func hidesTick(_ tick: Date, height: CGFloat) -> Bool {
    showsNow && abs(y(tick) - nowCentre(height: height)) < Self.nowHalf + 6
  }

  private func nowRule(lane: CGFloat, height: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        Text("now")
        Text(verbatim: TodayFormat.time(now, timeZone: zone, locale: locale)).monospacedDigit()
      }
      .font(.system(size: 10, weight: .semibold))
      .fixedSize()
      .frame(width: Self.labelWidth, height: Self.nowHalf * 2, alignment: .leading)
      .offset(y: nowCentre(height: height) - Self.nowHalf)
      Rectangle()
        .frame(width: lane, height: 1)
        .offset(x: Self.labelWidth, y: y(now))
    }
    .foregroundStyle(Color.accentColor)
    .accessibilityHidden(true)
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
    let width = max(lane * mark.width - Self.gap, 0)
    let top = y(max(mark.start, window.start))
    let bottom = y(min(mark.end, window.end))
    switch mark.kind {
    case .event(let event):
      MarkLabel(
        mark: mark, now: now, dayStart: dayStart, zone: zone, emoji: nil, color: color(event),
        reveal: reveal
      )
      .frame(width: width, height: max(bottom - top, Height.event), alignment: .topLeading)
      .offset(x: x, y: top)
    case .planned:
      MarkLabel(
        mark: mark, now: now, dayStart: dayStart, zone: zone, emoji: emoji(mark), color: nil,
        reveal: reveal
      )
      .frame(width: width, height: max(bottom - top, Height.planned), alignment: .topLeading)
      .offset(x: x, y: top)
    case .due:
      MarkLabel(
        mark: mark, now: now, dayStart: dayStart, zone: zone, emoji: emoji(mark), color: nil,
        reveal: reveal
      )
      // The label hangs below the due time (owner, 2026-11-17).
      .frame(width: width, height: Height.due, alignment: .leading)
      .offset(x: x, y: top)
    }
  }

  /// A run that does not fit its columns: one block, its marks in a popover.
  private func placed(_ block: DayRail.Block, lane: CGFloat) -> some View {
    let top = y(max(block.start, window.start))
    let bottom = y(min(block.end, window.end))
    return ClusterBlock(
      block: block, now: now, dayStart: dayStart, zone: zone, emoji: screen.emoji,
      calendarColor: block.marks.first.flatMap {
        if case .event(let event) = $0.kind { color(event) } else { nil }
      },
      reveal: reveal
    )
    .frame(
      width: max(lane * block.width - Self.gap, 0), height: max(bottom - top, Height.planned),
      alignment: .topLeading
    )
    .offset(x: Self.labelWidth + lane * block.leading, y: top)
  }

  private func pinned(_ mark: DayRail.Mark) -> some View {
    let color: Color? = if case .event(let event) = mark.kind { color(event) } else { nil }
    return MarkLabel(
      mark: mark, now: now, dayStart: dayStart, zone: zone, emoji: emoji(mark), color: color,
      reveal: reveal
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
  /// An event that began before it shows its weekday.
  let dayStart: Date
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
          .fixedSize()
          .layoutPriority(1)
        title(event)
      }
      .lineLimit(1)
      .padding(.trailing, 4)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Tokens.chipFill)
      .overlay {
        if event.display == .tentative { Hatch().stroke(Tokens.cardBorder, lineWidth: 1) }
      }
      // Past at 50 % over an opaque base, so the now line behind never shows through.
      .opacity(mark.end <= now ? 0.5 : 1)
      .background(.background)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(reading)
    case .planned(let item):
      Button {
        reveal(item.id)
      } label: {
        HStack(alignment: .top, spacing: 4) {
          Checkbox(isDone: item.status == .completed).imageScale(.small)
          Text(verbatim: time).monospacedDigit().fixedSize().layoutPriority(1)
          Text(verbatim: item.title).strikethrough(item.status == .completed)
          Spacer(minLength: 0)
          if let emoji { Text(verbatim: emoji).fixedSize() }
        }
        .lineLimit(1)
        .padding(.horizontal, 3)
        .foregroundStyle(item.status == .completed ? Tokens.doneText : Color.primary)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background, in: RoundedRectangle(cornerRadius: 3))
        .overlay {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Tokens.checkboxStroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(reading)
    case .due(let item, let isDeadline):
      Button {
        reveal(item.id)
      } label: {
        HStack(spacing: 4) {
          Rectangle()
            .fill(isDeadline ? AnyShapeStyle(Tokens.dueText) : AnyShapeStyle(.tertiary))
            .frame(width: 3)
          Checkbox(isDone: item.status == .completed).imageScale(.small)
          due(isDeadline).fixedSize().layoutPriority(1)
          Text(verbatim: item.title)
            .strikethrough(item.status == .completed)
            .foregroundStyle(item.status == .completed ? Tokens.doneText : Color.primary)
          Spacer(minLength: 0)
          if let emoji { Text(verbatim: emoji).fixedSize() }
        }
        .lineLimit(1)
        .background(.background)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(reading)
    }
  }

  private var time: String {
    TodayFormat.markTime(mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
  }

  private func due(_ isDeadline: Bool) -> Text {
    isDeadline
      ? Text("Due \(time)").fontWeight(.semibold).foregroundStyle(Tokens.dueText)
      : Text("due \(time)").foregroundStyle(.secondary)
  }

  private func title(_ event: CalendarEvent) -> Text {
    event.title.map { Text(verbatim: $0) } ?? Text("Busy")
  }

  private var reading: String {
    RailReading.mark(mark, now: now, dayStart: dayStart, zone: zone, locale: locale)
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

/// A run of marks that does not fit its columns (owner, 2026-11-17): the first mark's time and
/// title, then `+N`; a click lists every mark, and a task row selects its row in the list. An
/// event block is drawn as an event, with the first event's calendar bar; a task block that
/// holds a deadline keeps its amber bar.
private struct ClusterBlock: View {
  let block: DayRail.Block
  let now: Date
  let dayStart: Date
  let zone: TimeZone
  let emoji: [TaskItemID: String]
  /// The first event's calendar colour, for an event block.
  let calendarColor: Color?
  let reveal: (TaskItemID) -> Void
  @Environment(\.locale) private var locale
  @State private var isOpen = false

  var body: some View {
    let rows = ClusterRows.rows(
      block, emoji: emoji, dayStart: dayStart, zone: zone, locale: locale)
    Button {
      isOpen = true
    } label: {
      HStack(alignment: .top, spacing: 4) {
        if let calendarColor {
          Rectangle().fill(calendarColor).frame(width: 3)
        } else if block.holdsDeadline {
          Rectangle().fill(Tokens.dueText).frame(width: 3)
        }
        if let first = rows.first {
          Text(verbatim: first.when).monospacedDigit().fixedSize().layoutPriority(1)
            .foregroundStyle(calendarColor == nil ? Color.primary : Color.secondary)
          Text(verbatim: first.title)
        }
        Text(verbatim: "+\(block.marks.count - 1)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .fixedSize()
          .layoutPriority(1)
        Spacer(minLength: 0)
      }
      .lineLimit(1)
      .padding(hasBar ? .trailing : .horizontal, hasBar ? 4 : 3)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(calendarColor == nil ? Color.clear : Tokens.chipFill)
      .background(.background, in: RoundedRectangle(cornerRadius: 3))
      .overlay {
        if calendarColor == nil {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Tokens.checkboxStroke, lineWidth: 1)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isOpen, arrowEdge: .trailing) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          if let item = row.item {
            Button {
              isOpen = false
              reveal(item)
            } label: {
              label(row)
            }
            .buttonStyle(.plain)
          } else {
            label(row)
          }
        }
      }
      .font(.system(size: 11))
      .padding(10)
      .frame(minWidth: 220, alignment: .leading)
    }
    .modifier(
      BlockAccessibility(
        reading: RailReading.block(block, now: now, dayStart: dayStart, zone: zone, locale: locale),
        isOpen: $isOpen))
  }

  private var hasBar: Bool { calendarColor != nil || block.holdsDeadline }

  private func label(_ row: ClusterRows.Row) -> some View {
    HStack(spacing: 4) {
      if row.item != nil { Checkbox(isDone: row.isDone).imageScale(.small) }
      when(row).monospacedDigit().fixedSize().layoutPriority(1)
      Text(verbatim: row.title).strikethrough(row.isDone)
      Spacer(minLength: 0)
      if let emoji = row.emoji { Text(verbatim: emoji).fixedSize() }
    }
    .lineLimit(1)
    .foregroundStyle(row.isDone ? Tokens.doneText : Color.primary)
    .contentShape(Rectangle())
  }

  /// A deadline's `Due 18:00` in amber, as on the scale.
  private func when(_ row: ClusterRows.Row) -> Text {
    row.isDeadline
      ? Text(verbatim: row.when).fontWeight(.semibold).foregroundStyle(Tokens.dueText)
      : Text(verbatim: row.when)
  }
}

/// A block as one VoiceOver element: its reading, a button, and the default action, VO-Space,
/// that opens its popover (owner, 2026-11-17).
struct BlockAccessibility: ViewModifier {
  let reading: String
  @Binding var isOpen: Bool

  func body(content: Content) -> some View {
    content
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(reading)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { show() }
  }

  func show() { isOpen = true }
}

/// A block's marks as its popover lists them.
enum ClusterRows {
  struct Row: Hashable {
    /// Nil for an event.
    let item: TaskItemID?
    /// The time, `Due 18:00` or `due 20:35` for a due mark.
    let when: String
    let title: String
    let emoji: String?
    let isDone: Bool
    /// A deadline's due mark: its time is amber.
    let isDeadline: Bool
  }

  static func rows(
    _ block: DayRail.Block, emoji: [TaskItemID: String], dayStart: Date, zone: TimeZone,
    locale: Locale
  ) -> [Row] {
    block.marks.map { mark in
      let time = TodayFormat.markTime(
        mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
      switch mark.kind {
      case .event(let event):
        return Row(
          item: nil, when: time,
          title: event.title ?? RailReading.localized("Busy", locale), emoji: nil, isDone: false,
          isDeadline: false)
      case .planned(let item):
        return Row(
          item: item.id, when: time, title: item.title, emoji: emoji[item.id],
          isDone: item.status == .completed, isDeadline: false)
      case .due(let item, let isDeadline):
        return Row(
          item: item.id, when: RailReading.due(time, isDeadline: isDeadline, locale),
          title: item.title, emoji: emoji[item.id], isDone: item.status == .completed,
          isDeadline: isDeadline)
      }
    }
  }
}

/// What VoiceOver reads for a mark or a block, in the catalog's words (`today.md` § Calendar,
/// SwiftUI): `17:00, Violin lesson, event, in 40 minutes`, `20:30, Allemande…, task, estimate
/// 45 minutes, Not completed`.
enum RailReading {
  static func mark(
    _ mark: DayRail.Mark, now: Date, dayStart: Date, zone: TimeZone, locale: Locale
  ) -> String {
    let time = TodayFormat.markTime(mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
    switch mark.kind {
    case .event(let event):
      let title = event.title ?? localized("Busy", locale)
      let reading = localized("\(time), \(title), event", locale)
      let minutes = Int(mark.start.timeIntervalSince(now) / 60)
      guard mark.start > now, minutes > 0 else { return reading }
      return localized("\(reading), \(localized("in \(minutes) minutes", locale))", locale)
    case .planned(let item):
      return task(time, item, estimate: true, deadline: false, locale)
    case .due(let item, let isDeadline):
      return task(
        due(time, isDeadline: isDeadline, locale), item, estimate: false, deadline: isDeadline,
        locale)
    }
  }

  /// `4 items: ` and every mark's reading, joined by `; `.
  static func block(
    _ block: DayRail.Block, now: Date, dayStart: Date, zone: TimeZone, locale: Locale
  ) -> String {
    let readings = block.marks.map {
      mark($0, now: now, dayStart: dayStart, zone: zone, locale: locale)
    }
    let count = localized("\(block.marks.count) items", locale)
    return localized("\(count): \(readings.joined(separator: "; "))", locale)
  }

  static func due(_ time: String, isDeadline: Bool, _ locale: Locale) -> String {
    isDeadline ? localized("Due \(time)", locale) : localized("due \(time)", locale)
  }

  /// The catalog's string in `locale`'s language, as `Text` reads it from the environment.
  static func localized(_ value: String.LocalizationValue, _ locale: Locale) -> String {
    var resource = LocalizedStringResource(value)
    resource.locale = locale
    return String(localized: resource)
  }

  /// A deadline reads `deadline` where any other task reads `task`: `Due` and `due` sound alike.
  private static func task(
    _ when: String, _ item: TaskItem, estimate: Bool, deadline: Bool, _ locale: Locale
  ) -> String {
    var reading =
      deadline
      ? localized("\(when), \(item.title), deadline", locale)
      : localized("\(when), \(item.title), task", locale)
    if estimate, let minutes = item.estimateMinutes, minutes > 0 {
      reading = localized("\(reading), \(localized("estimate \(minutes) minutes", locale))", locale)
    }
    let state =
      item.status == .completed
      ? localized("Completed", locale) : localized("Not completed", locale)
    return localized("\(reading), \(state)", locale)
  }
}
