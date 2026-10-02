import Foundation
import MoonShineCore
import Synchronization

public enum BridgeError: Error, Equatable, Sendable {
  /// OmniFocus is not running; the bridge never launches it.
  case notRunning
  case timedOut(after: Duration)
  case failed(status: Int32, message: String)
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

/// Reads OmniFocus through `bridge/snapshot.js` (osascript, JXA + Omni Automation). Read-only.
public struct OmniFocusBridge: Sendable {
  public enum Request: Sendable, Equatable {
    case full
    case incremental(since: Date)
    case probe
  }

  public struct Output: Sendable {
    /// The snapshot or change-probe JSON. Carries task titles: never log it.
    public let json: Data
    /// How long the export held OmniFocus, as measured inside it.
    public let omniFocusTime: Duration?
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
      throw BridgeError.failed(
        status: result.status,
        message: String(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)))
    }
    if result.stdout.starts(with: Data(#"{"error":"notRunning"}"#.utf8)) {
      throw BridgeError.notRunning
    }
    guard result.stdout.first == UInt8(ascii: "{") else { throw BridgeError.malformedOutput }
    let milliseconds = result.stderr.firstMatch(of: /moonshine-bridge omnifocus_ms=(\d+)/)
      .flatMap { Int($0.1) }
    return Output(json: result.stdout, omniFocusTime: milliseconds.map { .milliseconds($0) })
  }

  public func document(_ request: Request) async throws -> SnapshotDocument {
    try SnapshotDocument.decode(try await run(request).json)
  }
}

extension OmniFocusBridge: TaskProvider {
  public func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
    try SnapshotMapper.map(
      try await document(modifiedSince.map { .incremental(since: $0) } ?? .full))
  }
}

/// Runs a child process, reading both pipes to the end; terminates it after `timeout`.
public struct ProcessScriptRunner: ScriptRunner {
  public init() {}

  public func run(_ executable: URL, arguments: [String], timeout: Duration) async throws
    -> ScriptResult
  {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(
          with: Result { try Self.runBlocking(executable, arguments: arguments, timeout: timeout) })
      }
    }
  }

  /// Shared with the watchdog. `Process` is not Sendable; it is only asked `isRunning` and
  /// told to `terminate()`, both thread-safe.
  private final class Watch: @unchecked Sendable {
    let process: Process
    let timedOut = Mutex(false)
    let stderr = Mutex(Data())

    init(_ process: Process) { self.process = process }
  }

  private static func runBlocking(_ executable: URL, arguments: [String], timeout: Duration)
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
    let watch = Watch(process)
    try process.run()

    let stderrRead = DispatchGroup()
    DispatchQueue.global().async(group: stderrRead) {
      let data = stderr.fileHandleForReading.readDataToEndOfFile()
      watch.stderr.withLock { $0 = data }
    }
    let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
      guard watch.process.isRunning else { return }
      watch.timedOut.withLock { $0 = true }
      watch.process.terminate()
    }
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    stderrRead.wait()
    if watch.timedOut.withLock({ $0 }) { throw BridgeError.timedOut(after: timeout) }
    return ScriptResult(
      status: process.terminationStatus, stdout: output,
      stderr: String(decoding: watch.stderr.withLock { $0 }, as: UTF8.self))
  }
}
