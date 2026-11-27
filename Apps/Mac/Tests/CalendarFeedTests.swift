import AppKit
import Foundation
import MoonShineCore
import MoonShineFixtures
import Synchronization
import Testing

@testable import MoonShineMac

/// A calendar provider that counts its calls and can hold its event reads at a gate. Invented
/// values only; never EventKit (CLAUDE.md rule 5).
final class FakeCalendar: CalendarProvider, Sendable {
  struct Calls: Equatable {
    var access = 0
    var request = 0
    var calendars = 0
    var events: [DateInterval] = []
  }

  struct State {
    var access: CalendarAccess
    var afterRequest: CalendarAccess = .granted
    var calls = Calls()
    var throwing = false
    var gated = false
    var gates: [CheckedContinuation<Void, Never>] = []
    var streams: [AsyncStream<Void>.Continuation] = []
  }

  let state: Mutex<State>

  init(access: CalendarAccess = .granted) {
    state = Mutex(State(access: access))
  }

  var calls: Calls { state.withLock { $0.calls } }
  var waiting: Int { state.withLock { $0.gates.count } }

  func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

  static let calendar = CalendarInfo(
    id: CalendarID("invented"), title: "Invented calendar", account: "Invented account",
    colorHex: nil, kind: .other)

  /// One event at the interval's start, so a test can tell which day's read landed.
  static func event(at start: Date) -> CalendarEvent {
    CalendarEvent(
      id: "invented-\(Int(start.timeIntervalSince1970))", calendarID: calendar.id,
      calendarKind: .other, title: "Invented event", start: start,
      end: start.addingTimeInterval(3_600))!
  }

  func access() async -> CalendarAccess {
    state.withLock {
      $0.calls.access += 1
      return $0.access
    }
  }

  func requestAccess() async -> CalendarAccess {
    state.withLock {
      $0.calls.request += 1
      $0.access = $0.afterRequest
      return $0.access
    }
  }

  func calendars() async -> CalendarRead<[CalendarInfo]> {
    state.withLock {
      $0.calls.calendars += 1
      return $0.access == .granted ? .read([Self.calendar], skipped: 0) : .unavailable($0.access)
    }
  }

  func events(in interval: DateInterval) async throws -> CalendarRead<[CalendarEvent]> {
    let gated = state.withLock {
      $0.calls.events.append(interval)
      return $0.gated
    }
    if gated { await withCheckedContinuation { gate in state.withLock { $0.gates.append(gate) } } }
    let (access, throwing) = state.withLock { ($0.access, $0.throwing) }
    if throwing { throw CalendarRangeError.tooLong }
    guard access == .granted else { return .unavailable(access) }
    return .read([Self.event(at: interval.start)], skipped: 0)
  }

  /// A new stream per call, as the system's: a stream whose reader stopped is finished.
  func changes() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    state.withLock { $0.streams.append(continuation) }
    return stream
  }

  func change() {
    for stream in state.withLock({ $0.streams }) { stream.yield() }
  }

  func release() {
    let gates = state.withLock {
      let gates = $0.gates
      $0.gates = []
      return gates
    }
    for gate in gates { gate.resume() }
  }
}

@MainActor
func waitUntil(_ condition: () -> Bool) async {
  for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

/// Lets queued work run: what a broken feed would do happens within it.
@MainActor
func settle() async {
  for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(5)) }
}

/// The calendar feed (S4-3d): reads, the change stream, activation, pause and connect.
@MainActor @Suite(.serialized) struct CalendarFeedTests {
  static let day = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 86_400)
  static let nextDay = DateInterval(start: day.end, duration: 86_400)

  let fake = FakeCalendar()
  let center = NotificationCenter()

  func feed(_ fake: FakeCalendar? = nil) -> CalendarFeed {
    CalendarFeed(provider: fake ?? self.fake, center: center)
  }

  func activate() {
    center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  @Test func accessIsUnknownUntilTheFirstRead() async {
    let feed = feed()
    #expect(feed.access == nil)
    #expect(fake.calls == FakeCalendar.Calls())
  }

  @Test func aReadOfTheShownDayHoldsItsEventsAndCalendars() async {
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.events.value != nil }
    #expect(feed.access == .granted)
    #expect(feed.events.value == [FakeCalendar.event(at: Self.day.start)])
    #expect(feed.calendars == [FakeCalendar.calendar])
    #expect(fake.calls.events == [Self.day])
  }

  /// Three changes while a read is in flight: one follow-up read, never three.
  @Test func aBurstOfChangesIsOneFollowUpRead() async {
    fake.set { $0.gated = true }
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { fake.waiting == 1 }
    fake.change()
    fake.change()
    fake.change()
    await settle()
    fake.set { $0.gated = false }
    fake.release()
    await waitUntil { fake.calls.events.count == 2 && feed.events.value != nil }
    await settle()
    #expect(fake.calls.events.count == 2)
  }

  @Test func aReadThatThrowsIsNoCalendarFactNotNoEvents() async {
    fake.set { $0.throwing = true }
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.access != nil }
    await settle()
    #expect(feed.access == .granted)
    #expect(feed.events.value == nil)
  }

  /// Access turned off in System Settings: the events read before go.
  @Test func revokedAccessDropsTheEventsAndCalendars() async {
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.events.value != nil }
    fake.set { $0.access = .denied }
    activate()
    await waitUntil { feed.access == .denied }
    #expect(feed.events == .unavailable(.denied))
    #expect(feed.calendars.isEmpty)
  }

  /// Access allowed in System Settings: switching back fills the rail, no relaunch.
  @Test func anActivationAfterAGrantReadsTheEvents() async {
    let fake = FakeCalendar(access: .denied)
    let feed = feed(fake)
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.access == .denied }
    #expect(feed.events.value == nil)
    fake.set { $0.access = .granted }
    activate()
    await waitUntil { feed.events.value != nil }
    #expect(feed.events.value?.count == 1)
  }

  /// A paused source reads nothing: no change, no activation; it holds no events (ADR-0012).
  @Test func aPausedFeedReadsNothingAndHoldsNoEvents() async {
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.events.value != nil }
    feed.pause()
    let calls = fake.calls
    fake.change()
    activate()
    feed.show(day: Self.nextDay)
    await settle()
    #expect(fake.calls == calls)
    #expect(feed.events.value == nil)
  }

  /// Live, Demo, Live: the change stream follows again.
  @Test func aResumedFeedFollowsChangesAgain() async {
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.events.value != nil }
    feed.pause()
    feed.resume()
    await waitUntil { fake.calls.events.count == 2 }
    fake.change()
    await waitUntil { fake.calls.events.count == 3 }
    #expect(fake.calls.events.count == 3)
    #expect(feed.events.value != nil)
  }

  /// A read for a day no longer shown lands nowhere; the shown day's read follows it.
  @Test func aLateReadOfAnEarlierDayIsDropped() async {
    fake.set { $0.gated = true }
    let feed = feed()
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { fake.waiting == 1 }
    feed.show(day: Self.nextDay)
    fake.set { $0.gated = false }
    fake.release()
    await waitUntil { fake.calls.events.count == 2 && feed.events.value != nil }
    await settle()
    #expect(fake.calls.events == [Self.day, Self.nextDay])
    #expect(feed.events.value == [FakeCalendar.event(at: Self.nextDay.start)])
  }

  /// `Connect calendars…` asks once, however often it is pressed while it asks.
  @Test func connectAsksOnceThenReads() async {
    let fake = FakeCalendar(access: .notDetermined)
    let feed = feed(fake)
    feed.show(day: Self.day)
    feed.resume()
    await waitUntil { feed.access == .notDetermined }
    feed.connect()
    #expect(feed.isConnecting)
    feed.connect()
    await waitUntil { feed.events.value != nil }
    #expect(fake.calls.request == 1)
    #expect(!feed.isConnecting)
    #expect(feed.access == .granted)
  }

  @Test func connectAsksNothingOnceAccessIsKnownOtherThanNotAsked() async {
    let feed = feed()
    feed.resume()
    await waitUntil { feed.access == .granted }
    feed.connect()
    await settle()
    #expect(fake.calls.request == 0)
  }
}

/// The row under the rail, and `Not now` (`design/screens/today.md` § Calendar).
@MainActor @Suite struct CalendarRowTests {
  static let zone = TimeZone(identifier: "Europe/Riga")!
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
  }

  func row(_ access: CalendarAccess?, notNow: Date? = nil, now: Date = date(11, 27, 12))
    -> CalendarRow?
  {
    CalendarRow(access: access, notNow: notNow, now: now, calendar: Self.calendar)
  }

  @Test func eachAccessHasItsRow() {
    #expect(row(nil) == nil)
    #expect(row(.notDetermined) == .connect)
    #expect(row(.denied) == .off)
    #expect(row(.writeOnly) == .off)
    #expect(row(.restricted) == nil)
    #expect(row(.granted) == nil)
  }

  /// Pressed late on 27 Nov: hidden through 26 Dec, back on 27 Dec, by calendar days.
  @Test func notNowHidesTheConnectRowForThirtyDays() {
    let pressed = Self.date(11, 27, 23, 50)
    #expect(row(.notDetermined, notNow: pressed, now: Self.date(11, 27, 23, 55)) == nil)
    #expect(row(.notDetermined, notNow: pressed, now: Self.date(12, 26, 23, 59)) == nil)
    #expect(row(.notDetermined, notNow: pressed, now: Self.date(12, 27, 0, 0)) == .connect)
  }

  @Test func aNotNowAfterTodayHidesNothing() {
    #expect(row(.notDetermined, notNow: Self.date(12, 1, 9), now: Self.date(11, 27, 9)) == .connect)
  }

  @Test func notNowLeavesTheOffRow() {
    #expect(row(.denied, notNow: Self.date(11, 27, 9), now: Self.date(11, 27, 10)) == .off)
  }

  @Test func theRowsSayTheDesignsWords() {
    #expect(
      CalendarRow.connect.sentence == "Calendar is not connected. Events stay on this device.")
    #expect(CalendarRow.off.sentence == "Calendar access is off for MoonShine.")
  }

  /// No event title, calendar or account name reaches a row or a notice (owner, 2026-11-27).
  @Test func noRowOrNoticeNamesAnEventOrACalendar() {
    let names =
      DemoCalendar.events.compactMap(\.title) + DemoCalendar.calendars.map(\.title)
      + DemoCalendar.calendars.compactMap(\.account)
      + [FakeCalendar.calendar.title, "Invented event", "Invented account"]
    let outcomes: [OpenOutcome] = [
      .opened, .noteNotFound, .vaultUnavailable(.notChosen), .vaultUnavailable(.unreadable),
      .notOpened, .demo, .superseded,
    ]
    let texts = CalendarRow.allCases.map(\.sentence) + outcomes.compactMap(LinkOpener.text)
    for text in texts {
      #expect(!text.isEmpty)
      for name in names { #expect(!text.contains(name)) }
    }
  }
}

/// The model's calendar: which provider, Demo's rules, Live's stored ones, `Not now`.
@MainActor @Suite(.serialized) struct CalendarModelTests {
  final class LiveFactory: @unchecked Sendable {
    var calls = 0
  }

  @Test func onlyLiveOutsideTheTestHostCallsTheSystemsProvider() {
    let factory = LiveFactory()
    let fake = FakeCalendar()
    let live: () -> any CalendarProvider = {
      factory.calls += 1
      return fake
    }
    #expect(AppModel.calendarProvider(for: .live, isTestHost: true, live: live) is DemoCalendar)
    #expect(AppModel.calendarProvider(for: .demo, isTestHost: false, live: live) is DemoCalendar)
    #expect(factory.calls == 0)
    #expect(AppModel.calendarProvider(for: .live, isTestHost: false, live: live) is FakeCalendar)
    #expect(factory.calls == 1)
  }

  /// A Live model a test builds without `calendars:` reads Demo's calendar, never the system's.
  @Test func aModelWithoutAProviderReadsDemosCalendarInLive() {
    let model = AppModel(isTestHost: false, settings: CountingSettings("live")) { _ in nil }
    #expect(model.source == .live)
    #expect(model.calendar.provider is DemoCalendar)
  }

  func liveModel(_ fake: FakeCalendar, settings: CountingSettings = CountingSettings("live"))
    -> AppModel
  {
    AppModel(
      isTestHost: false, settings: settings,
      calendars: { source -> any CalendarProvider in source == .live ? fake : DemoCalendar() },
      environments: { _ in nil })
  }

  /// Live, Demo, Live: Live's feed stops while Demo shows and follows again after.
  @Test func aSwitchPausesTheCalendarLeftAndResumesTheOneChosen() async {
    let fake = FakeCalendar()
    let model = liveModel(fake)
    model.showCalendarDay(CalendarFeedTests.day)
    model.start()
    await waitUntil { fake.calls.events.count == 1 }
    model.select(.demo)
    #expect(model.calendar.provider is DemoCalendar)
    fake.change()
    await settle()
    #expect(fake.calls.events.count == 1)
    model.select(.live)
    await waitUntil { fake.calls.events.count == 2 }
    fake.change()
    await waitUntil { fake.calls.events.count == 3 }
    #expect(fake.calls.events.count == 3)
  }

  /// Demo draws `design/demo-data.md`: 08:00–22:00 and its invented visibility, whatever Live
  /// stores (owner, 2026-11-27).
  @Test func demoKeepsItsWindowAndVisibilityLiveReadsTheStoredOnes() throws {
    let settings = CountingSettings("live")
    let wide = try #require(DayWindow(startMinute: 7 * 60, endMinute: 23 * 60))
    let stored = CalendarVisibility([
      CalendarID("invented"): CalendarSetting(show: false, countsAsBusy: false)
    ])
    settings.storedWindow = wide
    settings.storedVisibility = stored
    let model = liveModel(FakeCalendar(), settings: settings)
    #expect(model.dayWindow == wide)
    #expect(model.calendarVisibility == stored)
    #expect(model.dayRailInput(calendar: CalendarRowTests.calendar).window == wide)
    model.select(.demo)
    #expect(model.dayWindow == .standard)
    #expect(model.calendarVisibility == DemoCalendar.visibility)
    let input = model.dayRailInput(calendar: CalendarRowTests.calendar)
    #expect(input.window == .standard)
    #expect(input.isFrozen)
  }

  @Test func notNowHidesTheRowAndIsStored() async {
    let settings = CountingSettings("live")
    let model = liveModel(FakeCalendar(access: .notDetermined), settings: settings)
    model.start()
    await waitUntil { model.calendar.access == .notDetermined }
    #expect(model.dayRailInput(calendar: CalendarRowTests.calendar).row == .connect)
    model.dayRailInput(calendar: CalendarRowTests.calendar).notNow()
    #expect(model.dayRailInput(calendar: CalendarRowTests.calendar).row == nil)
    #expect(settings.notNowWrites.count == 1)
  }

  @Test func demoShowsNoRow() async {
    let model = AppModel(isTestHost: true, settings: NoSettings()) { _ in nil }
    model.start()
    await waitUntil { model.calendar.access != nil }
    #expect(model.calendar.access == .granted)
    #expect(model.dayRailInput(calendar: CalendarRowTests.calendar).row == nil)
  }
}
