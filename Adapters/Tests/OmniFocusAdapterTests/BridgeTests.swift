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

    @Test func terminatesAProcessThatOutlivesItsTimeout() async {
      let clock = ContinuousClock()
      let started = clock.now
      await #expect(throws: BridgeError.timedOut(after: .milliseconds(200))) {
        try await ProcessScriptRunner().run(
          sh, arguments: ["-c", "sleep 5"], timeout: .milliseconds(200))
      }
      // Below the child's 5 s sleep, which a call that did not terminate it would wait out; not
      // tighter, since shared CI runners took 3.6 s (PUB-3).
      #expect(clock.now - started < .seconds(4))
    }

    /// A child that ignores SIGTERM, with a grandchild holding the pipes open: the call still
    /// returns the typed timeout well before the child's 10 s sleep, which a call that did not
    /// kill it would wait out. Not timeout + grace + grace + 1 s: shared CI runners took 4.4 s
    /// (PUB-3).
    @Test func aChildThatIgnoresTermIsKilledAndTheCallReturns() async throws {
      // The child writes its pid to a file: a timed-out call returns no output.
      let pidFile = FileManager.default.temporaryDirectory.appending(path: "child-\(UUID()).pid")
      defer { try? FileManager.default.removeItem(at: pidFile) }
      let clock = ContinuousClock()
      let started = clock.now
      await #expect(throws: BridgeError.timedOut(after: .milliseconds(200))) {
        try await ProcessScriptRunner(grace: .milliseconds(500)).run(
          sh, arguments: ["-c", "trap '' TERM; echo $$ > '\(pidFile.path())'; sleep 10"],
          timeout: .milliseconds(200))
      }
      #expect(clock.now - started < .seconds(6))
      // The child ignored SIGTERM, so only SIGKILL can have ended it (and Process reaped it).
      let pid = try #require(
        Int32(
          try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
            in: .whitespacesAndNewlines)))
      #expect(kill(pid, 0) == -1 && errno == ESRCH, "child \(pid) is still alive")
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
  }

#endif
