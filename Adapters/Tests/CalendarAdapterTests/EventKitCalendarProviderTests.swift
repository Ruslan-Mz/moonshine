import Foundation
import MoonShineCore
import Testing

@testable import CalendarAdapter

/// A store the tests control; counts what the provider asks of it. No EventKit anywhere.
actor FakeStore: EventStoreReading {
  var status: StoreAuthorization
  let grants: Bool
  var records: [EventRecord]
  var calendarRecords: [CalendarRecord] = []
  private(set) var reads = 0
  private(set) var prompts = 0
  private(set) var resets = 0
  nonisolated let stream: AsyncStream<Void>
  nonisolated let continuation: AsyncStream<Void>.Continuation

  init(_ status: StoreAuthorization, grants: Bool = true, records: [EventRecord] = []) {
    self.status = status
    self.grants = grants
    self.records = records
    (stream, continuation) = AsyncStream.makeStream(of: Void.self)
  }

  func authorization() -> StoreAuthorization { status }

  func requestFullAccess() -> Bool {
    prompts += 1
    status = grants ? .fullAccess : .denied
    return grants
  }

  func reset() { resets += 1 }

  func calendars() -> [CalendarRecord] {
    reads += 1
    return calendarRecords
  }

  func events(from start: Date, to end: Date) -> [EventRecord] {
    reads += 1
    // Like EventKit before a reset: what was read without access stays empty.
    return resets == 0 && prompts > 0 ? [] : records
  }

  nonisolated func changes() -> AsyncStream<Void> { stream }
}

let day = DateInterval(start: Date(timeIntervalSinceReferenceDate: 0), duration: 86_400)

func record(
  _ hour: Double = 10, hours: Double = 1, id: String? = "e", title: String? = "x",
  status: EventStatus = .confirmed, me: ParticipantStatus? = nil, organizer: Bool = false,
  availability: Availability = .busy
) -> EventRecord {
  let start = day.start.addingTimeInterval(hour * 3_600)
  return EventRecord(
    id: id, calendarID: "c", title: title, start: start,
    end: start.addingTimeInterval(hours * 3_600), isAllDay: false, timeZone: nil, status: status,
    myStatus: me, iAmOrganizer: organizer, availability: availability)
}

@Suite struct EventKitCalendarProviderTests {
  @Test func mapsEveryAuthorization() async {
    let cases: [(StoreAuthorization, CalendarAccess)] = [
      (.notDetermined, .notDetermined), (.restricted, .restricted), (.denied, .denied),
      (.fullAccess, .granted), (.writeOnly, .writeOnly),
    ]
    for (status, access) in cases {
      #expect(await EventKitCalendarProvider(store: FakeStore(status)).access() == access)
    }
  }

  @Test func withoutAccessNothingIsRead() async throws {
    for status in [StoreAuthorization.notDetermined, .restricted, .denied, .writeOnly] {
      let store = FakeStore(status, records: [record()])
      let provider = EventKitCalendarProvider(store: store)
      let access = await provider.access()
      #expect(try await provider.events(in: day) == .unavailable(access))
      #expect(await provider.calendars() == .unavailable(access))
      #expect(await store.reads == 0)
    }
  }

  @Test func refusesTooLongBeforeReading() async {
    let store = FakeStore(.fullAccess, records: [record()])
    let years = DateInterval(start: day.start, duration: 5 * 366 * 86_400)
    await #expect(throws: CalendarRangeError.tooLong) {
      try await EventKitCalendarProvider(store: store).events(in: years)
    }
    #expect(await store.reads == 0)
  }

  @Test func asksOnceAndReadsAfterTheGrant() async throws {
    let store = FakeStore(.notDetermined, records: [record()])
    let provider = EventKitCalendarProvider(store: store)
    #expect(await provider.requestAccess() == .granted)
    #expect(await store.resets == 1)
    #expect(try await provider.events(in: day).value?.count == 1)
    #expect(await provider.requestAccess() == .granted)
    #expect(await store.prompts == 1)

    let refused = FakeStore(.notDetermined, grants: false)
    #expect(await EventKitCalendarProvider(store: refused).requestAccess() == .denied)
    #expect(await refused.resets == 0)
    let denied = FakeStore(.denied)
    #expect(await EventKitCalendarProvider(store: denied).requestAccess() == .denied)
    #expect(await denied.prompts == 0)
  }

  @Test func displayAndOccupyingFollowTheTable() {
    func look(_ record: EventRecord) -> String {
      guard let look = EventKitCalendarProvider.look(record) else { return "hidden" }
      return "\(look.display) \(look.occupiesTime)"
    }
    // Hidden.
    #expect(look(record(status: .canceled)) == "hidden")
    #expect(look(record(me: .declined)) == "hidden")
    #expect(look(record(me: .delegated)) == "hidden")
    // Tentative, not occupying.
    for me in [ParticipantStatus.pending, .tentative, .inProcess] {
      #expect(look(record(me: me)) == "tentative false")
    }
    #expect(look(record(status: .tentative)) == "tentative false")
    #expect(look(record(availability: .tentative)) == "tentative false")
    // Normal, occupying: accepted, unknown, no attendees or not among them, organiser.
    for me in [ParticipantStatus.accepted, .unknown, .completed, nil] {
      #expect(look(record(me: me)) == "normal true")
    }
    #expect(look(record(me: .pending, organizer: true)) == "normal true")
    #expect(look(record(status: .none, availability: .notSupported)) == "normal true")
    // Availability free takes no time; out of office has no rule of its own.
    #expect(look(record(availability: .free)) == "normal false")
    #expect(look(record(me: .tentative, availability: .free)) == "tentative false")
    #expect(look(record(availability: .unavailable)) == "normal true")
    #expect(look(record(me: .tentative, availability: .unavailable)) == "tentative false")
  }

  @Test func skipsInvalidRecordsAndCountsThem() async throws {
    let store = FakeStore(
      .fullAccess,
      records: [record(hours: -1), record(hours: -1, status: .canceled), record(11)])
    let read = try await EventKitCalendarProvider(store: store).events(in: day)
    guard case .read(let events, let skipped) = read else {
      Issue.record("unavailable")
      return
    }
    #expect(events.count == 1)
    #expect(skipped == 1)
  }

  @Test func titlesIdsAndTheInterval() async throws {
    let store = FakeStore(
      .fullAccess,
      records: [
        record(9, title: ""), record(10, id: nil), record(10, id: nil), record(-1, hours: 1),
        record(24, hours: 1), record(23, hours: 1),
      ])
    let events = try #require(
      try await EventKitCalendarProvider(store: store).events(in: day).value)
    // The events ending at the day's start and starting at its end are not on the day.
    #expect(events.count == 4)
    #expect(events[0].title == nil)
    #expect(Set(events.map(\.id)).count == 4)
    let zero = DateInterval(start: day.start, duration: 0)
    #expect(
      try await EventKitCalendarProvider(store: store).events(in: zero) == .read([], skipped: 0))
  }

  @Test func calendarsKeepTheirKind() async {
    let store = FakeStore(.fullAccess)
    await store.setCalendars([
      CalendarRecord(id: "h", title: "h", account: "a", colorHex: "#C75C5C", kind: .subscribed)
    ])
    let calendars = await EventKitCalendarProvider(store: store).calendars().value
    #expect(calendars?.map(\.kind) == [.subscribed])
    #expect(calendars?.first?.colorHex == "#C75C5C")
  }

  @Test func changesArriveFromTheStore() async {
    let store = FakeStore(.fullAccess)
    store.continuation.yield()
    store.continuation.finish()
    var count = 0
    for await _ in EventKitCalendarProvider(store: store).changes() { count += 1 }
    #expect(count == 1)
  }

  @Test func theNotificationRelayStopsWithItsStream() async {
    let center = NotificationCenter()
    let name = Notification.Name("test.calendar.changed")
    let (stopped, stop) = AsyncStream.makeStream(of: Void.self)
    var stream: AsyncStream<Void>? = notificationStream(name, center: center) { stop.yield() }
    var iterator = stream!.makeAsyncIterator()
    // Post until the relay has subscribed and one post comes through.
    let poster = Task {
      while !Task.isCancelled {
        center.post(name: name, object: nil)
        try? await Task.sleep(for: .milliseconds(5))
      }
    }
    #expect(await iterator.next() != nil)
    poster.cancel()
    stream = nil
    iterator = AsyncStream<Void> { $0.finish() }.makeAsyncIterator()
    var stops = stopped.makeAsyncIterator()
    #expect(await stops.next() != nil)
  }
}

extension FakeStore {
  func setCalendars(_ records: [CalendarRecord]) { calendarRecords = records }
}
