import Foundation
import MoonShineCore

/// Serves one task; while closed, every snapshot waits until the test opens the gate. A
/// snapshot asked for while `fails` is set throws instead.
actor GatedTaskProvider: TaskProvider {
  struct Unreadable: Error {}

  private(set) var calls = 0
  private var isOpen = false
  private var failure: (any Error)?
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(open: Bool = false) {
    isOpen = open
  }

  func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
    calls += 1
    let failing = failure
    if !isOpen { await withCheckedContinuation { waiting.append($0) } }
    if let failing { throw failing }
    return TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 0),
      timeZone: TestWorld.timeZone, defaultTimes: DefaultTimeSettings(), tags: [], projects: [],
      tasks: [SourceTask(externalId: "x", name: "Scales")])
  }

  func open() {
    isOpen = true
    for continuation in waiting { continuation.resume() }
    waiting = []
  }

  func close() {
    isOpen = false
  }

  func setFailing(_ value: Bool) {
    failure = value ? Unreadable() : nil
  }

  func setFailure(_ error: any Error) {
    failure = error
  }
}

/// Yields until `condition` holds, bounded so a broken implementation fails instead of hanging.
func eventually(_ condition: () async -> Bool) async {
  for _ in 0..<10_000 where !(await condition()) { await Task.yield() }
}
