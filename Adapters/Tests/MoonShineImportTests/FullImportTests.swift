import Foundation
import MoonShineCore
import ObsidianAdapter
import OmniFocusAdapter
import SQLiteStore
import Testing

@testable import moonshine_import

#if os(macOS)

  /// `fixtures/omnifocus.snapshot.json` at the repository root (synthetic data).
  let fixtureSnapshot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appending(path: "fixtures/omnifocus.snapshot.json")

  /// Answers every run with one canned result and counts the runs.
  final class CannedRunner: ScriptRunner, @unchecked Sendable {
    let result: ScriptResult
    private(set) var runs = 0

    init(status: Int32 = 0, stdout: Data = Data()) {
      result = ScriptResult(
        status: status, stdout: stdout, stderr: "moonshine-bridge omnifocus_ms=5\n")
    }

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> ScriptResult
    {
      runs += 1
      return result
    }
  }

  /// S4-4c-2: `full` reads the mapping file, then OmniFocus, and only then replaces its own
  /// store; a failed read removes and opens nothing. Every file here is invented.
  @Suite struct FullImportTests {
    let base: URL
    var folder: URL { DataFolder.url(base: base) }
    var tool: String { DataFolder.measurementStorePath(in: folder) }
    var app: String { DataFolder.appStorePath(in: folder) }

    init() throws {
      base = FileManager.default.temporaryDirectory
        .appending(path: "base-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
    }

    func bridge(_ runner: CannedRunner) -> OmniFocusBridge {
      OmniFocusBridge(script: URL(filePath: "bridge/snapshot.js"), runner: runner)
    }

    func succeeding() throws -> CannedRunner {
      CannedRunner(stdout: try Data(contentsOf: fixtureSnapshot))
    }

    /// The tool's old store and the app's store, each with its own invented bytes.
    func plantStores() throws {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for path in [tool, tool + "-wal", app] {
        #expect(FileManager.default.createFile(atPath: path, contents: Data(path.utf8)))
      }
    }

    func unchanged(_ paths: [String]) throws {
      for path in paths {
        #expect(try Data(contentsOf: URL(filePath: path)) == Data(path.utf8), "\(path)")
      }
    }

    func writeMapping(_ text: String) throws {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(text.utf8).write(to: DataFolder.mappingFile(in: folder))
    }

    func storedTags() async throws -> [MoonShineCore.Tag] {
      let store = try SQLiteStore(path: tool)
      defer { try? store.close() }
      return try await store.workspace().tags
    }

    @Test func aFailedReadRemovesNothing() async throws {
      try plantStores()
      let runner = CannedRunner(status: 1)
      await #expect(throws: BridgeError.self) {
        try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(runner))
      }
      #expect(runner.runs == 1)
      try unchanged([tool, tool + "-wal", app])
    }

    /// The bridge ran, but its output does not decode: the old store stays (PR #50 round 1).
    @Test func anOutputThatDoesNotDecodeRemovesNothing() async throws {
      try plantStores()
      let runner = CannedRunner(stdout: Data("{}".utf8))
      await #expect(throws: SnapshotError.self) {
        try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(runner))
      }
      #expect(runner.runs == 1)
      try unchanged([tool, tool + "-wal", app])
    }

    /// A valid snapshot of changes only is not the full read that may replace the store.
    @Test func aSnapshotOfChangesOnlyRemovesNothing() async throws {
      try plantStores()
      let full = String(decoding: try Data(contentsOf: fixtureSnapshot), as: UTF8.self)
      let delta = full.replacingOccurrences(
        of: "\"mode\": \"full\",",
        with: "\"mode\": \"incremental\",\n \"modifiedSince\": \"2026-10-01T15:00:00+03:00\",")
      #expect(delta != full)
      let runner = CannedRunner(stdout: Data(delta.utf8))
      await #expect(throws: PartialSnapshotError.self) {
        try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(runner))
      }
      try unchanged([tool, tool + "-wal", app])
    }

    /// Later runs import into the store run 1 opened: each commit raises its version by one.
    @Test func laterRunsReuseTheStore() async throws {
      try await MoonShineImport.full(runs: 2, base: base, bridge: bridge(try succeeding()))
      let store = try SQLiteStore(path: tool)
      defer { try? store.close() }
      #expect(try await store.identityMap().version == 2)
    }

    @Test func aSuccessfulReadReplacesOnlyTheMeasurementStore() async throws {
      try plantStores()
      try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(try succeeding()))
      try unchanged([app])
      #expect(try await storedTags().count == 14)
    }

    @Test func anInvalidMappingFileStopsBeforeTheBridge() async throws {
      try plantStores()
      try writeMapping("Effort:\n  - Low\n")
      let runner = try succeeding()
      await #expect(throws: MappingFileError.invalid(.invalidValue, key: .root)) {
        try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(runner))
      }
      #expect(runner.runs == 0)
      try unchanged([tool, tool + "-wal", app])
    }

    @Test func fullCreatesTheFolderBeforeOpeningTheStore() async throws {
      #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
      try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(try succeeding()))
      #expect(FileManager.default.fileExists(atPath: tool))
    }

    @Test func theMappedGroupsReachTheImport() async throws {
      try writeMapping("meta_tag_groups: [Effort]\n")
      try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(try succeeding()))
      #expect(Set(try await storedTags().filter(\.isMeta).map(\.name)) == ["Effort", "Low"])
    }

    @Test func withoutAMappingFileNoTagIsMeta() async throws {
      try await MoonShineImport.full(runs: 1, base: base, bridge: bridge(try succeeding()))
      #expect(try await storedTags().filter(\.isMeta).isEmpty)
    }

    @Test func theMappingErrorNamesItsKindAndKeyOnly() {
      #expect(
        MoonShineImport.describe(MappingFileError.invalid(.invalidValue, key: .metaTagGroups))
          == "mapping.yaml: invalidValue at meta_tag_groups")
      #expect(
        MoonShineImport.describe(MappingFileError.unreadable)
          == "mapping.yaml is not a regular file or cannot be read")
    }

    @Test func theMappingLineCountsGroupsFoundAndMetaTags() {
      #expect(
        MoonShineImport.mappingLine(.missing, found: 0, metaTags: 0)
          == "mapping: missing (no group is meta)")
      #expect(
        MoonShineImport.mappingLine(.groups(["Effort", "Other"]), found: 1, metaTags: 2)
          == "mapping: 1 of 2 groups found · meta tags 2")
    }
  }

#endif
