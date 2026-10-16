import CoreGraphics
@preconcurrency import EventKit
import Foundation
import MoonShineCore

/// The live calendar store, read-only (ADR-0012): full access to events only, never reminders,
/// never a write (`scripts/check-vault-writes.mjs`). The only file that imports EventKit.
actor SystemEventStore: EventStoreReading {
  private let store = EKEventStore()

  func authorization() -> StoreAuthorization {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: .notDetermined
    case .restricted: .restricted
    case .denied: .denied
    case .fullAccess: .fullAccess
    case .writeOnly: .writeOnly
    @unknown default: .restricted
    }
  }

  func requestFullAccess() async -> Bool {
    (try? await store.requestFullAccessToEvents()) ?? false
  }

  func reset() {
    store.reset()
  }

  func calendars() -> [CalendarRecord] {
    store.calendars(for: .event).map { calendar in
      CalendarRecord(
        id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source?.title,
        colorHex: Self.hex(calendar.cgColor), kind: Self.kind(calendar.type))
    }
  }

  func events(from start: Date, to end: Date) -> [EventRecord] {
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate).map { event in
      EventRecord(
        id: event.eventIdentifier, calendarID: event.calendar.calendarIdentifier,
        title: event.title, start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
        timeZone: event.timeZone, status: Self.status(event.status),
        myStatus: event.attendees?.first(where: \.isCurrentUser).map {
          Self.participant($0.participantStatus)
        },
        iAmOrganizer: event.organizer?.isCurrentUser ?? false,
        availability: Self.availability(event.availability))
    }
  }

  nonisolated func changes() -> AsyncStream<Void> {
    notificationStream(.EKEventStoreChanged, center: .default)
  }

  private static func kind(_ type: EKCalendarType) -> CalendarKind {
    switch type {
    case .subscription: .subscribed
    case .birthday: .birthdays
    default: .other
    }
  }

  private static func status(_ status: EKEventStatus) -> EventStatus {
    switch status {
    case .confirmed: .confirmed
    case .tentative: .tentative
    case .canceled: .canceled
    default: .none
    }
  }

  private static func participant(_ status: EKParticipantStatus) -> ParticipantStatus {
    switch status {
    case .pending: .pending
    case .accepted: .accepted
    case .declined: .declined
    case .tentative: .tentative
    case .delegated: .delegated
    case .completed: .completed
    case .inProcess: .inProcess
    default: .unknown
    }
  }

  private static func availability(_ availability: EKEventAvailability) -> Availability {
    switch availability {
    case .busy: .busy
    case .free: .free
    case .tentative: .tentative
    case .unavailable: .unavailable
    default: .notSupported
    }
  }

  private static func hex(_ color: CGColor?) -> String? {
    guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
      let components = color.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
      components.count >= 3
    else { return nil }
    let bytes = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
  }
}
