import Foundation
import MoonShineCore

/// `CalendarProvider` over the system calendars (ADR-0012). Read-only; events stay in memory.
public struct EventKitCalendarProvider: CalendarProvider {
  private let store: any EventStoreReading
  private let watch = AccessWatch()

  public init() {
    self.init(store: SystemEventStore())
  }

  init(store: any EventStoreReading) {
    self.store = store
  }

  /// Whenever access becomes granted, by MoonShine's prompt or later in System Settings, the
  /// store forgets what it cached without access, so the next read sees the events.
  public func access() async -> CalendarAccess {
    let access: CalendarAccess =
      switch await store.authorization() {
      case .notDetermined: .notDetermined
      case .restricted: .restricted
      case .denied: .denied
      case .fullAccess: .granted
      case .writeOnly: .writeOnly
      }
    if await watch.becameGranted(access) { await store.reset() }
    return access
  }

  /// Prompts only when access was never asked for.
  public func requestAccess() async -> CalendarAccess {
    let before = await access()
    guard before == .notDetermined else { return before }
    _ = await store.requestFullAccess()
    return await access()
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
    var events: [CalendarEvent] = []
    var skipped = 0
    // A zero-length query is the instant `start`: read one second and keep what `overlaps`
    // holds (`start ≤ T < end`), as every provider does.
    let end = interval.duration > 0 ? interval.end : interval.start.addingTimeInterval(1)
    let records = await store.events(from: interval.start, to: end)
    for (index, record) in records.enumerated() {
      guard let look = Self.look(record) else { continue }
      let start = Int(record.start.timeIntervalSinceReferenceDate)
      guard
        let event = CalendarEvent(
          id: record.id.map { "\($0)#\(start)" } ?? "\(record.calendarID)#\(start)#\(index)",
          calendarID: CalendarID(record.calendarID), calendarKind: record.calendarKind,
          title: record.title, start: record.start,
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

  /// The rules of `design/screens/settings-calendars.md` § Data, in their order: nil = hidden.
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

/// Remembers whether access was granted when last seen, to reset the store once per grant.
actor AccessWatch {
  private var granted = false

  /// True when `access` is granted and was not when last seen (or never seen).
  func becameGranted(_ access: CalendarAccess) -> Bool {
    defer { granted = access == .granted }
    return access == .granted && !granted
  }
}
