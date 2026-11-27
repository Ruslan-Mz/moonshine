import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

/// The calendar rules as `StandardSettings` keeps them (S4-3d), over an in-memory storage:
/// every value is checked on read, and a toggle keeps every other stored entry.
@Suite struct CalendarSettingsTests {
  static let a = CalendarID("invented-a")
  static let b = CalendarID("invented-b")
  static let visibilityKey = "calendarSettings"
  static let windowKey = "dayWindow"
  static let notNowKey = "calendarNotNow"

  func settings(_ values: [String: Data] = [:], isTestHost: Bool = false)
    -> (StandardSettings, RecordingStorage)
  {
    let storage = RecordingStorage()
    for (key, value) in values { storage.set(value, forKey: key) }
    return (StandardSettings(storage: storage, isTestHost: isTestHost), storage)
  }

  func json(_ text: String) -> Data { Data(text.utf8) }

  func object(_ data: Data?) -> [String: Any]? {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }

  // MARK: Show and Counts as busy

  @Test func aSettingRoundTripsAndOthersKeepTheirKindDefault() {
    let (settings, _) = settings()
    settings.setCalendarSetting(CalendarSetting(show: false, countsAsBusy: true), for: Self.a)
    settings.setCalendarSetting(CalendarSetting(show: true, countsAsBusy: false), for: Self.b)
    let visibility = settings.calendarVisibility
    #expect(visibility.stored[Self.a] == CalendarSetting(show: false, countsAsBusy: true))
    #expect(visibility.stored[Self.b] == CalendarSetting(show: true, countsAsBusy: false))
    #expect(
      visibility.setting(for: CalendarID("invented-c"), kind: .subscribed)
        == CalendarSetting(show: true, countsAsBusy: false))
  }

  @Test(arguments: ["not json", "[1, 2]", "\"text\"", "12", ""])
  func aValueThatIsNotAnObjectReadsAsNoSettings(_ text: String) {
    let (settings, _) = settings([Self.visibilityKey: json(text)])
    #expect(settings.calendarVisibility == CalendarVisibility())
  }

  /// Both booleans, as booleans; anything else is left out and its calendar gets the default.
  @Test func anEntryWithoutBothBooleansIsIgnoredAndTheOthersRead() {
    let (settings, _) = settings([
      Self.visibilityKey: json(
        #"{"invented-a": {"show": false, "busy": true}, "invented-b": {"show": true},"#
          + #" "invented-c": 5, "invented-d": {"show": 1, "busy": 0},"#
          + #" "invented-e": {"show": "yes", "busy": false}, "invented-f": null}"#)
    ])
    let read = settings.calendarVisibility.stored
    #expect(read == [Self.a: CalendarSetting(show: false, countsAsBusy: true)])
  }

  @Test func anEmptyOrOverlongIdIsIgnored() {
    let longest = String(repeating: "x", count: 256)
    let tooLong = String(repeating: "x", count: 257)
    let entry = #"{"show": true, "busy": true}"#
    let (settings, _) = settings([
      Self.visibilityKey: json(
        #"{"": \#(entry), "\#(longest)": \#(entry), "\#(tooLong)": \#(entry)}"#)
    ])
    #expect(Set(settings.calendarVisibility.stored.keys) == [CalendarID(longest)])
  }

  @Test func atMostFiveHundredEntriesAreReadInKeyOrder() {
    let entries = (0...500).map { String(format: #""id%03d": {"show": true, "busy": false}"#, $0) }
    let (settings, _) = settings([Self.visibilityKey: json("{\(entries.joined(separator: ","))}")])
    let stored = settings.calendarVisibility.stored
    #expect(stored.count == 500)
    #expect(stored[CalendarID("id499")] != nil)
    #expect(stored[CalendarID("id500")] == nil)
  }

  @Test func aReadWritesNothing() {
    let bad = json(#"{"invented-b": {"show": true}}"#)
    let (settings, storage) = settings([Self.visibilityKey: bad])
    let writes = storage.writes
    _ = settings.calendarVisibility
    #expect(storage.writes == writes)
    #expect(storage.data(forKey: Self.visibilityKey) == bad)
  }

  /// A toggle of one calendar replaces only its entry: an entry the read ignores stays.
  @Test func aToggleKeepsEveryOtherStoredEntryAsItIs() throws {
    let (settings, storage) = settings([
      Self.visibilityKey: json(
        #"{"invented-b": {"show": true}, "invented-c": {"show": false, "busy": false}}"#)
    ])
    settings.setCalendarSetting(CalendarSetting(show: false, countsAsBusy: false), for: Self.a)
    let stored = try #require(object(storage.data(forKey: Self.visibilityKey)))
    #expect(stored["invented-b"] as? [String: Bool] == ["show": true])
    #expect(stored["invented-c"] as? [String: Bool] == ["show": false, "busy": false])
    #expect(stored["invented-a"] as? [String: Bool] == ["show": false, "busy": false])
  }

  /// Data that is not an object holds nothing readable: the toggle writes its entry alone.
  @Test func aToggleOverUnreadableDataWritesItsEntryAlone() throws {
    let (settings, storage) = settings([Self.visibilityKey: json("not json")])
    settings.setCalendarSetting(CalendarSetting(show: true, countsAsBusy: false), for: Self.a)
    let stored = try #require(object(storage.data(forKey: Self.visibilityKey)))
    #expect(stored.count == 1)
    let read = settings.calendarVisibility.stored
    #expect(read == [Self.a: CalendarSetting(show: true, countsAsBusy: false)])
  }

  /// `JSONDecoder` reads a number out of `Double`'s range where `JSONSerialization` refuses
  /// the whole value: the toggle keeps what the read shows.
  @Test func aToggleOverBytesOnlyTheReadAcceptsKeepsTheReadEntries() throws {
    let (settings, storage) = settings([
      Self.visibilityKey: json(
        #"{"invented-a": {"show": false, "busy": true}, "invented-b": 1e400}"#)
    ])
    #expect(settings.calendarVisibility.stored[Self.a] != nil)
    settings.setCalendarSetting(CalendarSetting(show: true, countsAsBusy: true), for: Self.b)
    #expect(object(storage.data(forKey: Self.visibilityKey)) != nil)
    let read = settings.calendarVisibility.stored
    #expect(read[Self.a] == CalendarSetting(show: false, countsAsBusy: true))
    #expect(read[Self.b] == CalendarSetting(show: true, countsAsBusy: true))
  }

  /// The read takes 500: a new calendar past them is not stored, a stored one still changes.
  @Test func aNewCalendarPastFiveHundredIsNotStored() {
    let entries = (0..<500).map {
      String(format: #""id%03d": {"show": true, "busy": false}"#, $0)
    }
    let (settings, storage) = settings([
      Self.visibilityKey: json("{\(entries.joined(separator: ","))}")
    ])
    let writes = storage.writes
    let off = CalendarSetting(show: false, countsAsBusy: false)
    settings.setCalendarSetting(off, for: CalendarID("zz"))
    #expect(storage.writes == writes)
    let first = CalendarID("id000")
    settings.setCalendarSetting(off, for: first)
    #expect(settings.calendarVisibility.stored[first] == off)
  }

  /// The limit is 256 bytes, not characters: `ж` is two bytes in UTF-8.
  @Test func theIdLimitCountsBytes() {
    let longest = String(repeating: "ж", count: 128)
    let tooLong = String(repeating: "ж", count: 129)
    let entry = #"{"show": true, "busy": true}"#
    let (settings, _) = settings([
      Self.visibilityKey: json(#"{"\#(longest)": \#(entry), "\#(tooLong)": \#(entry)}"#)
    ])
    #expect(Set(settings.calendarVisibility.stored.keys) == [CalendarID(longest)])
  }

  @Test func aToggleWithAnIdTheReadWouldIgnoreWritesNothing() {
    let (settings, storage) = settings()
    let setting = CalendarSetting(show: true, countsAsBusy: true)
    settings.setCalendarSetting(setting, for: CalendarID(""))
    settings.setCalendarSetting(setting, for: CalendarID(String(repeating: "x", count: 257)))
    #expect(storage.writes.isEmpty)
  }

  // MARK: Day window

  @Test func aWindowRoundTrips() throws {
    let (settings, _) = settings()
    let wide = try #require(DayWindow(startMinute: 7 * 60, endMinute: 23 * 60))
    settings.setDayWindow(wide)
    #expect(settings.dayWindow == wide)
    let whole = try #require(DayWindow(startMinute: 0, endMinute: 24 * 60))
    settings.setDayWindow(whole)
    #expect(settings.dayWindow == whole)
  }

  @Test(arguments: [
    #"{"start": 1320, "end": 480}"#, #"{"start": 0, "end": 1441}"#, #"{"start": -15, "end": 600}"#,
    #"{"start": 480, "end": 490}"#, #"{"start": 470, "end": 900}"#, #"{"start": 480}"#,
    #"{"end": 900}"#, #"{"start": "480", "end": "900"}"#, #"{"start": 480.5, "end": 900}"#,
    "not json", "[480, 900]",
  ])
  func aWindowThatIsNotValidReadsAsStandard(_ text: String) {
    let (settings, _) = settings([Self.windowKey: json(text)])
    #expect(settings.dayWindow == .standard)
  }

  @Test func noWindowStoredReadsAsStandard() {
    #expect(settings().0.dayWindow == .standard)
  }

  @Test func aWindowOffTheQuarterHourIsNotWritten() throws {
    let (settings, storage) = settings()
    settings.setDayWindow(try #require(DayWindow(startMinute: 7 * 60 + 10, endMinute: 23 * 60)))
    #expect(storage.writes.isEmpty)
  }

  // MARK: Not now

  @Test func notNowRoundTrips() {
    let (settings, _) = settings()
    #expect(settings.calendarNotNow == nil)
    let pressed = Date(timeIntervalSinceReferenceDate: 815_000_000)
    settings.setCalendarNotNow(pressed)
    #expect(settings.calendarNotNow == pressed)
  }

  @Test(arguments: ["not json", "{}", #"{"day": "today"}"#, "12"])
  func notNowThatCannotBeReadIsNone(_ text: String) {
    #expect(settings([Self.notNowKey: json(text)]).0.calendarNotNow == nil)
  }

  // MARK: The test host

  @Test func aTestHostReadsAndWritesNone() throws {
    let stored = [
      Self.visibilityKey: json(#"{"invented-a": {"show": false, "busy": false}}"#),
      Self.windowKey: json(#"{"start": 420, "end": 1380}"#),
      Self.notNowKey: json(#"{"day": 815000000}"#),
    ]
    let (settings, storage) = settings(stored, isTestHost: true)
    let writes = storage.writes
    #expect(settings.calendarVisibility == CalendarVisibility())
    #expect(settings.dayWindow == .standard)
    #expect(settings.calendarNotNow == nil)
    settings.setCalendarSetting(CalendarSetting(show: true, countsAsBusy: true), for: Self.a)
    settings.setDayWindow(try #require(DayWindow(startMinute: 0, endMinute: 60)))
    settings.setCalendarNotNow(Date())
    #expect(storage.reads.isEmpty)
    #expect(storage.writes == writes)
  }
}
