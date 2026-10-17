import Foundation

/// The system calendars (EventKit today), read live on each device (ADR-0012). Read-only until
/// the Act phase. Events are held in memory for the visible range only: never stored, synced,
/// logged or encoded. Intervals are half-open, `[start, end)`.
public protocol CalendarProvider: Sendable {
  func access() async -> CalendarAccess
  /// Asks the system once; returns the state after the answer.
  func requestAccess() async -> CalendarAccess
  func calendars() async -> CalendarRead<[CalendarInfo]>
  /// Events that overlap `interval` (`CalendarEvent.overlaps`). Throws
  /// `CalendarRangeError.tooLong` for an interval longer than `CalendarRange` allows.
  func events(in interval: DateInterval) async throws -> CalendarRead<[CalendarEvent]>
  /// One element per change of the calendar database.
  func changes() -> AsyncStream<Void>
}

/// The rows of `design/screens/settings-calendars.md` § Layout.
public enum CalendarAccess: Hashable, Sendable {
  case notDetermined, granted, denied, writeOnly, restricted
}

/// What a calendar read returned. "Could not read" is not "nothing there": without access the
/// day has no calendar fact at all (`design/screens/today.md` § Calendar).
public enum CalendarRead<Value: Sendable>: Sendable {
  case unavailable(CalendarAccess)
  /// `skipped`: items the provider dropped as invalid (an end before the start). Hidden
  /// events (declined, delegated, cancelled) are not read at all and are not counted here.
  case read(Value, skipped: Int)

  /// The value of a read; nil when unavailable.
  public var value: Value? {
    if case .read(let value, _) = self { value } else { nil }
  }
}

extension CalendarRead: Equatable where Value: Equatable {}

/// EventKit answers at most four years per query and silently cuts a longer span, so a longer
/// interval is refused instead of read in part.
public enum CalendarRange {
  public static let maxYears = 4

  /// Throws `tooLong` when `interval` ends after its start + four calendar years (Gregorian, UTC).
  public static func check(_ interval: DateInterval) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let limit = calendar.date(byAdding: .year, value: maxYears, to: interval.start),
      interval.end <= limit
    else { throw CalendarRangeError.tooLong }
  }
}

public enum CalendarRangeError: Error, Equatable, Sendable {
  case tooLong
}

// MARK: - Values (in memory only: not Codable; descriptions show no title, name or id)

/// A calendar's device-local identifier (`calendarIdentifier`). Never stored or synced.
public struct CalendarID: Hashable, Sendable, CustomStringConvertible, CustomReflectable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { "CalendarID(…)" }
  public var customMirror: Mirror { Mirror(self, children: []) }
}

public enum CalendarKind: Hashable, Sendable {
  case subscribed, birthdays, other
}

public struct CalendarInfo: Hashable, Sendable, Identifiable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  public let id: CalendarID
  public let title: String
  /// The account (EventKit source) title, for grouping in Settings.
  public let account: String?
  /// `#RRGGBB`; Core holds no colour type.
  public let colorHex: String?
  public let kind: CalendarKind

  public init(
    id: CalendarID, title: String, account: String?, colorHex: String?, kind: CalendarKind
  ) {
    self.id = id
    self.title = title
    self.account = account
    self.colorHex = colorHex
    self.kind = kind
  }

  public var description: String { "CalendarInfo(kind: \(kind))" }
  public var debugDescription: String { description }
  public var customMirror: Mirror { Mirror(self, children: ["kind": kind]) }
}

/// How an event is drawn; whether it takes time is a separate fact (`occupiesTime`).
public enum EventDisplay: Hashable, Sendable {
  case normal
  /// Drawn hatched.
  case tentative
}

/// One event, or one occurrence of a repeating event. Hidden events (declined, delegated,
/// cancelled) never become a value.
public struct CalendarEvent: Hashable, Sendable, Identifiable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  /// In-memory identity for lists; never stored or logged.
  public let id: String
  public let calendarID: CalendarID
  /// The kind of the event's calendar, so its default setting applies even before the calendar
  /// list is read again (owner, 2026-10-17).
  public let calendarKind: CalendarKind
  /// Nil when empty or blank; the UI shows `Busy`. EventKit exposes no private flag, so a
  /// private event keeps whatever title the store gives.
  public let title: String?
  public let start: Date
  public let end: Date
  public let isAllDay: Bool
  public let display: EventDisplay
  /// False for tentative events, events marked free and every all-day event.
  public let occupiesTime: Bool
  public let timeZone: TimeZone?

  /// Nil when `end` is before `start`; a zero-length event is allowed.
  public init?(
    id: String, calendarID: CalendarID, calendarKind: CalendarKind, title: String?, start: Date,
    end: Date, isAllDay: Bool = false, display: EventDisplay = .normal, occupiesTime: Bool = true,
    timeZone: TimeZone? = nil
  ) {
    guard end >= start else { return nil }
    self.id = id
    self.calendarID = calendarID
    self.calendarKind = calendarKind
    let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.title = trimmed.isEmpty ? nil : title
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.display = display
    self.occupiesTime = occupiesTime && !isAllDay
    self.timeZone = timeZone
  }

  /// `[start, end)` against `[interval.start, interval.end)`; a zero-length event belongs to
  /// the interval that holds its start. A zero-length query at T is the instant T: it holds
  /// the events with `start ≤ T < end` (owner, 2026-10-17), so not a zero-length event at T.
  public func overlaps(_ interval: DateInterval) -> Bool {
    if interval.duration == 0 { return start <= interval.start && interval.start < end }
    if start == end { return start >= interval.start && start < interval.end }
    return start < interval.end && end > interval.start
  }

  public var description: String {
    "CalendarEvent(display: \(display), occupiesTime: \(occupiesTime), isAllDay: \(isAllDay))"
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(
      self,
      children: ["display": display, "occupiesTime": occupiesTime, "isAllDay": isAllDay])
  }
}
