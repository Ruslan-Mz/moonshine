import Foundation
import MoonShineCore
import Testing

@testable import CalendarAdapter

/// Every raw value of the SDK headers (`EKTypes.h`, `EKEvent.h`) and one unknown value each.
@Suite struct EventKitMappingTests {
  @Test func authorization() {
    let expected: [Int: StoreAuthorization] = [
      0: .notDetermined, 1: .restricted, 2: .denied, 3: .fullAccess, 4: .writeOnly, 99: .restricted,
    ]
    for (raw, status) in expected { #expect(StoreAuthorization(raw: raw) == status, "\(raw)") }
  }

  @Test func participantStatus() {
    let expected: [Int: ParticipantStatus] = [
      0: .unknown, 1: .pending, 2: .accepted, 3: .declined, 4: .tentative, 5: .delegated,
      6: .completed, 7: .inProcess, 99: .unknown,
    ]
    for (raw, status) in expected { #expect(ParticipantStatus(raw: raw) == status, "\(raw)") }
  }

  @Test func eventStatus() {
    let expected: [Int: EventStatus] = [
      0: .none, 1: .confirmed, 2: .tentative, 3: .canceled, 99: .none,
    ]
    for (raw, status) in expected { #expect(EventStatus(raw: raw) == status, "\(raw)") }
  }

  @Test func availability() {
    let expected: [Int: Availability] = [
      -1: .notSupported, 0: .busy, 1: .free, 2: .tentative, 3: .unavailable, 99: .notSupported,
    ]
    for (raw, value) in expected { #expect(Availability(raw: raw) == value, "\(raw)") }
  }

  @Test func calendarKind() {
    // 0 local, 1 CalDAV, 2 Exchange, 3 subscription, 4 birthday.
    let expected: [(Int, Bool, CalendarKind)] = [
      (0, false, .other), (1, false, .other), (2, false, .other), (3, false, .subscribed),
      (4, false, .birthdays), (1, true, .subscribed), (3, true, .subscribed), (4, true, .birthdays),
      (99, false, .other),
    ]
    for (type, subscribed, kind) in expected {
      #expect(
        CalendarKind(typeRaw: type, isSubscribed: subscribed) == kind, "\(type) \(subscribed)")
    }
  }

  @Test func whichAttendeeIsTheOwner() {
    #expect(ownerStatus(nil) == nil)
    #expect(ownerStatus([]) == nil)
    #expect(ownerStatus([RawAttendee(isCurrentUser: false, statusRaw: 2)]) == nil)
    #expect(
      ownerStatus([
        RawAttendee(isCurrentUser: false, statusRaw: 3),
        RawAttendee(isCurrentUser: true, statusRaw: 4),
        RawAttendee(isCurrentUser: true, statusRaw: 2),
      ]) == .tentative)
  }

  @Test func colours() {
    #expect(hexColor([0.4235, 0.5176, 0.6824]) == "#6C84AE")
    #expect(hexColor([1, 0, 0, 0.5]) == "#FF0000")
    #expect(hexColor([1.5, -1, 0.5]) == "#FF0080")
    #expect(hexColor([0.5, 0.5]) == nil)
  }

  @Test func recordsFromRawValues() {
    let calendar = CalendarRecord(
      RawCalendar(
        id: "c", title: "t", account: "a", rgb: [0, 0, 0], typeRaw: 1, isSubscribed: true))
    #expect(calendar.kind == .subscribed)
    #expect(calendar.colorHex == "#000000")
    #expect(
      CalendarRecord(
        RawCalendar(id: "c", title: "t", account: nil, rgb: nil, typeRaw: 0, isSubscribed: false)
      ).colorHex == nil)

    let start = Date(timeIntervalSinceReferenceDate: 0)
    let event = EventRecord(
      RawEvent(
        id: "e", calendarID: "c", calendarTypeRaw: 4, calendarIsSubscribed: false, title: "x",
        start: start, end: start.addingTimeInterval(60), isAllDay: false, timeZone: nil,
        statusRaw: 2, attendees: [RawAttendee(isCurrentUser: true, statusRaw: 1)],
        organizerIsCurrentUser: true, availabilityRaw: 1))
    #expect(event.calendarKind == .birthdays)
    #expect(event.status == .tentative)
    #expect(event.myStatus == .pending)
    #expect(event.iAmOrganizer)
    #expect(event.availability == .free)
  }
}
