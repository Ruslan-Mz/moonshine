import Foundation
import MoonShineCore

/// `CalendarProvider` over the system calendars (ADR-0012). Read-only; events stay in memory.
public struct EventKitCalendarProvider: CalendarProvider {
  private let store: any EventStoreReading

  public init() {
    self.init(store: SystemEventStore())
  }

  init(store: any EventStoreReading) {
    self.store = store
  }

  public func access() async -> CalendarAccess {
    switch await store.authorization() {
    case .notDetermined: .notDetermined
    case .restricted: .restricted
    case .denied: .denied
    case .fullAccess: .granted
    case .writeOnly: .writeOnly
    }
  }

  /// Prompts only when access was never asked for; after a grant the store forgets what it
  /// cached without access, so the next read sees the events.
  public func requestAccess() async -> CalendarAccess {
    let before = await access()
    guard before == .notDetermined else { return before }
    _ = await store.requestFullAccess()
    let after = await access()
    if after == .granted { await store.reset() }
    return after
  }

  public func calendars() async -> CalendarRead<[CalendarInfo]> {
    let access = await access()
    guard access == .granted else { return .unavailable(access) }
    let calendars = await store.calendars().map {
      CalendarInfo(
        id: CalendarID($0.id), title: $0.title, account: $0.account, colorHex: $0.colorHex,
        kind: $0.kind)
    }
    return .read(calendars, skipped: 0)
  }

  public func events(in interval: DateInterval) async throws -> CalendarRead<[CalendarEvent]> {
    try CalendarRange.check(interval)
    let access = await access()
    guard access == .granted else { return .unavailable(access) }
    guard interval.duration > 0 else { return .read([], skipped: 0) }
    var events: [CalendarEvent] = []
    var skipped = 0
    let records = await store.events(from: interval.start, to: interval.end)
    for (index, record) in records.enumerated() {
      guard let look = Self.look(record) else { continue }
      let start = Int(record.start.timeIntervalSinceReferenceDate)
      guard
        let event = CalendarEvent(
          id: record.id.map { "\($0)#\(start)" } ?? "\(record.calendarID)#\(start)#\(index)",
          calendarID: CalendarID(record.calendarID), title: record.title, start: record.start,
          end: record.end, isAllDay: record.isAllDay, display: look.display,
          occupiesTime: look.occupiesTime, timeZone: record.timeZone)
      else {
        skipped += 1
        continue
      }
      if event.overlaps(interval) { events.append(event) }
    }
    return .read(events, skipped: skipped)
  }

  public func changes() -> AsyncStream<Void> {
    store.changes()
  }

  /// `design/screens/settings-calendars.md` § Data: nil = hidden (declined, delegated,
  /// cancelled); tentative never occupies time; availability free never does either.
  static func look(_ record: EventRecord) -> (display: EventDisplay, occupiesTime: Bool)? {
    if record.status == .canceled { return nil }
    let answer = record.iAmOrganizer ? nil : record.myStatus
    if answer == .declined || answer == .delegated { return nil }
    let tentative =
      record.status == .tentative || record.availability == .tentative
      || answer == .pending || answer == .tentative || answer == .inProcess
    return (tentative ? .tentative : .normal, !tentative && record.availability != .free)
  }
}
