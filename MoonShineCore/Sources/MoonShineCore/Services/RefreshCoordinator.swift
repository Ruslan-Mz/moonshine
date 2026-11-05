import Foundation

/// What the coordinator tells the app.
public enum RefreshEvent: Sendable, Equatable {
  case started(ImportTrigger)
  case committed
  case notCommitted
  /// A ⌘R or a launch was dropped because OmniFocus is not running (ADR-0011:68).
  case omniFocusNotRunning
  /// OmniFocus' first state, and every change after it.
  case omniFocusState(OmniFocusState)
}

/// Turns change signals into imports (ADR-0011): never while OmniFocus is frontmost unless ⌘R
/// asked, never while it is not running, the timer only after its interval. One import at a
/// time, with at most one request pending behind it; `ImportService`'s own follow-up stays a
/// guard and is never reached from here.
public actor RefreshCoordinator {
  public static let minimumTimerInterval: Duration = .seconds(15 * 60)

  /// One consumer.
  public nonisolated let events: AsyncStream<RefreshEvent>
  private let continuation: AsyncStream<RefreshEvent>.Continuation
  public nonisolated let service: ImportService
  public nonisolated let timerInterval: Duration

  /// nil until the first state arrives; requests wait for it.
  private var state: OmniFocusState?
  private var importing = false
  private var pending: Pending?
  /// The monotonic start of the last import that committed in this process.
  private var lastCommittedStart: Duration?

  /// The requests that joined while an import ran or before the first state.
  private struct Pending {
    var request: ImportRequest
    var triggers: Set<ImportTrigger>
    /// The first ⌘R that joined.
    var manual: ImportRequest?

    init(_ request: ImportRequest) {
      self.request = request
      triggers = [request.trigger]
      manual = request.trigger == .manual ? request : nil
    }

    mutating func join(_ later: ImportRequest) {
      request = request.joined(by: later)
      triggers.insert(later.trigger)
      if manual == nil, later.trigger == .manual { manual = later }
    }
  }

  /// The interval is at least 15 min (`design/screens/settings.md`).
  public init(service: ImportService, timerInterval: Duration) {
    (events, continuation) = AsyncStream.makeStream()
    self.service = service
    self.timerInterval = max(timerInterval, Self.minimumTimerInterval)
  }

  public func handle(_ signal: ChangeSignal) {
    switch signal {
    case .launch: enqueue(.launch)
    case .manual: enqueue(.manual)
    case .timer: enqueue(.timer)
    case .omniFocus(let new):
      let old = state
      state = new
      if old != new { continuation.yield(.omniFocusState(new)) }
      if old == .frontmost, new == .background { enqueue(.resignActive) } else { decide() }
    }
  }

  /// Handles every signal of `source`. A source that ends before giving a state leaves
  /// OmniFocus taken as not running, so no request waits for ever.
  public func run(_ source: any ChangeSignalSource) async {
    for await signal in source.signals() { handle(signal) }
    if state == nil { handle(.omniFocus(.notRunning)) }
  }

  private func enqueue(_ trigger: ImportTrigger) {
    let request = ImportRequest(trigger: trigger, signalledAt: service.clock.monotonic())
    if pending == nil { pending = Pending(request) } else { pending?.join(request) }
    decide()
  }

  /// Starts or drops the pending request once nothing runs and the state is known.
  private func decide() {
    guard !importing, let state, let pending else { return }
    self.pending = nil
    switch state {
    case .notRunning:
      if !pending.triggers.isDisjoint(with: [.manual, .launch]) {
        continuation.yield(.omniFocusNotRunning)
      }
    case .frontmost:
      // Held for resign-active. A joined ⌘R alone starts it, recorded as ⌘R unless
      // resign-active is in it (owner, 2026-11-05).
      guard let manual = pending.manual else { return }
      start(pending.request.trigger == .resignActive ? pending.request : manual)
    case .background:
      if pending.triggers == [.timer], let last = lastCommittedStart,
        service.clock.monotonic() - last < timerInterval
      {
        return
      }
      start(pending.request)
    }
  }

  private func start(_ request: ImportRequest) {
    importing = true
    let started = service.clock.monotonic()
    continuation.yield(.started(request.trigger))
    Task {
      do {
        try await service.run(request)
        finish(committedFrom: started)
      } catch {
        finish(committedFrom: nil)
      }
    }
  }

  private func finish(committedFrom started: Duration?) {
    importing = false
    if let started { lastCommittedStart = started }
    continuation.yield(started == nil ? .notCommitted : .committed)
    decide()
  }
}
