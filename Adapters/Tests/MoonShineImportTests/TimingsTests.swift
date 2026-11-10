import Foundation
import MoonShineCore
import SQLiteStore
import Testing

@testable import moonshine_import

#if os(macOS)

  /// `moonshine-import timings` (S4-4c-3; ADR-0011): per trigger, signal → landing and the
  /// import's own time, and the 5 s target over resign-active runs from its cutoff. Invented runs.
  @Suite struct TimingsTests {
    static let cutoff = Date(timeIntervalSince1970: 1_794_138_074)

    static func run(
      _ trigger: ImportTrigger, at offset: TimeInterval = 60, waited: Duration? = .zero,
      duration: Duration?, held: Duration? = nil, failed: ImportFailure? = nil
    ) -> ImportRun {
      let start = cutoff.addingTimeInterval(offset)
      return ImportRun(
        trigger: trigger, startedAt: start, finishedAt: start, waited: waited,
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
          "target (resign-active since 2026-11-08): 0 committed · signal → landing median – · over 5 s: 0 · not committed 0",
        ])
    }

    @Test func theTargetCountsOnlyResignActiveRunsFromItsCutoff() throws {
      let runs = [
        // Before the cutoff: counted per trigger, never for the target.
        Self.run(.resignActive, at: -60, duration: .seconds(30)),
        Self.run(.resignActive, waited: .seconds(1), duration: .seconds(2)),
        Self.run(.resignActive, waited: .seconds(1), duration: .seconds(5)),
        Self.run(.resignActive, waited: .zero, duration: .milliseconds(5_010)),
        Self.run(.resignActive, duration: .seconds(1), failed: .providerNotRunning),
        Self.run(.timer, duration: .seconds(40)),
      ]
      let lines = Timings.lines(runs, targetSince: Self.cutoff)
      #expect(
        lines.first { $0.hasPrefix("resignActive:") }
          == "resignActive: runs 5 · committed 4 · not committed 1 (providerNotRunning 1)")
      #expect(
        lines.last
          == "target (resign-active since 2026-11-08): 3 committed · signal → landing median 5.01 s · over 5 s: 2 · not committed 1"
      )
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

    @Test func timingsNamesAMissingAppStoreAndCreatesNoFolder() throws {
      let base = FileManager.default.temporaryDirectory
        .appending(path: "moonshine-timings-\(UUID().uuidString)")
      let error = #expect(throws: (any Error).self) {
        try MoonShineImport.timings(base: base)
      }
      #expect(error.map(MoonShineImport.describe) == "no app store in the data folder")
      #expect(!FileManager.default.fileExists(atPath: base.path(percentEncoded: false)))
    }
  }

#endif
