import Foundation

/// Show and Counts as busy for one calendar (`design/screens/settings-calendars.md`). Per
/// device, kept in local preferences; never synced (ADR-0012).
public struct CalendarSetting: Hashable, Sendable {
  public var show: Bool
  public var countsAsBusy: Bool

  public init(show: Bool, countsAsBusy: Bool) {
    self.show = show
    self.countsAsBusy = countsAsBusy
  }

  /// A calendar with Show off contributes nothing, even with Counts as busy on.
  public var occupiesTime: Bool { show && countsAsBusy }
}

/// The stored settings, by calendar; a calendar without an entry gets the default.
public struct CalendarVisibility: Hashable, Sendable {
  public var stored: [CalendarID: CalendarSetting]

  public init(_ stored: [CalendarID: CalendarSetting] = [:]) {
    self.stored = stored
  }

  /// The stored setting, else Show on and Counts as busy on, except subscribed and birthday
  /// calendars (off) (owner, 2026-10-16).
  public func setting(for calendar: CalendarInfo) -> CalendarSetting {
    setting(for: calendar.id, kind: calendar.kind)
  }

  public func setting(for id: CalendarID, kind: CalendarKind) -> CalendarSetting {
    stored[id] ?? CalendarSetting(show: true, countsAsBusy: kind == .other)
  }
}
