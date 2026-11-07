import AppKit
import Foundation
import MoonShineCore
import OmniFocusAdapter

/// Live's change signals (S4-4b-2, ADR-0011): OmniFocus' state from the Mac's app
/// notifications, after one reading, and the timer. Observing opens and starts nothing.
struct MacChangeSignals: ChangeSignalSource {
  static let names = [
    NSWorkspace.didActivateApplicationNotification,
    NSWorkspace.didDeactivateApplicationNotification,
    NSWorkspace.didLaunchApplicationNotification,
    NSWorkspace.didTerminateApplicationNotification,
  ]

  let bundleIdentifier: String
  let center: NotificationCenter
  let reading: @Sendable () -> OmniFocusState
  let interval: Duration
  let sleep: @Sendable (Duration) async throws -> Void

  init(
    bundleIdentifier: String = OmniFocusBridge.bundleIdentifier,
    center: NotificationCenter = NSWorkspace.shared.notificationCenter,
    reading: @escaping @Sendable () -> OmniFocusState = RunningOmniFocus.now,
    interval: Duration = RefreshCoordinator.minimumTimerInterval,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.center = center
    self.reading = reading
    self.interval = interval
    self.sleep = sleep
  }

  /// A launch is background until OmniFocus comes to the front; a deactivate that ends with the
  /// app is a quit.
  static func state(after name: Notification.Name, isTerminated: Bool) -> OmniFocusState? {
    switch name {
    case NSWorkspace.didActivateApplicationNotification: .frontmost
    case NSWorkspace.didDeactivateApplicationNotification: isTerminated ? .notRunning : .background
    case NSWorkspace.didLaunchApplicationNotification: .background
    case NSWorkspace.didTerminateApplicationNotification: .notRunning
    default: nil
    }
  }

  /// The observers and the reading share one main-actor turn, so no notification is handled
  /// between them: the reading is never older than a state yielded after it. The timer waits a
  /// second past the interval, so a tick is never skipped for arriving a hair early against the
  /// coordinator's last start (ADR-0011's timer rule).
  func signals() -> AsyncStream<ChangeSignal> {
    let (stream, continuation) = AsyncStream.makeStream(of: ChangeSignal.self)
    let observers = Observers()
    let (center, bundleIdentifier, reading) = (center, bundleIdentifier, reading)
    Task { @MainActor in
      observers.list = Self.names.map { name in
        center.addObserver(forName: name, object: nil, queue: .main) { note in
          guard
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == bundleIdentifier,
            let state = Self.state(after: note.name, isTerminated: app.isTerminated)
          else { return }
          continuation.yield(.omniFocus(state))
        }
      }
      continuation.yield(.omniFocus(reading()))
    }
    let (sleep, tick) = (sleep, interval + .seconds(1))
    let timer = Task {
      while true {
        do { try await sleep(tick) } catch { return }
        guard !Task.isCancelled else { return }
        continuation.yield(.timer)
      }
    }
    continuation.onTermination = { _ in
      timer.cancel()
      Task { @MainActor in
        for observer in observers.list { center.removeObserver(observer) }
        observers.list = []
      }
    }
    return stream
  }
}

/// The observers of one stream, touched on the main actor only.
@MainActor private final class Observers: Sendable {
  var list: [any NSObjectProtocol] = []

  nonisolated init() {}
}
