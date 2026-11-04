import Foundation
import MoonShineCore
import Synchronization

public enum BridgeError: Error, Equatable, Sendable {
  /// OmniFocus is not running; the bridge never launches it.
  case notRunning
  case timedOut(after: Duration)
  /// osascript failed. Only the exit status and the OSA error number (e.g. -1743, Automation
  /// permission denied) are kept: its stderr can quote values from OmniFocus.
  case failed(status: Int32, osaError: Int?)
  case malformedOutput
}

/// What a finished script returned.
public struct ScriptResult: Sendable {
  public var status: Int32
  public var stdout: Data
  public var stderr: String

  public init(status: Int32, stdout: Data, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

/// Runs an executable to completion. Throws `BridgeError.timedOut` when it outlives `timeout`.
public protocol ScriptRunner: Sendable {
  func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> ScriptResult
}

// The bridge drives osascript through Process, which exists only on macOS; the iOS builds of
// this package read OmniFocus data from the Mac (ADR-0010).
#if os(macOS)

  /// Reads OmniFocus through `bridge/snapshot.js` (osascript, JXA + Omni Automation). Read-only.
  public struct OmniFocusBridge: Sendable {
    public enum Request: Sendable, Equatable {
      case full
      case incremental(since: Date)
      case probe
    }

    /// The requests that return a snapshot document (the probe has its own call).
    public enum SnapshotRequest: Sendable, Equatable {
      case full
      case incremental(since: Date)
    }

    public struct Output: Sendable {
      /// The snapshot or change-probe JSON. Carries task titles: never log it.
      public let json: Data
      /// How long the export held OmniFocus, as measured inside it.
      public let omniFocusTime: Duration
    }

    /// A decoded result and how long it held OmniFocus. Whether it is also validated depends
    /// on the method that returns it: `probe()` validates, `document(_:)` only decodes.
    public struct Measured<Value: Sendable>: Sendable {
      public let value: Value
      public let omniFocusTime: Duration
    }

    public static let defaultTimeout = Duration.seconds(30)
    static let osascript = URL(filePath: "/usr/bin/osascript")

    public let script: URL
    public let runner: any ScriptRunner
    public let timeout: Duration

    public init(
      script: URL, runner: any ScriptRunner = ProcessScriptRunner(),
      timeout: Duration = OmniFocusBridge.defaultTimeout
    ) {
      self.script = script
      self.runner = runner
      self.timeout = timeout
    }

    public func run(_ request: Request) async throws -> Output {
      var arguments = ["-l", "JavaScript", script.path(percentEncoded: false)]
      switch request {
      case .full: arguments.append("full")
      case .incremental(let since): arguments += ["incremental", since.formatted(.iso8601)]
      case .probe: arguments.append("probe")
      }
      let result = try await runner.run(Self.osascript, arguments: arguments, timeout: timeout)
      guard result.status == 0 else {
        // osascript ends an error line with the OSA number, e.g. "… (-1743)".
        let osaError = result.stderr.firstMatch(of: /\((-?\d+)\)\s*$/).flatMap { Int($0.1) }
        throw BridgeError.failed(status: result.status, osaError: osaError)
      }
      if result.stdout.starts(with: Data(#"{"error":"notRunning"}"#.utf8)) {
        throw BridgeError.notRunning
      }
      guard result.stdout.first == UInt8(ascii: "{") else { throw BridgeError.malformedOutput }
      // The timing marker is part of the contract: without it the held time would be invented.
      guard
        let milliseconds = result.stderr.firstMatch(of: /moonshine-bridge omnifocus_ms=(\d+)\s*$/)
          .flatMap({ Int($0.1) })
      else { throw BridgeError.malformedOutput }
      return Output(json: result.stdout, omniFocusTime: .milliseconds(milliseconds))
    }

    /// A full or incremental snapshot, decoded (validation happens in `SnapshotMapper.map`).
    public func document(_ request: SnapshotRequest) async throws -> Measured<SnapshotDocument> {
      let output: Output
      switch request {
      case .full: output = try await run(.full)
      case .incremental(let since): output = try await run(.incremental(since: since))
      }
      return Measured(
        value: try SnapshotDocument.decode(output.json), omniFocusTime: output.omniFocusTime)
    }

    /// The change probe, decoded and validated.
    public func probe() async throws -> Measured<ChangeProbe> {
      let output = try await run(.probe)
      let probe = try ChangeProbe.decode(output.json)
      let violations = SnapshotValidator.violations(in: probe)
      guard violations.isEmpty else { throw SnapshotError.invalid(violations) }
      return Measured(value: probe, omniFocusTime: output.omniFocusTime)
    }
  }

  extension OmniFocusBridge: TaskProvider {
    public func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      let measured = try await document(modifiedSince.map { .incremental(since: $0) } ?? .full)
      let source = try SnapshotMapper.map(measured.value)
      return TaskSourceSnapshot(
        provider: source.provider, generatedAt: source.generatedAt, timeZone: source.timeZone,
        defaultTimes: source.defaultTimes, modifiedSince: source.modifiedSince, tags: source.tags,
        projects: source.projects, tasks: source.tasks, heldFor: measured.omniFocusTime)
    }
  }

  /// Runs a child process, reading both pipes to the end; terminates it after `timeout`.
  public struct ProcessScriptRunner: ScriptRunner {
    /// How long a child gets after SIGTERM, and after SIGKILL, before the runner stops waiting.
    public let grace: Duration

    public init(grace: Duration = .seconds(2)) {
      self.grace = grace
    }

    public func run(_ executable: URL, arguments: [String], timeout: Duration) async throws
      -> ScriptResult
    {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          continuation.resume(
            with: Result {
              try runBlocking(executable, arguments: arguments, timeout: timeout)
            })
        }
      }
    }

    /// Every wait is bounded. The pipes are read on their own threads and never awaited after a
    /// timeout: a child that ignores SIGTERM, or a grandchild holding the pipes, cannot block us.
    private func runBlocking(_ executable: URL, arguments: [String], timeout: Duration)
      throws -> ScriptResult
    {
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      process.standardInput = FileHandle.nullDevice
      let exited = DispatchSemaphore(value: 0)
      process.terminationHandler = { _ in exited.signal() }
      try process.run()

      let reads = DispatchGroup()
      let collected = Collected()
      DispatchQueue.global().async(group: reads) {
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        collected.stdout.withLock { $0 = data }
      }
      DispatchQueue.global().async(group: reads) {
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        collected.stderr.withLock { $0 = data }
      }

      func deadline(_ duration: Duration) -> DispatchTime {
        .now() + Double(duration.components.seconds) + Double(duration.components.attoseconds)
          / 1e18
      }
      guard exited.wait(timeout: deadline(timeout)) == .success else {
        process.terminate()
        if exited.wait(timeout: deadline(grace)) == .timedOut {
          kill(process.processIdentifier, SIGKILL)
          _ = exited.wait(timeout: deadline(grace))
        }
        throw BridgeError.timedOut(after: timeout)
      }
      // Exited: the pipes reach EOF once every writer has closed them, unless a grandchild
      // still holds them, so this wait is bounded too.
      guard reads.wait(timeout: deadline(grace)) == .success else {
        throw BridgeError.timedOut(after: timeout)
      }
      return ScriptResult(
        status: process.terminationStatus, stdout: collected.stdout.withLock { $0 },
        stderr: String(decoding: collected.stderr.withLock { $0 }, as: UTF8.self))
    }

    /// What the pipe readers collected, shared with their threads.
    private final class Collected: Sendable {
      let stdout = Mutex(Data())
      let stderr = Mutex(Data())
    }
  }

#endif
