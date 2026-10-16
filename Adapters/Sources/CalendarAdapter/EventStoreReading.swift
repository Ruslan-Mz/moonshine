import Foundation
import MoonShineCore

/// What the adapter reads from the system calendar store. `SystemEventStore` is the live one and
/// the only file that imports EventKit; tests use a fake, so no test touches the real store.
protocol EventStoreReading: Sendable {
  func authorization() async -> StoreAuthorization
  /// Shows the system prompt for full access to events; true when granted.
  func requestFullAccess() async -> Bool
  /// Drops what the store cached before access was granted.
  func reset() async
  func calendars() async -> [CalendarRecord]
  func events(from start: Date, to end: Date) async -> [EventRecord]
  func changes() -> AsyncStream<Void>
}

enum StoreAuthorization: Sendable {
  case notDetermined, restricted, denied, fullAccess, writeOnly
}

enum ParticipantStatus: Sendable {
  case unknown, pending, accepted, declined, tentative, delegated, completed, inProcess
}

enum EventStatus: Sendable {
  case none, confirmed, tentative, canceled
}

enum Availability: Sendable {
  case notSupported, busy, free, tentative, unavailable
}

struct CalendarRecord: Sendable {
  var id: String
  var title: String
  var account: String?
  var colorHex: String?
  var kind: CalendarKind
}

struct EventRecord: Sendable {
  /// Nil when the store gives none; the provider then builds an in-memory one.
  var id: String?
  var calendarID: String
  var title: String?
  var start: Date
  var end: Date
  var isAllDay: Bool
  var timeZone: TimeZone?
  var status: EventStatus
  /// The owner's own answer; nil with no attendees or when the owner is not among them.
  var myStatus: ParticipantStatus?
  var iAmOrganizer: Bool
  var availability: Availability
}

/// Posts of `name` as a stream; when the stream ends, the relay stops (`didStop`, for tests).
func notificationStream(
  _ name: Notification.Name, center: NotificationCenter,
  didStop: @escaping @Sendable () -> Void = {}
) -> AsyncStream<Void> {
  AsyncStream { continuation in
    let relay = Task {
      for await _ in center.notifications(named: name) { continuation.yield() }
      didStop()
    }
    continuation.onTermination = { _ in relay.cancel() }
  }
}
