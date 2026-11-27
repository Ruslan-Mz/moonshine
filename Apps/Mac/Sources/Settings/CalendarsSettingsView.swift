import MoonShineCore
import SwiftUI

/// Settings → Calendars (`design/screens/settings-calendars.md`): access, the calendars by
/// account with Show and Counts as busy, and the day window. Applied at once; the rail and the
/// subtitle recompute from the events held. In Demo the switches act in memory only, the window
/// stays 08:00–22:00 and System Settings opens nothing (owner, 2026-11-27).
struct CalendarsSettingsView: View {
  @Bindable var model: AppModel
  @Environment(\.openTarget) private var openTarget

  var body: some View {
    let feed = model.calendar
    Form {
      Section {
        access(CalendarAccessLine(feed.access), isConnecting: feed.isConnecting)
      }
      if feed.access == .granted {
        ForEach(Array(CalendarGroup.groups(feed.calendars).enumerated()), id: \.offset) {
          _, group in
          calendars(group)
        }
      } else if feed.access != nil {
        // Nothing before the first read; then the list waits for Full Access.
        Section {
          Text("Calendars appear here after you connect.").foregroundStyle(.secondary)
        }
      }
      dayWindow
      Text("Events stay on this device. They are not synced by MoonShine.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .frame(width: 580)
  }

  /// Nothing before the first read, so no state flashes at launch.
  @ViewBuilder
  private func access(_ line: CalendarAccessLine?, isConnecting: Bool) -> some View {
    LabeledContent("Calendar access") {
      HStack(spacing: 8) {
        if let line { Text(line.label) }
        if model.source == .demo {
          Text("Demo data")
            .font(.caption)
            .padding(.horizontal, 5)
            .background(Tokens.chipFill, in: Capsule())
        }
        if let line, let button = line.button {
          switch line.action {
          case .connect?:
            Button {
              model.calendar.connect()
            } label: {
              Text(button)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isConnecting)
          case .systemSettings?:
            Button {
              openTarget(.calendarPrivacySettings)
            } label: {
              Text(button)
            }
          case nil: EmptyView()
          }
        }
      }
    }
    if let line {
      Text(line.caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func calendars(_ group: CalendarGroup) -> some View {
    Section {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          Color.clear.frame(height: 1)
          Text("Show")
          Text("Counts as busy")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        ForEach(group.calendars) { calendar in
          row(calendar, model.calendarVisibility.setting(for: calendar))
        }
      }
    } header: {
      group.account.map { Text(verbatim: $0) }
    }
  }

  private func row(_ calendar: CalendarInfo, _ setting: CalendarSetting) -> some View {
    GridRow {
      HStack(spacing: 6) {
        Circle().fill(Tokens.calendar(calendar.colorHex)).frame(width: 8, height: 8)
        Text(verbatim: calendar.title).lineLimit(1)
      }
      // A calendar with Show off contributes nothing: greyed.
      .opacity(setting.show ? 1 : 0.45)
      toggle("Show", calendar, setting.show) {
        model.setCalendarSetting(
          CalendarSetting(show: $0, countsAsBusy: setting.countsAsBusy), for: calendar.id)
      }
      toggle("Counts as busy", calendar, setting.countsAsBusy) {
        model.setCalendarSetting(
          CalendarSetting(show: setting.show, countsAsBusy: $0), for: calendar.id)
      }
    }
  }

  /// VoiceOver names the calendar with the column: `Family, Show`.
  private func toggle(
    _ label: LocalizedStringResource, _ calendar: CalendarInfo, _ isOn: Bool,
    set: @escaping (Bool) -> Void
  ) -> some View {
    Toggle(isOn: Binding(get: { isOn }, set: set)) { Text(label) }
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.mini)
      .accessibilityLabel(Text(verbatim: "\(calendar.title), \(String(localized: label))"))
  }

  private var dayWindow: some View {
    Section {
      let window = model.dayWindow
      LabeledContent("Day window") {
        HStack(spacing: 6) {
          minutePicker("Start", DayWindowChoice.starts, window.startMinute) {
            DayWindowChoice.window(start: $0, end: window.endMinute)
          }
          Text(verbatim: "–")
          minutePicker("End", DayWindowChoice.ends(after: window.startMinute), window.endMinute) {
            DayWindowChoice.window(start: window.startMinute, end: $0)
          }
        }
        .disabled(model.source == .demo)
      }
      Text(
        "Free time = day window − time in calendars that count as busy − tasks with a planned time and an estimate. Today counts from now to the end of the window. Overlaps count once. Tentative, all-day and free events are shown but not counted; declined, delegated and cancelled events are hidden."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func minutePicker(
    _ label: LocalizedStringKey, _ choices: [Int], _ selected: Int,
    window: @escaping (Int) -> DayWindow?
  ) -> some View {
    Picker(
      label,
      selection: Binding(
        get: { selected },
        set: { if let new = window($0) { model.setDayWindow(new) } })
    ) {
      ForEach(choices, id: \.self) { Text(verbatim: DayWindowChoice.label($0)).tag($0) }
    }
    .labelsHidden()
    .fixedSize()
  }
}

/// The access row of Settings → Calendars (`design/screens/settings-calendars.md` § Layout).
enum CalendarAccessLine: Equatable, CaseIterable {
  case notConnected, connected, denied, eventsOnly, restricted

  enum Action: Equatable {
    /// `Connect calendars…`, the default button.
    case connect
    case systemSettings
  }

  /// Nil before the first read.
  init?(_ access: CalendarAccess?) {
    switch access {
    case .notDetermined?: self = .notConnected
    case .granted?: self = .connected
    case .denied?: self = .denied
    case .writeOnly?: self = .eventsOnly
    case .restricted?: self = .restricted
    case nil: return nil
    }
  }

  /// None when restricted: the Mac's owner cannot lift it.
  var action: Action? {
    switch self {
    case .notConnected: .connect
    case .connected, .denied, .eventsOnly: .systemSettings
    case .restricted: nil
    }
  }

  var label: LocalizedStringResource {
    switch self {
    case .notConnected: "Not connected"
    case .connected: "Connected"
    case .denied: "Access denied"
    case .eventsOnly: "Can't read events"
    case .restricted: "Not available"
    }
  }

  var button: LocalizedStringResource? {
    switch self {
    case .notConnected: "Connect calendars…"
    case .connected: "Open System Settings…"
    case .denied, .eventsOnly: "Open System Settings"
    case .restricted: nil
    }
  }

  /// Where access is turned on in System Settings, `Then reopen MoonShine.` follows the
  /// sentence that names it: macOS shows a new grant to a reopened app (owner, 2026-11-27).
  var caption: LocalizedStringResource {
    switch self {
    case .notConnected:
      "MoonShine asks macOS for read-only access. Nothing is created or edited. The app works fully without it."
    case .connected: "MoonShine reads events through macOS (EventKit), read-only."
    case .denied:
      "Calendar access is off for MoonShine. Allow it in System Settings → Privacy & Security → Calendars. Then reopen MoonShine. Today, Week and Month work without events."
    case .eventsOnly:
      "MoonShine can only read calendars with Full Access. Change it in System Settings → Privacy & Security → Calendars. Then reopen MoonShine. Today, Week and Month work without events."
    case .restricted:
      "Calendar access is restricted on this device, for example by a device-management profile. Today, Week and Month work without events."
    }
  }

  /// `resource` in `locale`, whatever the Mac's language.
  static func string(_ resource: LocalizedStringResource, in locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
  }
}

/// The calendars of one account, in the order the provider gives them; accounts in the order
/// of their first calendar. An account is its identifier where the provider gives one: two
/// accounts may share a title.
struct CalendarGroup: Equatable {
  let account: String?
  var calendars: [CalendarInfo]

  private enum Key: Equatable {
    case id(String)
    case title(String?)

    init(_ calendar: CalendarInfo) {
      self = calendar.accountID.map(Key.id) ?? .title(calendar.account)
    }
  }

  static func groups(_ calendars: [CalendarInfo]) -> [CalendarGroup] {
    var groups: [CalendarGroup] = []
    for calendar in calendars {
      let key = Key(calendar)
      if let index = groups.firstIndex(where: { $0.calendars.first.map(Key.init) == key }) {
        groups[index].calendars.append(calendar)
      } else {
        groups.append(CalendarGroup(account: calendar.account, calendars: [calendar]))
      }
    }
    return groups
  }
}

/// The day window's two pickers, in minutes from midnight, on the quarter hour.
enum DayWindowChoice {
  static let step = 15
  static let starts = Array(stride(from: 0, to: 24 * 60, by: step))

  /// From a quarter hour after `start` to 24:00.
  static func ends(after start: Int) -> [Int] {
    Array(stride(from: start + step, through: 24 * 60, by: step))
  }

  /// A start at or after the end moves the end a quarter hour after it; nil past 23:45.
  static func window(start: Int, end: Int) -> DayWindow? {
    DayWindow(startMinute: start, endMinute: max(end, start + step))
  }

  /// `08:00`; the day's end is `24:00`.
  static func label(_ minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
  }
}
