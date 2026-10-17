import Foundation
import MoonShineCore

// EventKit values as `SystemEventStore` reads them: raw values only, so this file names no
// EventKit type and every case is tested. The raw values are those of the macOS SDK headers
// (`EKTypes.h`, `EKEvent.h`); an unknown value falls back to the calmest case.

/// One calendar, raw.
struct RawCalendar: Sendable {
  var id: String
  var title: String
  var account: String?
  /// sRGB red, green, blue (and alpha), 0...1; nil when the colour could not be converted.
  var rgb: [Double]?
  var typeRaw: Int
  var isSubscribed: Bool
}

/// One attendee, raw.
struct RawAttendee: Sendable {
  var isCurrentUser: Bool
  var statusRaw: Int
}

/// One event or occurrence, raw.
struct RawEvent: Sendable {
  var id: String?
  var calendarID: String
  var calendarTypeRaw: Int
  var calendarIsSubscribed: Bool
  var title: String?
  var start: Date
  var end: Date
  var isAllDay: Bool
  var timeZone: TimeZone?
  var statusRaw: Int
  var attendees: [RawAttendee]?
  var organizerIsCurrentUser: Bool
  var availabilityRaw: Int
}

extension StoreAuthorization {
  /// `EKAuthorizationStatus`: 0 not determined, 1 restricted, 2 denied, 3 full access (also the
  /// deprecated "authorized"), 4 write only.
  init(raw: Int) {
    self =
      switch raw {
      case 0: .notDetermined
      case 2: .denied
      case 3: .fullAccess
      case 4: .writeOnly
      default: .restricted
      }
  }
}

extension ParticipantStatus {
  /// `EKParticipantStatus`: 0 unknown … 7 in process.
  init(raw: Int) {
    self =
      switch raw {
      case 1: .pending
      case 2: .accepted
      case 3: .declined
      case 4: .tentative
      case 5: .delegated
      case 6: .completed
      case 7: .inProcess
      default: .unknown
      }
  }
}

extension EventStatus {
  /// `EKEventStatus`: 0 none, 1 confirmed, 2 tentative, 3 cancelled.
  init(raw: Int) {
    self =
      switch raw {
      case 1: .confirmed
      case 2: .tentative
      case 3: .canceled
      default: .none
      }
  }
}

extension Availability {
  /// `EKEventAvailability`: −1 not supported, 0 busy, 1 free, 2 tentative, 3 unavailable.
  init(raw: Int) {
    self =
      switch raw {
      case 0: .busy
      case 1: .free
      case 2: .tentative
      case 3: .unavailable
      default: .notSupported
      }
  }
}

extension CalendarKind {
  /// `EKCalendarType` 4 is birthdays; 3 (subscription) or a CalDAV calendar with
  /// `isSubscribed` is subscribed (`EKCalendar.h`).
  init(typeRaw: Int, isSubscribed: Bool) {
    self = typeRaw == 4 ? .birthdays : typeRaw == 3 || isSubscribed ? .subscribed : .other
  }
}

extension CalendarRecord {
  init(_ raw: RawCalendar) {
    self.init(
      id: raw.id, title: raw.title, account: raw.account, colorHex: raw.rgb.flatMap(hexColor),
      kind: CalendarKind(typeRaw: raw.typeRaw, isSubscribed: raw.isSubscribed))
  }
}

extension EventRecord {
  init(_ raw: RawEvent) {
    self.init(
      id: raw.id, calendarID: raw.calendarID,
      calendarKind: CalendarKind(
        typeRaw: raw.calendarTypeRaw, isSubscribed: raw.calendarIsSubscribed),
      title: raw.title, start: raw.start, end: raw.end, isAllDay: raw.isAllDay,
      timeZone: raw.timeZone, status: EventStatus(raw: raw.statusRaw),
      myStatus: ownerStatus(raw.attendees), iAmOrganizer: raw.organizerIsCurrentUser,
      availability: Availability(raw: raw.availabilityRaw))
  }
}

/// The owner's own answer: the first attendee who is the current user; nil with no attendees
/// or when the owner is not among them.
func ownerStatus(_ attendees: [RawAttendee]?) -> ParticipantStatus? {
  attendees?.first(where: \.isCurrentUser).map { ParticipantStatus(raw: $0.statusRaw) }
}

/// `#RRGGBB` from sRGB components; nil with fewer than three.
func hexColor(_ rgb: [Double]) -> String? {
  guard rgb.count >= 3 else { return nil }
  let bytes = rgb.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
  return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
}
