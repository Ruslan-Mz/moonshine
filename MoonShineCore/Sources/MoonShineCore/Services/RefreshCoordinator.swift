import Foundation

/// What the coordinator tells the app.
public enum RefreshEvent: Sendable, Equatable {
  case started(ImportTrigger)
  case committed
  case notCommitted(ImportFailure)
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
  /// How long a resign-active request waits before it joins, so a quit from the front is seen
  /// first (S4-4b-2).
  public nonisolated let settle: Duration
  private let sleep: @Sendable (Duration) async throws -> Void

  /// nil until the first state arrives; requests wait for it.
  private var state: OmniFocusState?
  private var importing = false
  private var pending: Pending?
  /// The monotonic start of the last import that committed in this process. Not seeded from
  /// the store: the wall clock can move, and after a relaunch the launch import commits first.
  private var lastCommittedStart: Duration?
  /// The resign-active request waiting out its settle; nothing starts meanwhile.
  private(set) var settling: ImportRequest?
  /// Bumped by every settle, so a settle that ended late cannot take a newer one's request.
  private var settleTag = 0
  /// Set while the source is not shown: requests are dropped, states still tracked.
  private var paused = false

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
  public init(
    service: ImportService, timerInterval: Duration, settle: Duration = .milliseconds(500),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    (events, continuation) = AsyncStream.makeStream()
    self.service = service
    self.timerInterval = max(timerInterval, Self.minimumTimerInterval)
    self.settle = settle
    self.sleep = sleep
  }

  /// A source not shown imports nothing and keeps tracking OmniFocus' state (owner,
  /// 2026-11-07); the switch back imports as ⌘R.
  public func setPaused(_ paused: Bool) {
    self.paused = paused
    decide()
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
      if old == .frontmost, new == .background {
        beginSettle()
      } else {
        // A quit or a return to OmniFocus within the settle was not a leave: its request never
        // joins (owner, 2026-11-07).
        if new != .background { settling = nil }
        decide()
      }
    }
  }

  /// Handles every signal of `source`. A source that ends before giving a state leaves
  /// OmniFocus taken as not running, so no request waits for ever.
  public func run(_ source: any ChangeSignalSource) async {
    for await signal in source.signals() { handle(signal) }
    if state == nil { handle(.omniFocus(.notRunning)) }
  }

  private func enqueue(_ trigger: ImportTrigger) {
    enqueue(ImportRequest(trigger: trigger, signalledAt: service.clock.monotonic()))
  }

  private func enqueue(_ request: ImportRequest) {
    if pending == nil { pending = Pending(request) } else { pending?.join(request) }
    decide()
  }

  /// The resign-active request is timed from the deactivate, so the settle counts in its wait.
  private func beginSettle() {
    settleTag += 1
    let tag = settleTag
    settling = ImportRequest(trigger: .resignActive, signalledAt: service.clock.monotonic())
    let (sleep, settle) = (self.sleep, self.settle)
    Task {
      try? await sleep(settle)
      settled(tag)
    }
  }

  private func settled(_ tag: Int) {
    guard tag == settleTag, let request = settling else { return }
    settling = nil
    enqueue(request)
  }

  /// Starts or drops the pending request once nothing runs or settles and the state is known.
  private func decide() {
    guard !importing, settling == nil, let state, let pending else { return }
    self.pending = nil
    guard !paused else { return }
    switch state {
    case .notRunning:
      if !pending.triggers.isDisjoint(with: [.manual, .launch]) {
        continuation.yield(.omniFocusNotRunning)
      }
    case .frontmost:
      // Dropped: resign-active brings its own request. A joined ⌘R alone starts it, recorded
      // as ⌘R unless resign-active is in it (owner, 2026-11-05).
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
        finish(.committed, from: started)
      } catch {
        let kind = (error as? any ImportFailureKind)?.importFailure ?? .other
        finish(.notCommitted(kind), from: nil)
      }
    }
  }

  /// `started` is the committed import's start.
  private func finish(_ event: RefreshEvent, from started: Duration?) {
    importing = false
    if let started { lastCommittedStart = started }
    continuation.yield(event)
    decide()
  }
}
