import Foundation
import MoonShineCore
import Synchronization

/// An `ImportClock` for tests, moved by hand; both clocks move together.
public final class SettableClock: Sendable {
  private let state: Mutex<(wall: Date, monotonic: Duration)>

  public init(_ date: Date) {
    state = Mutex((date, .zero))
  }

  public var clock: ImportClock {
    ImportClock(
      wall: { self.state.withLock { $0.wall } },
      monotonic: { self.state.withLock { $0.monotonic } })
  }

  public func advance(by duration: Duration) {
    state.withLock {
      $0.wall +=
        Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18
      $0.monotonic += duration
    }
  }

  public func set(_ date: Date) {
    state.withLock {
      $0.monotonic += .milliseconds(Int64((date.timeIntervalSince($0.wall) * 1000).rounded()))
      $0.wall = date
    }
  }
}
