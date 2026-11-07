import AppKit
import Foundation
import MoonShineCore
import Synchronization
import Testing

@testable import MoonShineMac

/// The timer's sleep: every tick waits until the test opens the gate.
actor TickGate {
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private(set) var asked: [Duration] = []

  var sleepers: Int { waiting.count }

  func sleep(_ duration: Duration) async {
    asked.append(duration)
    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    for continuation in waiting { continuation.resume() }
    waiting = []
  }
}

/// A private centre that counts removed observers; never the system's.
final class CountingCenter: NotificationCenter, @unchecked Sendable {
  let removed = Mutex(0)

  override func removeObserver(_ observer: Any) {
    removed.withLock { $0 += 1 }
    super.removeObserver(observer)
  }
}

/// Where the reading ran.
final class ReadingLog: Sendable {
  let onMain = Mutex<[Bool]>([])
}

private let interval = Duration.seconds(15 * 60)
private let host = NSRunningApplication.current.bundleIdentifier ?? ""

private func signals(
  center: NotificationCenter, gate: TickGate, log: ReadingLog = ReadingLog(),
  bundleIdentifier: String = host, reading: OmniFocusState = .background
) -> MacChangeSignals {
  MacChangeSignals(
    bundleIdentifier: bundleIdentifier, center: center,
    reading: {
      log.onMain.withLock { $0.append(Thread.isMainThread) }
      return reading
    },
    interval: interval, sleep: { await gate.sleep($0) })
}

/// Yields until `condition` holds, bounded so a broken source fails instead of hanging.
@MainActor private func eventually(_ condition: () async -> Bool) async {
  for _ in 0..<10_000 where !(await condition()) { await Task.yield() }
}

@MainActor private func post(_ name: Notification.Name, on center: NotificationCenter) {
  center.post(
    name: name, object: nil,
    userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
}

@Suite struct MacChangeSignalsTests {
  @Test func eachOmniFocusNotificationMapsToItsState() {
    let table: [(Notification.Name, Bool, OmniFocusState?)] = [
      (NSWorkspace.didActivateApplicationNotification, false, .frontmost),
      (NSWorkspace.didDeactivateApplicationNotification, false, .background),
      (NSWorkspace.didDeactivateApplicationNotification, true, .notRunning),
      (NSWorkspace.didLaunchApplicationNotification, false, .background),
      (NSWorkspace.didTerminateApplicationNotification, false, .notRunning),
      (NSWorkspace.didTerminateApplicationNotification, true, .notRunning),
      (NSWorkspace.didWakeNotification, false, nil),
    ]
    for (name, isTerminated, state) in table {
      #expect(
        MacChangeSignals.state(after: name, isTerminated: isTerminated) == state,
        "\(name.rawValue) \(isTerminated)")
    }
  }

  @MainActor @Test func theSourceYieldsTheCurrentStateFirstThenOmniFocusChanges() async {
    let (center, gate, log) = (NotificationCenter(), TickGate(), ReadingLog())
    var iterator = signals(center: center, gate: gate, log: log).signals().makeAsyncIterator()
    #expect(await iterator.next() == .omniFocus(.background))
    #expect(log.onMain.withLock { $0 } == [true])
    for name in [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didDeactivateApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didLaunchApplicationNotification,
    ] {
      post(name, on: center)
    }
    var states: [ChangeSignal?] = []
    for _ in 0..<4 { states.append(await iterator.next()) }
    #expect(
      states == [
        .omniFocus(.frontmost), .omniFocus(.background), .omniFocus(.notRunning),
        .omniFocus(.background),
      ])
  }

  @MainActor @Test func notificationsForAnotherAppAreIgnored() async {
    let (center, gate) = (NotificationCenter(), TickGate())
    let source = signals(center: center, gate: gate, bundleIdentifier: "com.example.other")
    var iterator = source.signals().makeAsyncIterator()
    #expect(await iterator.next() == .omniFocus(.background))
    post(NSWorkspace.didActivateApplicationNotification, on: center)
    post(NSWorkspace.didTerminateApplicationNotification, on: center)
    // The next signal is the timer's: the posts gave none.
    await eventually { await gate.sleepers > 0 }
    await gate.open()
    #expect(await iterator.next() == .timer)
  }

  @MainActor @Test func theTimerTicksEveryIntervalPlusOneSecond() async {
    let gate = TickGate()
    var iterator = signals(center: NotificationCenter(), gate: gate).signals()
      .makeAsyncIterator()
    #expect(await iterator.next() == .omniFocus(.background))
    for _ in 0..<3 {
      await eventually { await gate.sleepers > 0 }
      await gate.open()
      #expect(await iterator.next() == .timer)
    }
    await eventually { await gate.sleepers > 0 }
    #expect(await gate.asked == Array(repeating: interval + .seconds(1), count: 4))
  }

  @MainActor @Test func endingTheStreamStopsTheTimerAndTheObservers() async {
    let (center, gate) = (CountingCenter(), TickGate())
    let stream = signals(center: center, gate: gate).signals()
    let consumer = Task { for await _ in stream {} }
    await eventually { await gate.sleepers > 0 }
    consumer.cancel()
    await consumer.value
    await eventually { center.removed.withLock { $0 } == MacChangeSignals.names.count }
    #expect(center.removed.withLock { $0 } == MacChangeSignals.names.count)
    // The sleeping tick wakes cancelled: no tick and no further sleep.
    await gate.open()
    for _ in 0..<500 { await Task.yield() }
    #expect(await gate.asked.count == 1)
  }
}
