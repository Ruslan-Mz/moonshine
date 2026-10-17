import CoreGraphics
@preconcurrency import EventKit
import Foundation
import MoonShineCore

/// The live calendar store, read-only (ADR-0012): full access to events only, never reminders,
/// never a write (`scripts/check-vault-writes.mjs`). The only file that imports EventKit; it
/// unwraps raw values and leaves every mapping to `EventKitMapping.swift`, which is tested.
actor SystemEventStore: EventStoreReading {
  private let store = EKEventStore()

  func authorization() -> StoreAuthorization {
    StoreAuthorization(raw: EKEventStore.authorizationStatus(for: .event).rawValue)
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
        RawCalendar(
          id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source?.title,
          rgb: Self.rgb(calendar.cgColor), typeRaw: calendar.type.rawValue,
          isSubscribed: calendar.isSubscribed))
    }
  }

  func events(from start: Date, to end: Date) -> [EventRecord] {
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate).map { event in
      EventRecord(
        RawEvent(
          id: event.eventIdentifier, calendarID: event.calendar.calendarIdentifier,
          calendarTypeRaw: event.calendar.type.rawValue,
          calendarIsSubscribed: event.calendar.isSubscribed, title: event.title,
          start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
          timeZone: event.timeZone, statusRaw: event.status.rawValue,
          attendees: event.attendees?.map {
            RawAttendee(isCurrentUser: $0.isCurrentUser, statusRaw: $0.participantStatus.rawValue)
          },
          organizerIsCurrentUser: event.organizer?.isCurrentUser ?? false,
          availabilityRaw: event.availability.rawValue))
    }
  }

  nonisolated func changes() -> AsyncStream<Void> {
    notificationStream(.EKEventStoreChanged, center: .default)
  }

  private static func rgb(_ color: CGColor?) -> [Double]? {
    guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
      let components = color.converted(to: srgb, intent: .defaultIntent, options: nil)?.components
    else { return nil }
    return components.map { Double($0) }
  }
}
