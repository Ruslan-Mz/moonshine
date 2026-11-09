import Foundation

/// The clocks an import reads: the wall clock for stored instants, a monotonic one for the
/// durations. It is the only clock of the import path, so a signal's time and an import's start
/// are never read from two origins (ADR-0011).
public struct ImportClock: Sendable {
  public let wall: @Sendable () -> Date
  /// Time since one origin; only differences between two readings mean anything.
  public let monotonic: @Sendable () -> Duration

  public init(wall: @escaping @Sendable () -> Date, monotonic: @escaping @Sendable () -> Duration) {
    self.wall = wall
    self.monotonic = monotonic
  }

  /// One origin for the whole process, so readings from any caller can be subtracted.
  private static let origin = ContinuousClock.now

  public static let system = ImportClock(
    wall: { Date() }, monotonic: { ContinuousClock.now - origin })

  /// Demo mode: the wall clock stands still at `date`; durations are still measured.
  public static func frozen(at date: Date) -> ImportClock {
    ImportClock(wall: { date }, monotonic: system.monotonic)
  }
}

/// What asked for an import (ADR-0011's four signals). Stored by raw value.
public enum ImportTrigger: String, Sendable, CaseIterable {
  case launch
  case resignActive
  case timer
  case manual
}

public struct ImportRequest: Sendable, Equatable {
  public let trigger: ImportTrigger
  /// The monotonic time of the signal; nil when the request is its own signal, and
  /// `ImportService` then reads it when the request arrives.
  public let signalledAt: Duration?

  public init(trigger: ImportTrigger, signalledAt: Duration? = nil) {
    self.trigger = trigger
    self.signalledAt = signalledAt
  }

  /// The request recorded when `later` joins this one: the first, unless `later` is the first
  /// resign-active one, so the target's median keeps every resign-active signal (ADR-0011,
  /// 2026-11-04 and 2026-11-05).
  public func joined(by later: ImportRequest) -> ImportRequest {
    later.trigger == .resignActive && trigger != .resignActive ? later : self
  }
}

/// The rows an import brought, per entity kind (the spec's "row counts").
public struct ImportCounts: Sendable, Equatable {
  public let lines: Int
  public let notes: Int
  public let artifacts: Int
  public let projects: Int
  public let tasks: Int
  public let tags: Int

  public init(lines: Int, notes: Int, artifacts: Int, projects: Int, tasks: Int, tags: Int) {
    self.lines = lines
    self.notes = notes
    self.artifacts = artifacts
    self.projects = projects
    self.tasks = tasks
    self.tags = tags
  }

  public init(_ workspace: Workspace) {
    self.init(
      lines: workspace.lines.count, notes: workspace.notes.count,
      artifacts: workspace.artifacts.count, projects: workspace.projects.count,
      tasks: workspace.tasks.count, tags: workspace.tags.count)
  }
}

/// Why an import did not commit, by kind only: never a value, an id or a provider's text.
/// Held in memory in S4-4c-1; S4-4c-3 records it. One writer per store, so an identity
/// conflict cannot happen and is `other`.
public enum ImportFailure: String, Sendable, CaseIterable {
  case providerNotRunning
  case permissionDenied
  case timedOut
  case invalidSnapshot
  case partialSnapshot
  /// The mapping file in the data folder cannot be read; imports wait for a valid one.
  case mappingInvalid
  case other
}

/// An error that names its kind; any other error is `other`.
public protocol ImportFailureKind: Error {
  var importFailure: ImportFailure { get }
}

extension PartialSnapshotError: ImportFailureKind {
  public var importFailure: ImportFailure { .partialSnapshot }
}

/// How an import ended. Only committed runs are recorded until failures are (S4-4c).
public enum ImportOutcome: Sendable, Equatable {
  case committed(ImportCounts)
}

/// One recorded import. A duration is nil when it could not be measured, never 0.
public struct ImportRun: Sendable, Equatable {
  public let trigger: ImportTrigger
  public let startedAt: Date
  public let finishedAt: Date
  /// From the signal to the start.
  public let waited: Duration?
  /// From the start to the store's write.
  public let duration: Duration?
  /// How long the task provider held its source (OmniFocus), as it reported.
  public let providerHeld: Duration?
  public let outcome: ImportOutcome

  /// A negative duration is not measurable and becomes nil, so the store never writes what
  /// its reader rejects.
  public init(
    trigger: ImportTrigger, startedAt: Date, finishedAt: Date, waited: Duration?,
    duration: Duration?, providerHeld: Duration?, outcome: ImportOutcome
  ) {
    func measurable(_ value: Duration?) -> Duration? { value.flatMap { $0 < .zero ? nil : $0 } }
    self.trigger = trigger
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.waited = measurable(waited)
    self.duration = measurable(duration)
    self.providerHeld = measurable(providerHeld)
    self.outcome = outcome
  }
}

/// An import that has read its sources and is about to be committed. The store finishes it
/// inside its write, so `duration` covers the decode, the merge and every row written; only
/// the run's own row and the transaction's commit fall outside.
public struct PendingImportRun: Sendable {
  public let trigger: ImportTrigger
  public let startedAt: Date
  /// The monotonic reading at the start.
  public let started: Duration
  /// From the signal to the start; zero without a signal time, nil when the signal reads
  /// after the start.
  public let waited: Duration?
  public let providerHeld: Duration?
  public let counts: ImportCounts
  public let clock: ImportClock

  public init(
    request: ImportRequest, startedAt: Date, started: Duration, providerHeld: Duration?,
    counts: ImportCounts, clock: ImportClock
  ) {
    trigger = request.trigger
    self.startedAt = startedAt
    self.started = started
    if let signalledAt = request.signalledAt {
      waited = started - signalledAt < .zero ? nil : started - signalledAt
    } else {
      waited = .zero
    }
    self.providerHeld = providerHeld
    self.counts = counts
    self.clock = clock
  }

  public func finished() -> ImportRun {
    let duration = clock.monotonic() - started
    return ImportRun(
      trigger: trigger, startedAt: startedAt, finishedAt: clock.wall(), waited: waited,
      duration: duration, providerHeld: providerHeld, outcome: .committed(counts))
  }
}
