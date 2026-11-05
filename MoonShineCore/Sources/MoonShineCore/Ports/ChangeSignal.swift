import Foundation

/// "A source may have changed" (ADR-0011). Calendar changes join this port later; they do not
/// start the importer.
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
