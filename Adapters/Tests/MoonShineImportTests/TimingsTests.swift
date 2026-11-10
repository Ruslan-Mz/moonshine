import Foundation
import MoonShineCore
import SQLiteStore
import Testing

@testable import moonshine_import

#if os(macOS)

  /// `moonshine-import timings` (S4-4c-3; ADR-0011): per trigger, signal → landing and the
  /// import's own time, and the 5 s target over resign-active runs from its cutoff. Invented runs.
  @Suite struct TimingsTests {
    static let cutoff = MoonShineImport.targetSince

    static func run(
      _ trigger: ImportTrigger, at offset: TimeInterval = 60, waited: Duration? = .zero,
      duration: Duration?, held: Duration? = nil, failed: ImportFailure? = nil,
      endsBeforeStart: Bool = false
    ) -> ImportRun {
      let start = cutoff.addingTimeInterval(offset)
      return ImportRun(
        trigger: trigger, startedAt: start,
        finishedAt: endsBeforeStart ? start.addingTimeInterval(-1) : start, waited: waited,
        duration: duration, providerHeld: held,
        outcome: failed.map { .failed($0) }
          ?? .committed(
            ImportCounts(lines: 1, notes: 2, artifacts: 3, projects: 4, tasks: 5, tags: 6)))
    }

    @Test func timingsPrintsSignalToLandingPerTriggerCountsMissingTimesAndNoInstants() {
      let runs = [
        Self.run(.launch, waited: .milliseconds(500), duration: .seconds(2), held: .seconds(1)),
        Self.run(.launch, waited: .milliseconds(500), duration: .seconds(4), held: .seconds(3)),
        Self.run(.launch, waited: nil, duration: .seconds(9)),
        Self.run(.launch, duration: .seconds(1), failed: .timedOut),
        Self.run(.launch, duration: .seconds(1), failed: .timedOut),
        Self.run(.launch, duration: nil, failed: .permissionDenied),
      ]
      #expect(
        Timings.lines(runs, targetSince: Self.cutoff) == [
          "launch: runs 6 · committed 3 · not committed 3 (permissionDenied 1, timedOut 2)",
          "  signal → landing median 2.50 s · p90 4.50 s · import median 4.00 s · p90 9.00 s"
            + " · OmniFocus held median 1.00 s · p90 3.00 s · 1 not reported · 1 not measured",
          "resignActive: runs 0",
          "timer: runs 0",
          "manual: runs 0",
          "target (resign-active since 2026-11-08): 0 committed · signal → landing median – · over 5 s: 0 · not measured 0 · not committed 0",
          "ended before they started (clock set back): 0",
        ])
    }

    @Test func theTargetCountsOnlyResignActiveRunsFromItsCutoff() throws {
      let runs = [
        // Before the cutoff: counted per trigger, never for the target.
        Self.run(.resignActive, at: -0.001, duration: .seconds(30)),
        // At the cutoff: counted. A landing of exactly 5 s is not over.
        Self.run(.resignActive, at: 0, waited: .seconds(1), duration: .seconds(4)),
        Self.run(.resignActive, waited: .seconds(1), duration: .seconds(5)),
        Self.run(.resignActive, waited: .zero, duration: .milliseconds(5_010)),
        // Committed without a measured wait: counted as not measured, not in the median.
        Self.run(.resignActive, waited: nil, duration: .seconds(9)),
        Self.run(.resignActive, duration: .seconds(1), failed: .providerNotRunning),
        Self.run(.timer, duration: .seconds(40)),
      ]
      let lines = Timings.lines(runs, targetSince: Self.cutoff)
      #expect(
        lines.first { $0.hasPrefix("resignActive:") }
          == "resignActive: runs 6 · committed 5 · not committed 1 (providerNotRunning 1)")
      #expect(
        lines.dropLast().last
          == "target (resign-active since 2026-11-08): 4 committed · signal → landing median 5.01 s · over 5 s: 2 · not measured 1 · not committed 1"
      )
    }

    /// The wall clock stepped back during an import: the store reads such a row as not
    /// measured, and the report counts it instead of failing (owner, 2026-11-10).
    @Test func runsThatEndedBeforeTheyStartedAreCounted() {
      let runs = [
        Self.run(.timer, waited: nil, duration: nil, endsBeforeStart: true),
        Self.run(.timer, duration: .seconds(1)),
      ]
      let lines = Timings.lines(runs, targetSince: Self.cutoff)
      #expect(lines.last == "ended before they started (clock set back): 1")
      #expect(
        lines.contains { $0.hasPrefix("  signal → landing") && $0.hasSuffix("1 not measured") })
    }

    @Test func describeNamesOnlyTheStoreColumnOrTable() {
      #expect(
        MoonShineImport.describe(SQLiteStoreError.missingTable("imports"))
          == "the app store has no imports table")
      #expect(
        MoonShineImport.describe(SQLiteStoreError.unknownValue(column: "imports.outcome"))
          == "the app store holds an unknown value in imports.outcome")
      #expect(
        MoonShineImport.describe(SQLiteStoreError.outOfRange(column: "imports.attrs"))
          == "the app store holds a value out of range in imports.attrs")
      #expect(
        MoonShineImport.describe(SQLiteStoreError.cannotOpenReadOnly)
          == "the app store cannot be opened read-only; open MoonShine once, then quit it")
    }

    func temporaryBase() -> URL {
      FileManager.default.temporaryDirectory
        .appending(path: "moonshine-timings-\(UUID().uuidString)")
    }

    /// Writes one committed and one failed run into a store at `path`, then closes it.
    func writeStore(at path: String) async throws {
      let store = try SQLiteStore(path: path)
      let start = Self.cutoff.addingTimeInterval(60)
      // Signalled at 0, started at 1 s, ended at 3 s.
      let clock = ImportClock(wall: { start }, monotonic: { .seconds(3) })
      try await store.commit(
        Workspace(timeZone: .gmt), identities: IdentityMap(), expectedVersion: 0, at: start,
        run: PendingImportRun(
          request: ImportRequest(trigger: .resignActive, signalledAt: .zero), startedAt: start,
          started: .seconds(1), clock: clock))
      try await store.recordFailure(
        PendingImportRun(
          request: ImportRequest(trigger: .timer), startedAt: start, started: .seconds(1),
          clock: clock), .timedOut)
      try store.close()
    }

    @Test func timingsReadsTheAppStoreNotTheMeasurementStore() async throws {
      let base = temporaryBase()
      defer { try? FileManager.default.removeItem(at: base) }
      let folder = try DataFolder.create(base: base)
      try await writeStore(at: DataFolder.measurementStorePath(in: folder))
      #expect(throws: MoonShineImport.NoAppStore.self) {
        try MoonShineImport.timingsLines(base: base)
      }
      try await writeStore(at: DataFolder.appStorePath(in: folder))
      let lines = try MoonShineImport.timingsLines(base: base)
      #expect(lines.contains("resignActive: runs 1 · committed 1 · not committed 0"))
      #expect(
        lines.contains(
          "target (resign-active since 2026-11-08): 1 committed · signal → landing median 3.00 s · over 5 s: 0 · not measured 0 · not committed 0"
        ))
      #expect(lines.contains("timer: runs 1 · committed 0 · not committed 1 (timedOut 1)"))
    }

    @Test func timingsNamesAMissingAppStoreAndCreatesNoFolder() throws {
      let base = temporaryBase()
      let error = #expect(throws: (any Error).self) {
        try MoonShineImport.timings(base: base)
      }
      #expect(error.map(MoonShineImport.describe) == "no app store in the data folder")
      #expect(!FileManager.default.fileExists(atPath: base.path(percentEncoded: false)))
    }
  }

#endif
