import AppKit
import Foundation
import MoonShineCore
import Observation

/// One source's calendar (S4-3d): its access, the shown day's events and the calendars, read
/// live from its provider and held in memory only (ADR-0012). A calendar change refreshes the
/// views and starts no import (ADR-0012, note of 2026-11-27). Nothing about an event or a
/// calendar is logged.
@MainActor @Observable
final class CalendarFeed {
  /// Nil until the first read: no row shows before it, so a granted Mac never sees the connect
  /// row flash at launch.
  private(set) var access: CalendarAccess?
  /// The shown day's events; `.unavailable` without access or after a read that threw: never
  /// "no events" (`design/screens/today.md` § Calendar).
  private(set) var events: CalendarRead<[CalendarEvent]> = .unavailable(.notDetermined)
  private(set) var calendars: [CalendarInfo] = []
  /// `Connect calendars…` is waiting for the system's answer.
  private(set) var isConnecting = false
  /// For tests: which provider the model chose.
  let provider: any CalendarProvider
  @ObservationIgnored private let center: NotificationCenter
  @ObservationIgnored private var isActive = false
  @ObservationIgnored private var day: DateInterval?
  /// The read in flight; while it runs, a change or a new day asks for one follow-up.
  @ObservationIgnored private var reading: Task<Void, Never>?
  @ObservationIgnored private var followUp = false
  /// Bumped by a new day and by a pause: a read started before lands nowhere.
  @ObservationIgnored private var latest = 0
  @ObservationIgnored private var following: Task<Void, Never>?
  @ObservationIgnored private var activation: (any NSObjectProtocol)?

  init(provider: any CalendarProvider, center: NotificationCenter = .default) {
    self.provider = provider
    self.center = center
  }

  /// Reads, then follows the calendar's changes and the app's activation. Idempotent.
  func resume() {
    guard !isActive else { return }
    isActive = true
    let changes = provider.changes()
    following = Task { [weak self] in
      for await _ in changes { self?.read() }
    }
    // A revoked access is seen when the owner switches back; a new grant reaches the app only
    // after it is reopened (owner, 2026-11-27, the live check of #74), so Settings says so.
    activation = center.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.read() }
    }
    read()
  }

  /// A source not shown reads nothing and holds no events (ADR-0012).
  func pause() {
    guard isActive else { return }
    isActive = false
    following?.cancel()
    following = nil
    if let activation { center.removeObserver(activation) }
    activation = nil
    latest += 1
    followUp = false
    events = .unavailable(access ?? .notDetermined)
    calendars = []
  }

  /// The day Today shows, in its zone.
  func show(day: DateInterval) {
    guard day != self.day else { return }
    self.day = day
    latest += 1
    read()
  }

  /// Asks the system once; a second press while it asks does nothing.
  func connect() {
    guard !isConnecting, access == .notDetermined else { return }
    isConnecting = true
    let provider = provider
    Task { [weak self] in
      _ = await provider.requestAccess()
      self?.isConnecting = false
      self?.read()
    }
  }

  /// One read in flight, at most one follow-up.
  func read() {
    guard isActive else { return }
    guard reading == nil else {
      followUp = true
      return
    }
    let (number, day, provider) = (latest, day, provider)
    reading = Task { [weak self] in
      let access = await provider.access()
      var events: CalendarRead<[CalendarEvent]> = .unavailable(access)
      var calendars: [CalendarInfo] = []
      if access == .granted {
        calendars = await provider.calendars().value ?? []
        if let day { events = (try? await provider.events(in: day)) ?? .unavailable(access) }
      }
      self?.land(number, access: access, events: events, calendars: calendars)
    }
  }

  private func land(
    _ number: Int, access: CalendarAccess, events: CalendarRead<[CalendarEvent]>,
    calendars: [CalendarInfo]
  ) {
    reading = nil
    if isActive && number == latest {
      self.access = access
      self.events = events
      self.calendars = calendars
    }
    if followUp {
      followUp = false
      read()
    }
  }
}
