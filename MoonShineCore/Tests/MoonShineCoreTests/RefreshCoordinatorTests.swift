import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// Collects the coordinator's events.
actor EventLog {
  private(set) var events: [RefreshEvent] = []

  func append(_ event: RefreshEvent) {
    events.append(event)
  }

  func count(_ event: RefreshEvent) -> Int {
    events.filter { $0 == event }.count
  }

  var started: [ImportTrigger] {
    events.compactMap { if case .started(let trigger) = $0 { trigger } else { nil } }
  }
}

extension RefreshEvent {
  var endsAnImport: Bool {
    switch self {
    case .committed, .notCommitted: true
    default: false
    }
  }
}

/// Yields the given signals, then ends.
struct ListSource: ChangeSignalSource {
  let list: [ChangeSignal]

  func signals() -> AsyncStream<ChangeSignal> {
    AsyncStream { continuation in
      for signal in list { continuation.yield(signal) }
      continuation.finish()
    }
  }
}

/// A coordinator over a real `ImportService` and `InMemoryStore`, with one settable clock.
struct Rig {
  static let start = Date(timeIntervalSince1970: 1_790_000_000)

  let provider: GatedTaskProvider
  let time = SettableClock(Rig.start)
  let store = InMemoryStore()
  let service: ImportService
  let coordinator: RefreshCoordinator
  let log = EventLog()

  init(open: Bool = true, timerInterval: Duration = .seconds(15 * 60)) {
    provider = GatedTaskProvider(open: open)
    service = ImportService(tasks: provider, notes: DemoVault(), store: store, clock: time.clock)
    coordinator = RefreshCoordinator(service: service, timerInterval: timerInterval)
    let (events, log) = (coordinator.events, log)
    Task { for await event in events { await log.append(event) } }
  }

  func send(_ signals: ChangeSignal...) async {
    for signal in signals { await coordinator.handle(signal) }
  }

  /// Sends what makes the coordinator see `trigger`.
  func signal(_ trigger: ImportTrigger) async {
    switch trigger {
    case .launch: await send(.launch)
    case .manual: await send(.manual)
    case .timer: await send(.timer)
    case .resignActive: await send(.omniFocus(.frontmost), .omniFocus(.background))
    }
  }

  func committed(_ count: Int) async {
    await eventually { await log.count(.committed) == count }
  }

  /// Gives a wrongly started import time to show itself before a negative check.
  func quiesce() async {
    for _ in 0..<500 { await Task.yield() }
  }

  func lastTrigger() async throws -> ImportTrigger? {
    try await store.lastCommittedImport()?.trigger
  }
}

@Suite struct RefreshCoordinatorTests {
  @Test func signalsDuringAnImportStartExactlyOneMoreImport() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.background), .launch)
    await eventually { await rig.provider.calls == 1 }
    await rig.send(.manual, .manual, .manual)
    await rig.signal(.resignActive)
    await rig.quiesce()
    // The coordinator holds the follow-up itself; the service's own queue stays empty.
    #expect(await rig.service.followUpRequests == 0)
    #expect(await rig.provider.calls == 1)
    await rig.provider.open()
    await rig.committed(2)
    await rig.quiesce()
    #expect(await rig.provider.calls == 2)
    #expect(await rig.log.started == [.launch, .resignActive])
  }

  /// A signal while OmniFocus is frontmost is dropped, not held: resign-active brings its own
  /// request, and a quit then reports only the state (owner, 2026-11-05).
  @Test func aSignalWhileOmniFocusIsFrontmostIsDroppedAndResignActiveImportsOnItsOwn()
    async throws
  {
    let rig = Rig()
    await rig.send(.omniFocus(.frontmost), .launch, .timer)
    await rig.quiesce()
    #expect(await rig.provider.calls == 0)
    await rig.send(.omniFocus(.background))
    await rig.committed(1)
    #expect(try await rig.lastTrigger() == .resignActive)
    #expect(await rig.provider.calls == 1)

    let quit = Rig()
    await quit.send(
      .omniFocus(.frontmost), .launch, .omniFocus(.notRunning), .omniFocus(.background))
    await quit.quiesce()
    #expect(await quit.provider.calls == 0)
    #expect(await quit.log.count(.omniFocusNotRunning) == 0)
    #expect(await quit.log.count(.omniFocusState(.notRunning)) == 1)
  }

  @Test func refreshIsAllowedWhileOmniFocusIsFrontmost() async throws {
    let rig = Rig()
    await rig.send(.omniFocus(.frontmost), .manual)
    await rig.committed(1)
    #expect(try await rig.lastTrigger() == .manual)
  }

  @Test func theTimerIsSkippedWithinTheIntervalFromTheLastImportsStart() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.background))
    // The first tick, before any commit, imports; the import commits 11 s after it.
    await rig.send(.timer)
    await eventually { await rig.provider.calls == 1 }
    rig.time.advance(by: .seconds(11))
    await rig.provider.open()
    await rig.committed(1)

    rig.time.advance(by: .seconds(15 * 60 - 12))
    await rig.send(.timer)
    await rig.quiesce()
    #expect(await rig.provider.calls == 1)

    rig.time.advance(by: .seconds(1))
    await rig.send(.timer)
    await rig.committed(2)

    // A failed import is not a start the timer counts from.
    rig.time.advance(by: .seconds(10 * 60))
    await rig.provider.setFailing(true)
    await rig.send(.manual)
    await eventually { await rig.log.count(.notCommitted(.other)) == 1 }
    await rig.provider.setFailing(false)
    rig.time.advance(by: .seconds(5 * 60))
    await rig.send(.timer)
    await rig.committed(3)
    #expect(await rig.log.started == [.timer, .timer, .manual, .timer])
  }

  @Test func theTimerDoesNothingWhileOmniFocusIsFrontmostOrNotRunning() async throws {
    let rig = Rig()
    await rig.send(.omniFocus(.frontmost), .timer, .omniFocus(.notRunning), .timer)
    await rig.quiesce()
    #expect(await rig.provider.calls == 0)
    #expect(await rig.log.count(.omniFocusNotRunning) == 0)
  }

  @Test func nothingImportsWhileOmniFocusIsNotRunningAndTheModelIsTold() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.notRunning), .launch, .manual)
    await eventually { await rig.log.count(.omniFocusNotRunning) == 2 }
    #expect(await rig.provider.calls == 0)

    // A ⌘R left pending when OmniFocus quits is dropped, and said so.
    await rig.send(.omniFocus(.background), .manual)
    await eventually { await rig.provider.calls == 1 }
    await rig.send(.manual, .omniFocus(.notRunning))
    await rig.provider.open()
    await rig.committed(1)
    await eventually { await rig.log.count(.omniFocusNotRunning) == 3 }
    await rig.quiesce()
    #expect(await rig.provider.calls == 1)
    #expect(await rig.log.count(.omniFocusState(.notRunning)) == 2)
    #expect(await rig.log.count(.omniFocusState(.background)) == 1)
  }

  @Test func aPendingImportDoesNotStartOnceOmniFocusIsFrontmostUnlessARefreshJoinedIt()
    async throws
  {
    let dropped = Rig(open: false)
    await dropped.send(.omniFocus(.background), .launch)
    await eventually { await dropped.provider.calls == 1 }
    await dropped.signal(.resignActive)
    await dropped.send(.omniFocus(.frontmost))
    await dropped.provider.open()
    await dropped.committed(1)
    await dropped.quiesce()
    #expect(await dropped.provider.calls == 1)

    let refreshed = Rig(open: false)
    await refreshed.send(.omniFocus(.background), .launch)
    await eventually { await refreshed.provider.calls == 1 }
    await refreshed.signal(.resignActive)
    await refreshed.send(.manual, .omniFocus(.frontmost))
    await refreshed.provider.open()
    await refreshed.committed(2)
    // Resign-active stays recorded, so its median keeps the signal (owner, 2026-11-05).
    #expect(try await refreshed.lastTrigger() == .resignActive)
  }

  /// Owner, 2026-11-05: a pending request that starts only because a joined ⌘R exempts it from
  /// the frontmost drop is recorded as ⌘R, with ⌘R's own wait.
  @Test func aRefreshThatAloneStartsAPendingImportIsRecordedAsARefresh() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.background), .manual)
    await eventually { await rig.provider.calls == 1 }
    await rig.send(.timer)
    rig.time.advance(by: .seconds(5))
    await rig.send(.manual, .omniFocus(.frontmost))
    rig.time.advance(by: .seconds(20))
    await rig.provider.open()
    await rig.committed(2)
    let run = try #require(try await rig.store.lastCommittedImport())
    #expect(run.trigger == .manual)
    #expect(run.waited == .seconds(20))
  }

  @Test func quittingOmniFocusWhileFrontmostStartsNothing() async throws {
    let rig = Rig()
    await rig.send(.omniFocus(.frontmost), .omniFocus(.notRunning))
    await rig.quiesce()
    #expect(await rig.provider.calls == 0)
    #expect(await rig.log.started.isEmpty)
  }

  @Test func aResignActiveRequestOutranksEveryOtherAndOtherwiseTheFirstIsRecorded()
    async throws
  {
    let table: [(first: ImportTrigger, then: ImportTrigger, recorded: ImportTrigger)] = [
      (.launch, .resignActive, .resignActive), (.manual, .resignActive, .resignActive),
      (.timer, .resignActive, .resignActive), (.resignActive, .launch, .resignActive),
      (.resignActive, .manual, .resignActive), (.resignActive, .timer, .resignActive),
      (.manual, .timer, .manual), (.timer, .manual, .timer), (.launch, .manual, .launch),
    ]
    for row in table {
      let rig = Rig(open: false)
      await rig.send(.omniFocus(.background), .launch)
      await eventually { await rig.provider.calls == 1 }
      await rig.signal(row.first)
      await rig.signal(row.then)
      await rig.provider.open()
      await rig.committed(2)
      #expect(try await rig.lastTrigger() == row.recorded, "\(row.first) then \(row.then)")
    }
  }

  @Test func signalsBeforeTheFirstStateWaitForIt() async throws {
    let rig = Rig()
    await rig.send(.launch, .manual)
    await rig.quiesce()
    #expect(await rig.provider.calls == 0)
    await rig.coordinator.run(ListSource(list: [.omniFocus(.background)]))
    await rig.committed(1)
    await rig.quiesce()
    #expect(await rig.provider.calls == 1)
    #expect(try await rig.lastTrigger() == .launch)
  }

  @Test func aSourceThatEndsWithoutAStateDropsItsPendingRequestsAndSaysSo() async throws {
    let rig = Rig()
    await rig.send(.launch)
    await rig.coordinator.run(ListSource(list: []))
    await eventually { await rig.log.count(.omniFocusNotRunning) == 1 }
    #expect(await rig.log.count(.omniFocusState(.notRunning)) == 1)
    await rig.send(.manual)
    await eventually { await rig.log.count(.omniFocusNotRunning) == 2 }
    #expect(await rig.provider.calls == 0)
  }

  @Test func aTimerIntervalUnderFifteenMinutesIsFifteen() async {
    #expect(Rig(timerInterval: .seconds(60)).coordinator.timerInterval == .seconds(15 * 60))
    #expect(Rig(timerInterval: .seconds(30 * 60)).coordinator.timerInterval == .seconds(30 * 60))
  }

  @Test func aTickDuringAnImportStartsNoFollowUp() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.background), .manual)
    await eventually { await rig.provider.calls == 1 }
    rig.time.advance(by: .seconds(5))
    await rig.send(.timer)
    await rig.provider.open()
    await rig.committed(1)
    await rig.quiesce()
    #expect(await rig.provider.calls == 1)
  }

  @Test func theFollowUpRecordsTheWaitFromItsSignal() async throws {
    let rig = Rig(open: false)
    await rig.send(.omniFocus(.background), .launch)
    await eventually { await rig.provider.calls == 1 }
    rig.time.advance(by: .seconds(2))
    await rig.send(.manual)
    rig.time.advance(by: .seconds(9))
    await rig.provider.open()
    await rig.committed(2)
    let run = try #require(try await rig.store.lastCommittedImport())
    #expect(run.trigger == .manual)
    #expect(run.waited == .seconds(9))
  }

  /// S4-4c-1: the kind of a failed import reaches the model; an error with no kind is `other`.
  @Test func aFailedImportReportsItsKind() async throws {
    struct Denied: ImportFailureKind { var importFailure: ImportFailure { .permissionDenied } }
    let rig = Rig()
    await rig.send(.omniFocus(.background))
    let cases: [(any Error, ImportFailure)] = [
      (Denied(), .permissionDenied), (GatedTaskProvider.Unreadable(), .other),
      (PartialSnapshotError(modifiedSince: Rig.start), .partialSnapshot),
    ]
    for (number, (error, kind)) in cases.enumerated() {
      await rig.provider.setFailure(error)
      await rig.send(.manual)
      await eventually { await rig.log.events.filter(\.endsAnImport).count == number + 1 }
      #expect(await rig.log.events.last == .notCommitted(kind))
    }
  }

  @Test func joinedByIsTheRuleImportServiceApplies() {
    func request(_ trigger: ImportTrigger, _ second: Int64) -> ImportRequest {
      ImportRequest(trigger: trigger, signalledAt: .seconds(second))
    }
    let triggers = ImportTrigger.allCases
    for first in triggers {
      for then in triggers {
        let joined = request(first, 1).joined(by: request(then, 2))
        let expected =
          then == .resignActive && first != .resignActive ? request(then, 2) : request(first, 1)
        #expect(joined == expected, "\(first) then \(then)")
      }
    }
  }
}
