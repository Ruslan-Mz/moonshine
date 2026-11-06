import Foundation
import MoonShineCore
import Testing

@testable import OmniFocusAdapter

#if os(macOS)

  let repositoryRoot = fixtureURL.deletingLastPathComponent().deletingLastPathComponent()
  let bridgeScript = repositoryRoot.appending(path: "bridge/snapshot.js")

  /// Answers every run with one canned result and records the arguments.
  final class FakeRunner: ScriptRunner, @unchecked Sendable {
    let result: ScriptResult
    private(set) var arguments: [[String]] = []

    init(status: Int32 = 0, stdout: Data, stderr: String = "moonshine-bridge omnifocus_ms=5\n") {
      result = ScriptResult(status: status, stdout: stdout, stderr: stderr)
    }

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> ScriptResult
    {
      self.arguments.append(arguments)
      return result
    }
  }

  @Suite struct OmniFocusBridgeTests {
    func bridge(_ runner: FakeRunner) -> OmniFocusBridge {
      OmniFocusBridge(script: URL(filePath: "/repo/bridge/snapshot.js"), runner: runner)
    }

    @Test func fullSnapshotMapsAndReportsTheTimeInsideOmniFocus() async throws {
      let runner = FakeRunner(
        stdout: try Data(contentsOf: fixtureURL), stderr: "moonshine-bridge omnifocus_ms=1234\n")
      let output = try await bridge(runner).run(.full)
      #expect(output.omniFocusTime == .milliseconds(1234))
      #expect(runner.arguments == [["-l", "JavaScript", "/repo/bridge/snapshot.js", "full"]])
      let source = try await bridge(runner).snapshot(modifiedSince: nil)
      #expect(source.tasks.count == 350)
      #expect(try await bridge(runner).document(.full).omniFocusTime == .milliseconds(1234))
    }

    @Test func theBridgeReportsTheHeldTimeOfItsMarker() async throws {
      let runner = FakeRunner(
        stdout: try Data(contentsOf: fixtureURL), stderr: "moonshine-bridge omnifocus_ms=2718\n")
      let source = try await bridge(runner).snapshot(modifiedSince: nil)
      #expect(source.heldFor == .milliseconds(2718))
    }

    /// The bridge adds only the held time: every other field is the mapped document's, for a
    /// full and an incremental snapshot.
    @Test func theBridgesSnapshotIsTheMappedDocumentWithItsHeldTime() async throws {
      let full = try String(contentsOf: fixtureURL, encoding: .utf8)
      let incremental = full.replacingOccurrences(
        of: #""mode": "full","#,
        with: #""mode": "incremental", "modifiedSince": "2026-09-30T20:00:00+03:00","#)
      #expect(incremental != full)
      for (json, since) in [
        (full, nil), (incremental, Date(timeIntervalSince1970: 1_790_787_600)),
      ] {
        let mapped = try SnapshotMapper.map(SnapshotDocument.decode(Data(json.utf8)))
        let expected = TaskSourceSnapshot(
          provider: mapped.provider, generatedAt: mapped.generatedAt, timeZone: mapped.timeZone,
          defaultTimes: mapped.defaultTimes, modifiedSince: mapped.modifiedSince,
          tags: mapped.tags, projects: mapped.projects, tasks: mapped.tasks,
          heldFor: .milliseconds(5))
        let source = try await bridge(FakeRunner(stdout: Data(json.utf8)))
          .snapshot(modifiedSince: since)
        #expect(String(reflecting: source) == String(reflecting: expected))
        #expect((source.modifiedSince == nil) == (since == nil))
      }
    }

    @Test func aMissingOrMalformedTimingMarkerIsAMalformedResult() async throws {
      for stderr in ["", "moonshine-bridge omnifocus_ms=abc\n", "omnifocus_ms=12\n"] {
        let runner = FakeRunner(stdout: try Data(contentsOf: fixtureURL), stderr: stderr)
        await #expect(throws: BridgeError.malformedOutput) { try await bridge(runner).run(.full) }
      }
    }

    @Test func probeIsDecodedAndValidated() async throws {
      let valid =
        #"{"schemaVersion":1,"source":"omnifocus","mode":"probe","generatedAt":"2026-09-30T21:00:00+03:00","taskCount":163,"latestModified":null}"#
      let probe = try await bridge(FakeRunner(stdout: Data(valid.utf8))).probe()
      #expect(probe.value.taskCount == 163)
      #expect(probe.omniFocusTime == .milliseconds(5))
      let negative = valid.replacingOccurrences(of: "163", with: "-1")
      await #expect(throws: SnapshotError.invalid([.init("taskCount", "is negative")])) {
        try await bridge(FakeRunner(stdout: Data(negative.utf8))).probe()
      }
    }

    @Test func incrementalRequestPassesTheCutoff() async throws {
      let runner = FakeRunner(stdout: try Data(contentsOf: fixtureURL))
      _ = try await bridge(runner).run(
        .incremental(since: Date(timeIntervalSince1970: 1_790_787_600)))
      #expect(runner.arguments.first?.suffix(2) == ["incremental", "2026-09-30T17:00:00Z"])
    }

    @Test func notRunningIsTyped() async {
      let runner = FakeRunner(stdout: Data(#"{"error":"notRunning"}"#.utf8 + [10]))
      await #expect(throws: BridgeError.notRunning) { try await bridge(runner).run(.probe) }
    }

    @Test func scriptFailureKeepsStatusAndOSAErrorButNeverStderr() async {
      let cases: [(stderr: String, osaError: Int?)] = [
        (
          "snapshot.js: execution error: Not authorized to send Apple events to OmniFocus. (-1743)\n",
          -1743
        ),
        (
          "snapshot.js: execution error: Error: SECRET-TASK-TITLE is not a function (-2700)\n",
          -2700
        ),
        ("SECRET-TASK-TITLE\n", nil),
      ]
      for (stderr, osaError) in cases {
        let runner = FakeRunner(status: 1, stdout: Data(), stderr: stderr)
        let error = await #expect(throws: BridgeError.failed(status: 1, osaError: osaError)) {
          try await bridge(runner).run(.full)
        }
        #expect(!String(describing: error as Any).contains("SECRET"))
      }
    }

    @Test func outputThatIsNotJSONIsMalformed() async {
      let runner = FakeRunner(stdout: Data("oops".utf8))
      await #expect(throws: BridgeError.malformedOutput) { try await bridge(runner).run(.full) }
    }
  }

  @Suite struct ProcessScriptRunnerTests {
    let sh = URL(filePath: "/bin/sh")

    @Test func readsLargeOutputAndStderrToTheEnd() async throws {
      let result = try await ProcessScriptRunner().run(
        sh, arguments: ["-c", "head -c 300000 /dev/zero; echo note >&2; exit 3"],
        timeout: .seconds(10))
      #expect(result.stdout.count == 300_000)
      #expect(result.stderr == "note\n")
      #expect(result.status == 3)
    }

    // No tight wall-clock bound on shared CI runners (owner, 2026-11-06, H1c): the two timeout
    // tests assert how the child ended, bound the call only by 30 s against the child's 60 s
    // sleep, and print the time. The child writes its pid, its sleeping grandchild's pid and the
    // signals it caught to files in a fresh folder: a timed-out call returns no output. The 2 s
    // timeout leaves the shells time to set their traps before SIGTERM (PR #47 round 1).

    /// Long enough for both shells to set their traps on a slow runner.
    static let timeout = Duration.seconds(2)
    /// What a call that waited out the child's or the grandchild's 60 s sleep would exceed.
    static let bound = Duration.seconds(30)

    /// The files a timeout test's child writes, and a cleanup that ends whatever it left running.
    struct ChildTrace {
      let folder = FileManager.default.temporaryDirectory.appending(path: "child-\(UUID())")
      var pid: URL { folder.appending(path: "pid") }
      var grandchild: URL { folder.appending(path: "grandchild") }
      var signals: URL { folder.appending(path: "signals") }
      /// Written by a grandchild whose standard output is the runner's pipe.
      var grandchildOnPipe: URL { folder.appending(path: "grandchild-on-pipe") }

      /// Whether the process of `file` ends within `bound`. `kill(pid, 0)` still succeeds while an
      /// exited child waits to be reaped, so a single look right after the call could fail.
      func ends(_ file: URL, within bound: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + bound
        while isAlive(file) && clock.now < deadline {
          try? await Task.sleep(for: .milliseconds(50))
        }
        return !isAlive(file)
      }

      init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      }

      func read(_ file: URL) -> String? {
        (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(
          in: .whitespacesAndNewlines)
      }

      func isAlive(_ file: URL) -> Bool {
        guard let pid = read(file).flatMap(Int32.init) else { return false }
        return kill(pid, 0) == 0
      }

      /// Kills the child (when a broken runner left it) and the grandchild, then removes the files.
      func cleanUp() {
        for file in [pid, grandchild] {
          if let pid = read(file).flatMap(Int32.init) { kill(pid, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: folder)
      }
    }

    @Test func terminatesAProcessThatOutlivesItsTimeout() async throws {
      let trace = try ChildTrace()
      defer { trace.cleanUp() }
      // SIGTERM ends `wait` and runs the trap, which records it and exits.
      let script = """
        trap 'echo TERM > "\(trace.signals.path())"; exit 143' TERM
        echo $$ > "\(trace.pid.path())"
        sleep 60 > /dev/null 2>&1 &
        echo $! > "\(trace.grandchild.path())"
        wait
        """
      let clock = ContinuousClock()
      let started = clock.now
      await #expect(throws: BridgeError.timedOut(after: Self.timeout)) {
        try await ProcessScriptRunner().run(sh, arguments: ["-c", script], timeout: Self.timeout)
      }
      let elapsed = clock.now - started
      print("terminatesAProcessThatOutlivesItsTimeout: the call returned after \(elapsed)")
      #expect(trace.read(trace.signals) == "TERM", "the child never received SIGTERM")
      #expect(trace.read(trace.pid) != nil, "the child never started")
      #expect(await trace.ends(trace.pid, within: Self.bound), "the child is still running")
      #expect(elapsed < Self.bound, "the call waited out the child's sleep")
    }

    /// A child that catches SIGTERM, records it and keeps waiting on its 60 s sleep: only SIGKILL
    /// can end it before the sleep does. The sleep ignores SIGTERM too, as the runner's terminate
    /// also reaches the child's process group, and it keeps the runner's pipes open: the call must
    /// still return, as the runner never waits for its pipes after a timeout (PR #47 round 1).
    @Test func aChildThatIgnoresTermIsKilledAndTheCallReturns() async throws {
      let trace = try ChildTrace()
      defer { trace.cleanUp() }
      let script = """
        trap 'echo TERM >> "\(trace.signals.path())"' TERM
        echo $$ > "\(trace.pid.path())"
        (trap '' TERM; [ -p /dev/stdout ] && echo pipe > "\(trace.grandchildOnPipe.path())"; exec sleep 60) &
        sleeper=$!
        echo $sleeper > "\(trace.grandchild.path())"
        while kill -0 $sleeper 2> /dev/null; do wait $sleeper; done
        """
      let clock = ContinuousClock()
      let started = clock.now
      await #expect(throws: BridgeError.timedOut(after: Self.timeout)) {
        try await ProcessScriptRunner(grace: .milliseconds(500)).run(
          sh, arguments: ["-c", script], timeout: Self.timeout)
      }
      let elapsed = clock.now - started
      print("aChildThatIgnoresTermIsKilledAndTheCallReturns: the call returned after \(elapsed)")
      #expect(trace.read(trace.signals) == "TERM", "the child never received SIGTERM")
      #expect(trace.read(trace.pid) != nil, "the child never started")
      // The sleep held the runner's pipes when the call returned, and still runs, so only SIGKILL
      // can have ended the child that waited on it.
      #expect(trace.read(trace.grandchildOnPipe) == "pipe", "the sleep did not hold the pipes")
      #expect(trace.isAlive(trace.grandchild), "the child's sleep ended early")
      #expect(await trace.ends(trace.pid, within: Self.bound), "the child survived: no SIGKILL")
      #expect(elapsed < Self.bound, "the call waited for the child's sleep or its pipes")
    }

    @Test func bridgeScriptCompiles() async throws {
      let output = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID()).scpt")
      defer { try? FileManager.default.removeItem(at: output) }
      let result = try await ProcessScriptRunner().run(
        URL(filePath: "/usr/bin/osacompile"),
        arguments: ["-l", "JavaScript", "-o", output.path(), bridgeScript.path()],
        timeout: .seconds(20))
      #expect(result.status == 0, "\(result.stderr)")
    }

    // MARK: S4-4c-1

    @Test func bridgeErrorsMapToFailureKinds() {
      let table: [(BridgeError, ImportFailure)] = [
        (.notRunning, .providerNotRunning), (.timedOut(after: .seconds(30)), .timedOut),
        (.failed(status: 1, osaError: -1743), .permissionDenied),
        (.failed(status: 1, osaError: -600), .providerNotRunning),
        (.failed(status: 1, osaError: -609), .providerNotRunning),
        (.failed(status: 1, osaError: -1728), .other), (.failed(status: 1, osaError: nil), .other),
        (.malformedOutput, .invalidSnapshot),
      ]
      for (error, kind) in table { #expect(error.importFailure == kind, "\(error)") }
    }

    @Test func snapshotErrorsAreInvalidSnapshots() {
      let errors: [SnapshotError] = [
        .unsupportedSchema(9), .invalid([]), .badValue(path: "tasks[0].status"),
        .undecodable(path: "document"),
      ]
      for error in errors { #expect(error.importFailure == .invalidSnapshot, "\(error)") }
    }

    /// The app asks macOS whether this OmniFocus runs; the script must ask about the same one.
    @Test func theBridgeNamesTheOmniFocusOfItsScript() throws {
      let script = try String(contentsOf: bridgeScript, encoding: .utf8)
      #expect(script.contains("Application('\(OmniFocusBridge.bundleIdentifier)')"))
    }
  }

#endif
