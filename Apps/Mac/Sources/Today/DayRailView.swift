import MoonShineCore
import SwiftUI

/// The calendar the Day rail reads, set by `RootView` from the model's calendar feed (S4-3d).
struct DayRailInput {
  let events: CalendarRead<[CalendarEvent]>
  let visibility: CalendarVisibility
  /// For the bar colours.
  let calendars: [CalendarInfo]
  /// The rail's span and the free term: Settings' in Live, `DayWindow.standard` in Demo.
  let window: DayWindow
  /// Demo's clock stands still at the overview's `now`; Live's runs.
  let isFrozen: Bool
  /// The row under the rail; nil for none.
  var row: CalendarRow?
  var isConnecting = false
  var connect: @MainActor () -> Void = {}
  var notNow: @MainActor () -> Void = {}

  /// Before the model sets one: the tasks with a time, no calendar fact and no row.
  static let none = DayRailInput(
    events: .unavailable(.notDetermined), visibility: CalendarVisibility(), calendars: [],
    window: .standard, isFrozen: false)
}

extension EnvironmentValues {
  @Entry var dayRailInput = DayRailInput.none
}

/// The row under Today's rail while the calendar cannot be read (`design/screens/today.md` §
/// Calendar, `design/copy.md` § Calendar strings). Its words hold no event, calendar or account.
enum CalendarRow: Equatable, CaseIterable {
  /// Not asked yet: `Connect calendars…` and `Not now`.
  case connect
  /// Denied: `Open System Settings`.
  case off
  /// Add Events Only: access is on but of the wrong kind; `Open System Settings` (owner,
  /// 2026-11-27, PR #74 round 1).
  case fullAccessOnly

  /// How long `Not now` hides the connect row, in calendar days.
  static let notNowDays = 30

  /// Nil before access is known, when granted, while `Not now` hides it (from the day it was
  /// pressed until 30 calendar days later, in `calendar`'s zone; a day after today, the clock
  /// moved back, hides nothing), and when restricted: the Mac's owner cannot lift a
  /// device-management restriction, and Settings → Calendars explains it (owner, 2026-11-27).
  init?(access: CalendarAccess?, notNow: Date?, now: Date, calendar: Calendar) {
    switch access {
    case .notDetermined?:
      if let notNow, Self.hides(pressed: notNow, now: now, calendar: calendar) { return nil }
      self = .connect
    case .denied?: self = .off
    case .writeOnly?: self = .fullAccessOnly
    case .granted?, .restricted?, nil: return nil
    }
  }

  /// The row offers `Open System Settings` rather than `Connect calendars…` and `Not now`.
  var opensSystemSettings: Bool { self != .connect }

  private static func hides(pressed: Date, now: Date, calendar: Calendar) -> Bool {
    let pressed = calendar.startOfDay(for: pressed)
    let today = calendar.startOfDay(for: now)
    guard pressed <= today, let days = calendar.dateComponents([.day], from: pressed, to: today).day
    else { return false }
    return days < notNowDays
  }

  var sentence: String { String(localized: resource) }

  /// The sentence in `locale`, whatever the Mac's language.
  func sentence(in locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }

  private var resource: LocalizedStringResource {
    switch self {
    case .connect: "Calendar is not connected. Events stay on this device."
    case .off: "Calendar access is off for MoonShine."
    case .fullAccessOnly: "MoonShine can only read calendars with Full Access."
    }
  }
}

/// `CalendarRow` under the rail; buttons as links, as the rail's other actions.
struct CalendarAccessRow: View {
  @Environment(\.dayRailInput) private var input
  @Environment(\.openTarget) private var openTarget

  var body: some View {
    if let row = input.row {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: row.sentence).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 12) {
          if row.opensSystemSettings {
            Button("Open System Settings") { openTarget(.calendarPrivacySettings) }
          } else {
            Button("Connect calendars…") { input.connect() }.disabled(input.isConnecting)
            Button("Not now") { input.notNow() }
          }
        }
        .buttonStyle(.link)
      }
      .font(.system(size: 11))
    }
  }
}

extension DayRail {
  /// Absent with no calendar fact and no task with a time today (`today.md` § Calendar).
  var isShown: Bool {
    load.eventCount != nil || !(above.isEmpty && marks.isEmpty && below.isEmpty)
  }
}

/// The Day section at the top of Today's rail: `design/screens/today.md` § Calendar,
/// `design/screens/day-rail-dense.md` (direction 1, the compressed timeline) and
/// `design/components.md` § Day rail. Read only: a task row selects its row in the list; its
/// checkbox and a double-click open the task in OmniFocus through the opener (S4-5).
struct DayRailView: View {
  let rail: DayRail
  let now: Date
  let screen: TodayScreen
  let calendars: [CalendarInfo]
  /// The task selected in the list: its rows take the selection fill.
  let selected: TaskItemID?
  /// A click on a task row: the list selects its row.
  let reveal: (TaskItemID) -> Void
  @Environment(\.locale) private var locale

  /// The time gutter left of the rows (`RailTimeGutter`).
  static let gutter: CGFloat = 40
  /// The duration line and the now dot, at the gutter's trailing edge.
  static let lineX: CGFloat = gutter - 5

  var body: some View {
    let timeline = DayTimeline.layout(rail, now: now)
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Day").font(.system(size: 12, weight: .semibold))
        if let facts = DayFactText.joined(
          facts.filter(\.isCalendar), timeZone: zone, locale: locale)
        {
          facts.foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(reading.section(rail, timeline))
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
      scale(timeline)
      ForEach(Array(rail.below.enumerated()), id: \.offset) { pinned($0.element) }
      VStack(alignment: .leading, spacing: 2) {
        if let facts = DayFactText.joined(
          facts.filter { !$0.isCalendar }, timeZone: zone, locale: locale)
        {
          facts
        }
        let edges = TodayFormat.windowEdges(window, calendar: screen.calendar)
        Text("day window \(edges.0)–\(edges.1)")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    }
    .font(.system(size: 11.5))
    .accessibilityElement(children: .contain)
  }

  private var zone: TimeZone { screen.timeZone }
  private var dayStart: Date { screen.calendar.startOfDay(for: screen.day) }
  private var facts: [DayFact] { TodayFormat.dayFact(rail.load) }
  private var window: DateInterval { rail.load.window }
  private var reading: RailReading {
    RailReading(
      now: now, dayStart: dayStart, zone: zone, locale: locale, lines: screen.lineNames,
      selected: selected)
  }

  private func scale(_ timeline: DayTimeline) -> some View {
    ZStack(alignment: .topLeading) {
      edge(window.start, y: 0, showsTime: timeline.showsStartEdge)
      edge(window.end, y: timeline.height, showsTime: timeline.showsEndEdge)
      ForEach(Array(timeline.items.enumerated()), id: \.offset) { _, item in
        switch item {
        case .gap(let gap): gapRow(gap, holdsNow: holdsNow(gap, timeline.now))
        case .row(let row): timelineRow(row)
        }
      }
      if let mark = timeline.now { nowMarker(mark) }
    }
    // Room for the end line's label.
    .frame(maxWidth: .infinity, minHeight: timeline.height + 7, alignment: .topLeading)
  }

  /// The window's start or end line, its time in the gutter unless the now label covers it.
  private func edge(_ date: Date, y: CGFloat, showsTime: Bool) -> some View {
    ZStack(alignment: .topLeading) {
      if showsTime {
        Text(verbatim: time(date))
          .font(.system(size: 10))
          .monospacedDigit()
          .foregroundStyle(.tertiary)
          .offset(y: y - 6)
      }
      Rectangle()
        .fill(Tokens.cardBorder)
        .frame(height: 1)
        .padding(.leading, Self.gutter)
        .offset(y: y)
    }
    .accessibilityHidden(true)
  }

  private func holdsNow(_ gap: DayTimeline.Gap, _ now: DayTimeline.Now?) -> Bool {
    guard let now, now.place == .gap else { return false }
    return now.y >= gap.top && now.y <= gap.top + gap.height
  }

  /// `RailGap`: a dotted stub and the stretch it shortens, `11:55–14:15`.
  private func gapRow(_ gap: DayTimeline.Gap, holdsNow: Bool) -> some View {
    HStack(spacing: 6) {
      Rectangle()
        .stroke(Tokens.checkboxStroke, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
        .frame(width: 1.5, height: 12)
      Text(verbatim: "\(time(gap.from))–\(time(gap.to))")
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
    .frame(height: 18)
    .padding(.leading, Self.gutter + 4)
    .offset(y: gap.top)
    .accessibilityHidden(true)
  }

  private func timelineRow(_ row: DayTimeline.Row) -> some View {
    ZStack(alignment: .topLeading) {
      if row.showsStart {
        gutterTime(row.mark.start, size: 11, style: .secondary).offset(y: row.top + 4)
      }
      if row.showsEnd {
        gutterTime(row.mark.end, size: 10, style: .tertiary).offset(y: row.top + 18)
      }
      if let line = row.line {
        Rectangle()
          .fill(lineColor(row.mark))
          .opacity(0.7)
          .frame(width: 2, height: max(line.end - row.top, 0))
          .offset(x: Self.lineX, y: row.top)
          .accessibilityHidden(true)
        if let end = line.endTime {
          gutterTime(end, size: 10, style: .tertiary).offset(y: line.end - 6)
        }
      }
      DayRailRow(
        mark: row.mark, now: now, dayStart: dayStart,
        zone: zone, emoji: emoji(row.mark), color: eventColor(row.mark),
        range: row.showsRange ? range(row.mark) : nil, isSelected: isSelected(row.mark),
        reading: reading.row(row.mark, inside: row.inside), reveal: reveal
      )
      .frame(height: row.height)
      .padding(.leading, Self.gutter)
      .offset(y: row.top)
    }
  }

  private func gutterTime(_ date: Date, size: CGFloat, style: HierarchicalShapeStyle)
    -> some View
  {
    Text(verbatim: time(date))
      .font(.system(size: size))
      .monospacedDigit()
      .foregroundStyle(style)
      .fixedSize()
      .accessibilityHidden(true)
  }

  /// `NowMarker`: the label in the gutter, `now` over the time; a line across the rows only in
  /// a gap or a slot, else a dot on the span's line or the block's edge (owner, 2026-11-20).
  private func nowMarker(_ mark: DayTimeline.Now) -> some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        Text("now").font(.system(size: 9.5))
        Text(verbatim: time(now)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
      }
      .fixedSize()
      // No plate (owner, 2026-11-24): the gutter's times give way to the label and the line
      // runs to its right, so nothing shows through.
      .frame(width: Self.lineX - 4, height: 24, alignment: .leading)
      .offset(y: mark.y - 12)
      switch mark.place {
      case .gap, .slot:
        Rectangle()
          .frame(height: 1.5)
          .padding(.leading, Self.gutter)
          .offset(y: mark.y - 0.75)
      case .line, .block:
        Circle()
          .frame(width: 7, height: 7)
          .offset(x: Self.lineX - 2.5, y: mark.y - 3.5)
      }
    }
    .foregroundStyle(Color.accentColor)
    .accessibilityHidden(true)
  }

  /// `PinnedRow`: before or after the window, its time in the gutter; one from an earlier day
  /// keeps `Wed 23:00` in the row (owner, 2026-11-21).
  private func pinned(_ mark: DayRail.Mark) -> some View {
    let earlier = mark.start < dayStart
    return HStack(spacing: 0) {
      Group {
        if Self.showsGutterTime(pinned: mark, dayStart: dayStart) {
          Text(verbatim: time(mark.start)).monospacedDigit().foregroundStyle(.secondary)
        }
      }
      .font(.system(size: 11))
      .frame(width: Self.gutter, alignment: .leading)
      .accessibilityHidden(true)
      DayRailRow(
        mark: mark, now: now, dayStart: dayStart, zone: zone, emoji: emoji(mark),
        color: eventColor(mark), range: earlier ? range(mark) : nil,
        isSelected: isSelected(mark), reading: reading.row(mark), reveal: reveal)
    }
    .frame(height: 22)
  }

  /// A pinned row's time is in the gutter, except a due row's and one from an earlier day.
  static func showsGutterTime(pinned mark: DayRail.Mark, dayStart: Date) -> Bool {
    if case .due = mark.kind { return false }
    return mark.start >= dayStart
  }

  /// `17:45–18:15`, or `Wed 23:00–09:00` from an earlier day.
  private func range(_ mark: DayRail.Mark) -> String {
    let start = TodayFormat.markTime(mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
    return mark.isSpan ? "\(start)–\(time(mark.end))" : start
  }

  private func isSelected(_ mark: DayRail.Mark) -> Bool {
    Self.isSelected(mark, selected: selected)
  }

  /// A task's rows take the selection when its task is selected in the list, its planned and
  /// its due row alike (owner, 2026-11-21); an event never does.
  static func isSelected(_ mark: DayRail.Mark, selected: TaskItemID?) -> Bool {
    switch mark.kind {
    case .event: false
    case .planned(let item), .due(let item, _): item.id == selected
    }
  }

  private func emoji(_ mark: DayRail.Mark) -> String? {
    switch mark.kind {
    case .event: nil
    case .planned(let item), .due(let item, _): screen.emoji[item.id]
    }
  }

  private func eventColor(_ mark: DayRail.Mark) -> Color? {
    if case .event(let event) = mark.kind { color(event) } else { nil }
  }

  /// The calendar's colour for an event, else secondary (`DurationLine`).
  private func lineColor(_ mark: DayRail.Mark) -> AnyShapeStyle {
    eventColor(mark).map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary)
  }

  private func color(_ event: CalendarEvent) -> Color {
    Tokens.calendar(calendars.first { $0.id == event.calendarID }?.colorHex)
  }

  private func title(_ event: CalendarEvent) -> Text {
    event.title.map { Text(verbatim: $0) } ?? Text("Busy")
  }

  private func time(_ date: Date) -> String {
    TodayFormat.time(date, timeZone: zone, locale: locale)
  }
}

/// `DayRailRow`: one event, timed task or due task, full width (`design/components.md` § Day
/// rail). Its time is in the gutter, except a due row's `Due 18:00` and a range the row shows.
private struct DayRailRow: View {
  let mark: DayRail.Mark
  let now: Date
  let dayStart: Date
  let zone: TimeZone
  let emoji: String?
  /// The calendar's colour, for an event.
  let color: Color?
  /// `17:45–18:15` for a span inside another or a row from before the window.
  let range: String?
  let isSelected: Bool
  let reading: String
  let reveal: (TaskItemID) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    switch mark.kind {
    case .event(let event):
      HStack(alignment: .top, spacing: 6) {
        CalendarBar(color: color ?? Tokens.paused)
        title(event).padding(.top, 3)
        Spacer(minLength: 0)
        rangeText.padding(.top, 4)
      }
      .lineLimit(1)
      .padding(.trailing, 6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Tokens.chipFill)
      .overlay {
        if event.display == .tentative { Hatch().stroke(Tokens.cardBorder, lineWidth: 1) }
      }
      // Past at 50 % over an opaque base.
      .opacity(mark.end <= now ? 0.5 : 1)
      .background(.background)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(reading)
    case .planned(let item):
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        OpeningCheckbox(isDone: item.status == .completed, id: item.id).imageScale(.small)
        Button {
          reveal(item.id)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: item.title).strikethrough(item.status == .completed)
            Spacer(minLength: 0)
            rangeText
            if let emoji { Text(verbatim: emoji).fixedSize() }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One click selects its row; a double-click opens it (`today.md` § Calendar). Not on
        // the checkbox, whose own click opens it once (PR #73 round 1).
        .opensOnDoubleClick(.task(item.id))
        .accessibilityLabel(reading)
      }
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.top, 3)
      .foregroundStyle(item.status == .completed ? Tokens.doneText : Color.primary)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(.background, in: RoundedRectangle(cornerRadius: 3))
      .modifier(Selection(isSelected: isSelected, outline: true))

    case .due(let item, let isDeadline):
      HStack(spacing: 5) {
        Rectangle()
          .fill(isDeadline ? AnyShapeStyle(Tokens.dueText) : AnyShapeStyle(Tokens.checkboxStroke))
          .frame(width: 3)
        OpeningCheckbox(isDone: item.status == .completed, id: item.id).imageScale(.small)
        Button {
          reveal(item.id)
        } label: {
          HStack(spacing: 5) {
            due(isDeadline).fixedSize().layoutPriority(1)
            Text(verbatim: item.title)
              .strikethrough(item.status == .completed)
              .foregroundStyle(item.status == .completed ? Tokens.doneText : Color.primary)
            Spacer(minLength: 0)
            if let emoji { Text(verbatim: emoji).fixedSize() }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One click selects its row; a double-click opens it (`today.md` § Calendar). Not on
        // the checkbox, whose own click opens it once (PR #73 round 1).
        .opensOnDoubleClick(.task(item.id))
        .accessibilityLabel(reading)
      }
      .lineLimit(1)
      .padding(.trailing, 6)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .background(.background)
      .modifier(Selection(isSelected: isSelected, outline: false))

    }
  }

  @ViewBuilder private var rangeText: some View {
    if let range {
      Text(verbatim: range)
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize()
        .layoutPriority(1)
    }
  }

  private func due(_ isDeadline: Bool) -> Text {
    let time = TodayFormat.markTime(mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
    return isDeadline
      ? Text("Due \(time)").fontWeight(.semibold).foregroundStyle(Tokens.dueText)
      : Text("due \(time)").foregroundStyle(.tertiary)
  }

  private func title(_ event: CalendarEvent) -> Text {
    event.title.map { Text(verbatim: $0) } ?? Text("Busy")
  }
}

/// A task row's outline, or the `selection` fill and a 1.5-pt accent ring when its task is
/// selected in the list (`day-rail-dense.md` § Selected).
private struct Selection: ViewModifier {
  let isSelected: Bool
  /// A timed task's 1-pt outline when not selected.
  let outline: Bool

  func body(content: Content) -> some View {
    content
      .background(isSelected ? Tokens.selection : Color.clear)
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 1.5)
        } else if outline {
          RoundedRectangle(cornerRadius: 3).strokeBorder(Tokens.checkboxStroke, lineWidth: 1)
        }
      }
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

/// What VoiceOver reads on the Day rail, in the catalog's words (`day-rail-dense.md` §
/// VoiceOver): `10:20, Call a supplier, task, no estimate, not completed, Life ops, selected`.
struct RailReading {
  let now: Date
  let dayStart: Date
  let zone: TimeZone
  let locale: Locale
  /// A task's line; a task with no line found has no line term.
  let lines: [TaskItemID: TodayScreen.LineName]
  let selected: TaskItemID?

  /// `Day, 15 items with a time, 1 before 08:00. Shortened: 08:30 to 10:05, 10:35 to 11:40.
  /// Now 14:40, during Draft the summary.`
  func section(_ rail: DayRail, _ timeline: DayTimeline) -> String {
    let window = rail.load.window
    var counts = [
      localized("Day, \(rail.above.count + rail.marks.count + rail.below.count) items with a time")
    ]
    if !rail.above.isEmpty {
      counts.append(localized("\(rail.above.count) before \(time(window.start))"))
    }
    if !rail.below.isEmpty {
      counts.append(localized("\(rail.below.count) after \(time(window.end))"))
    }
    var sentences = [counts.joined(separator: ", ")]
    let gaps = timeline.gaps.map { range($0.from, $0.to) }
    if !gaps.isEmpty { sentences.append(localized("Shortened: \(gaps.joined(separator: ", "))")) }
    if let mark = timeline.now {
      sentences.append(
        mark.during.map { localized("Now \(time(now)), during \(title($0))") }
          ?? localized("Now \(time(now))"))
    }
    return sentences.map { "\($0)." }.joined(separator: " ")
  }

  /// A row's reading; an outer span adds the rows inside it: `… . Contains Review the notes,
  /// 17:45 to 18:15, and Send an invoice.`
  func row(_ mark: DayRail.Mark, inside: [DayRail.Mark] = []) -> String {
    let reading = self.mark(mark)
    guard !inside.isEmpty else { return reading }
    let names = inside.map {
      $0.isSpan ? localized("\(title($0)), \(range($0.start, $0.end))") : title($0)
    }
    return localized("\(reading). Contains \(names.formatted(.list(type: .and).locale(locale))).")
  }

  private func mark(_ mark: DayRail.Mark) -> String {
    let start = TodayFormat.markTime(mark.start, dayStart: dayStart, timeZone: zone, locale: locale)
    let when = mark.isSpan ? range(mark.start, mark.end) : start
    switch mark.kind {
    case .event:
      let reading = localized("\(when), \(title(mark)), event")
      let minutes = Int(mark.start.timeIntervalSince(now) / 60)
      guard mark.start > now, minutes > 0 else { return reading }
      return localized("\(reading), \(localized("in \(minutes) minutes"))")
    case .planned(let item):
      return task(when, item, estimate: true, deadline: false)
    case .due(let item, let isDeadline):
      return task(
        Self.due(start, isDeadline: isDeadline, locale), item, estimate: false, deadline: isDeadline
      )
    }
  }

  static func due(_ time: String, isDeadline: Bool, _ locale: Locale) -> String {
    isDeadline ? localized("Due \(time)", locale) : localized("due \(time)", locale)
  }

  static func localized(_ value: String.LocalizationValue, _ locale: Locale) -> String {
    TodayFormat.localized(value, locale)
  }

  private func localized(_ value: String.LocalizationValue) -> String {
    Self.localized(value, locale)
  }

  /// `17:45 to 18:15`, or `Wed 23:00 to 09:00` from an earlier day.
  private func range(_ from: Date, _ to: Date) -> String {
    let start = TodayFormat.markTime(from, dayStart: dayStart, timeZone: zone, locale: locale)
    return localized("\(start) to \(time(to))")
  }

  private func time(_ date: Date) -> String {
    TodayFormat.time(date, timeZone: zone, locale: locale)
  }

  private func title(_ mark: DayRail.Mark) -> String {
    switch mark.kind {
    case .event(let event): event.title ?? localized("Busy")
    case .planned(let item), .due(let item, _): item.title
    }
  }

  /// A deadline reads `deadline` where any other task reads `task`: `Due` and `due` sound alike.
  private func task(_ when: String, _ item: TaskItem, estimate: Bool, deadline: Bool) -> String {
    var reading =
      deadline
      ? localized("\(when), \(item.title), deadline") : localized("\(when), \(item.title), task")
    var terms: [String] = []
    if estimate {
      if let minutes = item.estimateMinutes, minutes > 0 {
        terms.append(
          minutes.isMultiple(of: 60)
            ? localized("estimate \(minutes / 60) hours") : localized("estimate \(minutes) minutes")
        )
      } else {
        terms.append(localized("no estimate"))
      }
    }
    terms.append(item.status == .completed ? localized("completed") : localized("not completed"))
    switch lines[item.id] {
    case .lifeOps: terms.append(localized("Life ops"))
    case .named(let name): terms.append(name)
    case nil: break
    }
    if item.id == selected { terms.append(localized("selected")) }
    for term in terms { reading = localized("\(reading), \(term)") }
    return reading
  }
}
