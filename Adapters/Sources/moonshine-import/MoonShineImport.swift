import Foundation
import MoonShineCore
import ObsidianAdapter
import OmniFocusAdapter
import SQLiteStore

#if os(macOS)

  /// Measures the live OmniFocus import (phase 1, S3a-1) and checks the vault (S3b-2). Prints
  /// counts and timings only, never titles, ids, paths or note names (except `vault --paths`,
  /// below). Run from the repository root (OmniFocus running for the first three):
  ///
  ///     swift run -c release --package-path Adapters moonshine-import full [runs]
  ///     swift run -c release --package-path Adapters moonshine-import incremental <minutes>
  ///     swift run -c release --package-path Adapters moonshine-import probe
  ///     swift run -c release --package-path Adapters moonshine-import vault <folder>
  ///     swift run -c release --package-path Adapters moonshine-import vault --paths <folder>
  ///
  /// `vault` only reads the vault folder and writes nothing: no store, no files. `--paths` also
  /// prints each problem's kind, vault-relative path and line: owner only, in the owner's own
  /// terminal. An agent never runs it, and its output never goes into a log, commit or PR.
  ///
  /// `full` imports into its own store, `moonshine-import.sqlite` in the data folder
  /// (`~/Library/Application Support/MoonShine/`, created if missing); never the app's
  /// `MoonShine.sqlite` next to it. It reads `mapping.yaml` there first (an invalid file stops it),
  /// then OmniFocus, and only after that first read succeeds does it recreate its store, so a
  /// failed read removes nothing; run 1's "import" phase includes that. One run unless `runs` is
  /// given. The vault is not read here (`VaultSnapshot.notRead`), so every task maps to Life ops.
  @main
  struct MoonShineImport {
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
          try await full(runs: count, base: try applicationSupport(), bridge: bridge)
        case ("incremental", let minutes?):
          guard let minutes = Int(minutes), minutes > 0 else { usage() }
          try await incremental(minutes: minutes)
        case ("probe", nil): try await probe()
        case ("vault", "--paths") where arguments.count == 3:
          // Checked before anything is read: paths go only to the owner's own terminal.
          if let refusal = pathsRefusal(output: STDOUT_FILENO) {
            // To standard error: standard output is the pipe or file being refused.
            FileHandle.standardError.write(Data((refusal + "\n").utf8))
            exit(2)
          }
          try vault(at: arguments[2], paths: true)
        case ("vault", let folder?) where arguments.count == 2: try vault(at: folder, paths: false)
        default: usage()
        }
      } catch {
        print("error: \(describe(error))")
        exit(1)
      }
    }

    static func usage() -> Never {
      print(
        """
        usage: moonshine-import full [runs] | incremental <minutes> | probe
                             | vault [--paths] <folder>
          vault <folder>  reads the vault and prints counts only; writes nothing (no store, no files)
          vault --paths <folder>  also prints each problem's kind, vault-relative path and line;
                          for the owner's own terminal only: never run by an agent, never pasted
                          into a log, commit or PR
        """)
      exit(2)
    }

    // MARK: Modes

    /// The data folder's base; only this entry point and the app's name it.
    static func applicationSupport() throws -> URL {
      try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }

    static func full(runs: Int, base: URL, bridge: OmniFocusBridge) async throws {
      // Only `full` creates the folder: `vault` writes nothing.
      let storePath = try Self.storePath(base: base)
      let mapping = try MappingFile.read(folder: DataFolder.url(base: base))
      let groups: Set<String> = if case .groups(let groups) = mapping { groups } else { [] }
      var opened: SQLiteStore?
      var workspace: Workspace?
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
        let store: SQLiteStore
        if let opened {
          store = opened
        } else {
          // Only now that OmniFocus was read: a failed read leaves the old store as it was.
          try removeStore(at: storePath)
          store = try SQLiteStore(path: storePath)
          opened = store
        }
        var identities = try await store.identityMap()
        let imported = Importer(metaTagGroups: groups).makeWorkspace(
          tasks: source, vault: .notRead(), stored: try await store.workspace(),
          identities: &identities.map, now: Date())
        workspace = imported
        marks.append(clock.now)
        // The measurement records its own phases; it adds no row to `imports`.
        try await store.commit(
          imported, identities: identities.map, expectedVersion: identities.version, at: Date(),
          run: nil)
        marks.append(clock.now)
        let steps = zip(marks.dropFirst(), marks).map { $0 - $1 }
        phases.append(steps + [marks[marks.count - 1] - marks[0], output.omniFocusTime])
        print("run \(run)\(run == 1 ? " (empty store)" : ""): " + line(phases[run - 1], names))
        last = document
      }
      if runs > 1 { print("median: " + line(median(phases), names)) }
      if let last { report(last) }
      if let workspace {
        print(
          mappingLine(
            mapping, found: workspace.metaGroupsFound,
            metaTags: workspace.tags.filter(\.isMeta).count))
      }
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
          fetched - start, clock.now - fetched, clock.now - start, output.omniFocusTime,
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
        let measured = try await bridge.probe()
        probe = measured.value
        phases.append([clock.now - start, measured.omniFocusTime])
        print("run \(run): " + line(phases[run - 1], names))
      }
      print("median: " + line(median(phases), names))
      if let probe {
        let latest = probe.latestModified.flatMap { try? Date.ISO8601FormatStyle().parse($0) }
        let age = latest.map { "\(Int(Date().timeIntervalSince($0) / 60)) min ago" } ?? "n/a"
        print("probe: tasks \(probe.taskCount) · latest change \(age)")
      }
    }

    /// Why `vault --paths` refuses to run, or nil when `output` is a terminal. A pipe or a file
    /// (an agent's tool call, a redirect into a log) is refused.
    static func pathsRefusal(output: Int32) -> String? {
      guard isatty(output) == 0 else { return nil }
      return "vault --paths prints note paths and is for the owner's own terminal only; "
        + "it refuses to run when its output is a pipe or a file. Nothing was read."
    }

    /// Reads the vault and prints its counts; with `paths` (owner only) each problem's kind,
    /// path and line too. Writes nothing: no store, no files.
    static func vault(at folder: String, paths: Bool) throws {
      let start = clock.now
      // The local zone: the tool prints counts only, and no count depends on it.
      let read = try ObsidianVault(
        root: URL(filePath: folder, directoryHint: .isDirectory), timeZone: .current
      ).read()
      let elapsed = clock.now - start
      for line in read.report { print(line) }
      print(line([elapsed], ["time"]))
      guard paths else { return }
      print("problems (owner only; do not paste):")
      for location in read.problemLocations { print("  " + location) }
    }

    /// `full`'s store under `base`, the folder created first: the tool's own, never the app's.
    static func storePath(base: URL) throws -> String {
      DataFolder.measurementStorePath(in: try DataFolder.create(base: base))
    }

    /// Removes the tool's own store file and its `-wal` / `-shm`, nothing else. Only a missing
    /// file is fine: a store that cannot be removed would be measured as empty.
    static func removeStore(at storePath: String) throws {
      for suffix in ["", "-wal", "-shm"] {
        do {
          try FileManager.default.removeItem(atPath: storePath + suffix)
        } catch let error as NSError
          where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
        {
          continue
        }
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
        // Counts only: the times themselves are the owner's data.
        let atDefault = fallback.map { fallback in clock.filter { $0 == fallback }.count }
        print(
          "\(name): \(dated.count) with an own date · "
            + (atDefault.map { "\($0) at the default time · \(clock.count - $0) at other times" }
              ?? "no default time setting")
            + " · \(Set(clock).count) distinct times")
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
            "  \(name), \(completed ? "completed" : "remaining"): " + cells.joined(separator: " · ")
          )
        }
      }
      let repeatingWithDue = document.tasks.filter {
        $0.status != "completed" && $0.repetition != nil && $0.dueDate != nil
      }.count
      print("remaining repeating tasks with an own due date: \(repeatingWithDue)")
      let inherited = document.tasks.filter { $0.dueDate == nil && $0.effectiveDueDate != nil }
        .count
      let overridden = document.tasks.filter {
        $0.dueDate != nil && $0.effectiveDueDate.map(instant) != $0.dueDate.map(instant)
      }.count
      print(
        "effective due: \(inherited) inherited · \(overridden) with an own due date that differs from the effective one"
      )
    }

    // MARK: Helpers

    /// Counts only: never a group's name.
    static func mappingLine(_ read: MappingFile.Read, found: Int, metaTags: Int) -> String {
      switch read {
      case .missing: "mapping: missing (no group is meta)"
      case .groups(let groups):
        "mapping: \(found) of \(groups.count) groups found · meta tags \(metaTags)"
      }
    }

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
      case MappingFileError.unreadable:
        return "mapping.yaml is not a regular file or cannot be read"
      case MappingFileError.invalid(let kind, let key):
        return "mapping.yaml: \(kind.rawValue) at \(key.rawValue)"
      case VaultReadError.rootUnreadable: return "the vault folder cannot be read"
      case VaultReadError.tooManyNotes(let limit):
        return "the vault has more than \(limit) notes; nothing was read"
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

#else

  /// The measurement tool drives OmniFocus on the Mac; other platforms only get an entry point.
  @main
  struct MoonShineImport {
    static func main() {
      print("moonshine-import runs on macOS only")
    }
  }

#endif
