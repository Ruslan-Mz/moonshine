import Foundation
import MoonShineCore
import OmniFocusAdapter
import SQLiteStore

/// Measures the live OmniFocus import (phase 1, S3a-1). Prints counts and timings only, never
/// titles or ids. Run from the repository root while OmniFocus is running:
///
///     swift run -c release --package-path Adapters moonshine-import full [runs]
///     swift run -c release --package-path Adapters moonshine-import incremental <minutes>
///     swift run -c release --package-path Adapters moonshine-import probe
///
/// `full` imports into `data/import.local.sqlite` (git-ignored), recreated before the first run;
/// one run unless `runs` is given. The vault is left empty (its reader is S3b), so every task
/// maps to Life ops.
@main
struct MoonShineImport {
  static let storePath = "data/import.local.sqlite"
  /// 300 s for the measurement only (a full read may exceed the adapter's 30 s default).
  static let bridge = OmniFocusBridge(
    script: URL(filePath: "bridge/snapshot.js"), timeout: .seconds(300))
  static let clock = ContinuousClock()
  static let runs = 3

  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    do {
      switch (arguments.first, arguments.dropFirst().first) {
      case ("full", let second):
        guard let count = second == nil ? 1 : second.flatMap({ Int($0) }), count > 0 else {
          usage()
        }
        try await full(runs: count)
      case ("incremental", let minutes?):
        guard let minutes = Int(minutes), minutes > 0 else { usage() }
        try await incremental(minutes: minutes)
      case ("probe", nil): try await probe()
      default: usage()
      }
    } catch {
      print("error: \(describe(error))")
      exit(1)
    }
  }

  static func usage() -> Never {
    print("usage: moonshine-import full [runs] | incremental <minutes> | probe")
    exit(2)
  }

  // MARK: Modes

  static func full(runs: Int) async throws {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: storePath + suffix)
    }
    let store = try SQLiteStore(path: storePath)
    let names = ["bridge", "decode+validate", "import", "commit", "total", "OmniFocus held"]
    var phases: [[Duration]] = []
    var last: SnapshotDocument?
    for run in 1...runs {
      var marks = [clock.now]
      let output = try await bridge.run(.full)
      marks.append(clock.now)
      let document = try SnapshotDocument.decode(output.json)
      let source = try SnapshotMapper.map(document)
      marks.append(clock.now)
      var identities = try await store.identityMap()
      let workspace = Importer().makeWorkspace(
        tasks: source, vault: VaultSnapshot(lines: [], artifacts: [], notes: []),
        identities: &identities.map, now: Date())
      marks.append(clock.now)
      try await store.commit(
        workspace, identities: identities.map, expectedVersion: identities.version, at: Date())
      marks.append(clock.now)
      let steps = zip(marks.dropFirst(), marks).map { $0 - $1 }
      phases.append(steps + [marks[marks.count - 1] - marks[0], output.omniFocusTime ?? .zero])
      print("run \(run)\(run == 1 ? " (empty store)" : ""): " + line(phases[run - 1], names))
      last = document
    }
    if runs > 1 { print("median: " + line(median(phases), names)) }
    if let last { report(last) }
  }

  static func incremental(minutes: Int) async throws {
    let since = Date().addingTimeInterval(-Double(minutes) * 60)
    let names = ["bridge", "decode+validate", "total", "OmniFocus held"]
    var phases: [[Duration]] = []
    var delta: TaskSourceSnapshot?
    for run in 1...runs {
      let start = clock.now
      let output = try await bridge.run(.incremental(since: since))
      let fetched = clock.now
      delta = try SnapshotMapper.map(try SnapshotDocument.decode(output.json))
      phases.append([
        fetched - start, clock.now - fetched, clock.now - start, output.omniFocusTime ?? .zero,
      ])
      print("run \(run): " + line(phases[run - 1], names))
    }
    print("median: " + line(median(phases), names))
    if let delta {
      print(
        "delta since \(minutes) min: projects \(delta.projects.count) · tasks \(byStatus(delta.tasks.map(\.status.rawValue)))"
      )
    }
  }

  static func probe() async throws {
    let names = ["probe", "OmniFocus held"]
    var phases: [[Duration]] = []
    var probe: ChangeProbe?
    for run in 1...runs {
      let start = clock.now
      let output = try await bridge.run(.probe)
      probe = try ChangeProbe.decode(output.json)
      phases.append([clock.now - start, output.omniFocusTime ?? .zero])
      print("run \(run): " + line(phases[run - 1], names))
    }
    print("median: " + line(median(phases), names))
    if let probe {
      let latest = probe.latestModified.flatMap { try? Date.ISO8601FormatStyle().parse($0) }
      let age = latest.map { "\(Int(Date().timeIntervalSince($0) / 60)) min ago" } ?? "n/a"
      print("probe: tasks \(probe.taskCount) · latest change \(age)")
    }
  }

  // MARK: Report (counts only)

  static func report(_ document: SnapshotDocument) {
    print(
      "counts: folders \(document.folders.count) · tags \(document.tags.count) · projects \(document.projects.count) · tasks \(byStatus(document.tasks.map(\.status)))"
    )
    let times = document.defaultTimes
    print(
      "default times: "
        + (times == nil
          ? "not readable" : "due, defer\(times?.planned == nil ? "" : ", planned") set"))
    // Time of day as written in each date's own offset (SnapshotTime), never converted.
    for (name, date, fallback) in [
      ("planned", \SnapshotDocument.Task.plannedDate, times?.planned),
      ("due", \SnapshotDocument.Task.dueDate, times?.due),
    ] {
      let dated = document.tasks.filter { $0[keyPath: date] != nil }
      let clock = dated.compactMap { $0[keyPath: date].flatMap(SnapshotTime.localTimeOfDay) }
      let other = fallback.map { fallback in clock.filter { $0 != fallback }.count }
      print(
        "\(name): \(dated.count) with an own date, "
          + (other.map { "\($0) at a time other than the default" } ?? "no default time setting"))
      let counts = Dictionary(grouping: clock, by: { $0 }).mapValues(\.count)
      let top = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(10)
      print(
        "\(name) times: \(counts.count) distinct · top 10: "
          + top.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
      // Split: remaining vs completed, repeating vs one-off, at the default vs another time.
      for completed in [false, true] {
        let cells = [true, false].map { repeating in
          let tasks = dated.filter {
            ($0.status == "completed") == completed
              && ($0.repetition != nil || $0.repeatOf != nil) == repeating
          }
          let atDefault = tasks.filter {
            fallback != nil && $0[keyPath: date].flatMap(SnapshotTime.localTimeOfDay) == fallback
          }.count
          return "\(repeating ? "repeating" : "one-off") \(tasks.count) "
            + "(default \(atDefault), other \(tasks.count - atDefault))"
        }
        print(
          "  \(name), \(completed ? "completed" : "remaining"): " + cells.joined(separator: " · "))
      }
    }
    let repeatingWithDue = document.tasks.filter {
      $0.status != "completed" && $0.repetition != nil && $0.dueDate != nil
    }.count
    print("remaining repeating tasks with an own due date: \(repeatingWithDue)")
    let inherited = document.tasks.filter { $0.dueDate == nil && $0.effectiveDueDate != nil }.count
    let overridden = document.tasks.filter {
      $0.dueDate != nil && $0.effectiveDueDate.map(instant) != $0.dueDate.map(instant)
    }.count
    print(
      "effective due: \(inherited) inherited · \(overridden) with an own due date that differs from the effective one"
    )
  }

  // MARK: Helpers

  /// Error kind and JSON path only: never a value, a payload slice or osascript's stderr.
  static func describe(_ error: any Error) -> String {
    switch error {
    case BridgeError.notRunning: return "OmniFocus is not running"
    case BridgeError.timedOut(let after): return "bridge timed out after \(after)"
    case BridgeError.malformedOutput: return "bridge output is not JSON"
    case BridgeError.failed(let status, let osaError):
      return "bridge failed: exit \(status)" + (osaError.map { ", OSA error \($0)" } ?? "")
    case SnapshotError.unsupportedSchema(let version): return "unsupported schema \(version)"
    case SnapshotError.invalid(let violations):
      return "\(violations.count) contract violations: "
        + violations.prefix(5).map(\.description).joined(separator: "; ")
    case SnapshotError.badValue(let path): return "bad value at \(path)"
    case SnapshotError.undecodable(let path): return "JSON does not decode at \(path)"
    default: return "\(type(of: error))"
    }
  }

  static func instant(_ string: String) -> Date? { try? Date.ISO8601FormatStyle().parse(string) }

  static func byStatus(_ statuses: [String]) -> String {
    let counts = Dictionary(grouping: statuses, by: { $0 }).mapValues(\.count)
    return "\(statuses.count) ("
      + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
      + ")"
  }

  static func median(_ runs: [[Duration]]) -> [Duration] {
    precondition(!runs.isEmpty, "median of no runs")
    return runs[0].indices.map { index in runs.map { $0[index] }.sorted()[runs.count / 2] }
  }

  static func line(_ durations: [Duration], _ names: [String]) -> String {
    zip(names, durations).map { name, duration in
      let seconds =
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
      return "\(name) \(String(format: "%.2f", seconds)) s"
    }.joined(separator: " · ")
  }
}
