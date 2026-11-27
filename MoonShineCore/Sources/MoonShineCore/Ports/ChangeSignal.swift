import Foundation

/// "A source may have changed" (ADR-0011); it drives imports only. Calendar changes never join
/// it: the calendar feed follows its provider's own change stream and starts no import (ADR-0012,
/// note of 2026-11-27).
public enum ChangeSignal: Sendable, Equatable {
  case launch
  /// ⌘R.
  case manual
  case timer
  case omniFocus(OmniFocusState)
}

public enum OmniFocusState: Sendable, Equatable {
  case notRunning
  case background
  case frontmost
}

/// A Mac source (S4-4b-2) or Demo's. A source that reports OmniFocus yields its current state
/// first; one that ends without a state leaves OmniFocus taken as not running.
public protocol ChangeSignalSource: Sendable {
  func signals() -> AsyncStream<ChangeSignal>
}
