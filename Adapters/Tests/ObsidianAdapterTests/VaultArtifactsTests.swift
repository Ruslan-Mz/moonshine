import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import ObsidianAdapter

@Suite struct VaultArtifactsTests {
  /// A vault of these notes (path → frontmatter), read.
  func read(_ notes: [String: String]) throws -> VaultRead {
    let vault = try TemporaryVault()
    for (path, yaml) in notes { try vault.write(path, note(yaml)) }
    return try ObsidianVault(root: vault.root, timeZone: moscow).read()
  }

  /// A year note with these `artifacts:` items (YAML lines, indented by two).
  func year(_ year: Int = 2026, _ items: String...) -> String {
    "type: year_artifacts\nyear: \(year)\nartifacts:\n" + items.joined(separator: "\n")
  }

  func quarter(_ period: String, _ items: String...) -> String {
    "type: quarter_focus\nperiod: \(period)\nartifacts:\n" + items.joined(separator: "\n")
  }

  /// The problems of `artifacts:` and of several notes for one period.
  func artifactProblems(_ read: VaultRead) -> [String] {
    problems(
      read.issues.filter {
        guard case .vault(_, _, let problem) = $0 else { return false }
        return problem.key?.hasPrefix("artifacts.") == true || problem.key == "notes.artifacts"
          || problem.kind == .duplicatePeriodNote || problem.kind == .duplicateArtifactId
      })
  }

  func artifact(
    _ key: String, _ title: String, period periodKey: String = "2026", lines: [LineKey] = [],
    status: ArtifactStatus = .planned, priority: Bool = false, in path: String = "y.md"
  ) -> SourceArtifact {
    SourceArtifact(
      key: key, periodKey: periodKey, title: title, lineKeys: lines, status: status,
      priority: priority, notePath: path)
  }

  @Test func theFixtureArtifactsEqualTheDemoVaultArtifacts() throws {
    let read = try ObsidianVault(root: fixtureVault, timeZone: moscow).read()
    #expect(read.artifacts == DemoVault.snapshot.artifacts)
    #expect(read.unread == .nothing)
    #expect(read.issues.isEmpty)
  }

  // MARK: Items

  @Test func everyKeyIsCarriedToTheArtifact() throws {
    let read = try read([
      "y.md": year(
        2026,
        "  - id: a-1", "    title: Paper", "    lines: [research, violin]",
        "    status: in_progress", "    priority: true", "    carried_to: 2027",
        "    done: 2026-10-12",
        "  - id: a-2", "    title: Recital", "    line: violin", "    status: done",
        "    priority: false",
        "  - {id: a-3, title: Plain, status: null}"),
      "q.md": quarter("2026-Q4", "  - {id: q-1, title: Etudes, status: dropped}"),
    ])
    #expect(
      read.artifacts == [
        artifact("q-1", "Etudes", period: "2026-Q4", status: .dropped, in: "q.md"),
        artifact(
          "a-1", "Paper", lines: ["research", "violin"], status: .inProgress, priority: true),
        artifact("a-2", "Recital", lines: ["violin"], status: .done),
        artifact("a-3", "Plain"),
      ])
    #expect(artifactProblems(read).isEmpty)
    #expect(read.unread == .nothing)
  }

  @Test func eachRefusedValueSkipsItsItemAndLeavesTheListUnread() throws {
    let control = "\"Bad\\x01title\""
    let wide = String(repeating: "e\u{301}\u{301}\u{301}\u{301}\u{301}", count: 100)
    let cases: [(item: String, problem: String)] = [
      ("{title: T}", "missingKey (artifacts.id)"),
      ("{id: null, title: T}", "missingKey (artifacts.id)"),
      ("{id: A-1, title: T}", "invalidValue (artifacts.id)"),
      ("{id: \(String(repeating: "a", count: 65)), title: T}", "invalidValue (artifacts.id)"),
      ("{id: [x], title: T}", "invalidValue (artifacts.id)"),
      ("{id: x}", "missingKey (artifacts.title)"),
      ("{id: x, title: \(String(repeating: "t", count: 201))}", "invalidValue (artifacts.title)"),
      ("{id: x, title: \(wide)}", "invalidValue (artifacts.title)"),
      ("{id: x, title: \(control)}", "invalidValue (artifacts.title)"),
      ("{id: x, title: T, line: Violin}", "invalidValue (artifacts.line)"),
      ("{id: x, title: T, line: violin, lines: [piano]}", "invalidValue (artifacts.lines)"),
      ("{id: x, title: T, line: violin, lines: []}", "invalidValue (artifacts.lines)"),
      ("{id: x, title: T, lines: violin}", "invalidValue (artifacts.lines)"),
      ("{id: x, title: T, lines: [violin, Piano]}", "invalidValue (artifacts.lines)"),
      ("{id: x, title: T, lines: [violin, violin]}", "invalidValue (artifacts.lines)"),
      (
        "{id: x, title: T, lines: [\((0...20).map { "l\($0)" }.joined(separator: ", "))]}",
        "invalidValue (artifacts.lines)"
      ),
      ("{id: x, title: T, status: started}", "invalidValue (artifacts.status)"),
      ("{id: x, title: T, priority: yes}", "invalidValue (artifacts.priority)"),
      ("plain text", "invalidValue (notes.artifacts)"),
    ]
    for (item, problem) in cases {
      let read = try read(["y.md": year(2026, "  - {id: kept, title: Kept}", "  - \(item)")])
      #expect(read.artifacts == [artifact("kept", "Kept")], "\(item)")
      #expect(artifactProblems(read) == ["y.md:6:\(problem)"], "\(item)")
      #expect(
        read.unread == VaultUnread(paths: [], artifactLists: ["y.md"], notRecognised: []),
        "\(item)")
      #expect(read.notes.map(\.path) == ["y.md"], "\(item)")
    }
  }

  @Test func everyCapIsAcceptedAtItsLimit() throws {
    let id = String(repeating: "a", count: 64)
    let title = String(repeating: "t", count: 200)
    let lines = (1...20).map { "l\($0)" }
    let read = try read([
      "y.md": year(
        2026, "  - {id: \(id), title: \(title), lines: [\(lines.joined(separator: ", "))]}")
    ])
    #expect(read.artifacts == [artifact(id, title, lines: lines.map { LineKey($0) })])
    #expect(read.unread == .nothing)
  }

  @Test func aListOfAHundredItemsIsReadAndOneMoreIsNot() throws {
    let items = (1...101).map { "  - {id: a-\($0), title: T\($0)}" }
    let full = try read([
      "y.md": "type: year_artifacts\nyear: 2026\nartifacts:\n"
        + items.dropLast().joined(separator: "\n")
    ])
    #expect(full.artifacts.count == 100)
    #expect(full.unread == .nothing)
    let over = try read([
      "y.md": "type: year_artifacts\nyear: 2026\nartifacts:\n" + items.joined(separator: "\n")
    ])
    #expect(over.artifacts.isEmpty)
    #expect(artifactProblems(over) == ["y.md:5:invalidValue (notes.artifacts)"])
    #expect(over.unread == VaultUnread(paths: [], artifactLists: ["y.md"], notRecognised: []))
    #expect(over.notes.map(\.path) == ["y.md"])
  }

  // MARK: The list

  @Test func anAbsentNullOrEmptyListIsACleanReadWithNoArtifacts() throws {
    for list in ["", "artifacts:", "artifacts: null", "artifacts: []"] {
      let read = try read(["y.md": "type: year_artifacts\nyear: 2026\n" + list])
      #expect(read.artifacts.isEmpty, "\(list)")
      #expect(artifactProblems(read).isEmpty, "\(list)")
      #expect(read.unread == .nothing, "\(list)")
    }
  }

  @Test func aListThatIsNotAListIsInvalidAndLeavesTheListUnread() throws {
    for list in ["artifacts: a26-01", "artifacts: {id: a, title: T}"] {
      let read = try read(["y.md": "type: year_artifacts\nyear: 2026\n" + list])
      #expect(read.artifacts.isEmpty, "\(list)")
      #expect(artifactProblems(read) == ["y.md:4:invalidValue (notes.artifacts)"], "\(list)")
      #expect(read.unread == VaultUnread(paths: [], artifactLists: ["y.md"], notRecognised: []))
    }
  }

  @Test func artifactsOnAnotherTypeAreAnUnknownKey() throws {
    let read = try read([
      "m.md": "type: month_plan\nmonth: 2026-10\nartifacts: [{id: a, title: T}]",
      "c.md": "type: horizon_corridor\nhorizons: [2036]\nartifacts: scalar",
    ])
    #expect(read.artifacts.isEmpty)
    #expect(artifactProblems(read).isEmpty)
    #expect(read.unread == .nothing)
  }

  @Test func aNoteWhosePeriodIsNotAYearOrQuarterHasItsListRefused() throws {
    let read = try read([
      "q.md": "type: quarter_focus\nperiod: 2026-10\nartifacts: [{id: a, title: T}]",
      "y.md": "type: year_artifacts\nperiod: 2026..2027\nartifacts: [{id: b, title: T}]",
      "z.md": "type: quarter_focus\nperiod: 2026-W41\nartifacts: []",
    ])
    #expect(read.artifacts.isEmpty)
    #expect(
      artifactProblems(read) == [
        "q.md:4:invalidValue (notes.artifacts)", "y.md:4:invalidValue (notes.artifacts)",
      ])
    #expect(
      read.unread == VaultUnread(paths: [], artifactLists: ["q.md", "y.md"], notRecognised: []))
    #expect(read.notes.count == 3)
  }

  @Test func aSkippedNoteHasNoArtifactProblems() throws {
    let read = try read([
      "y.md": "type: year_artifacts\nyear: 26\nartifacts: [{id: a, title: T}, {id: A}]"
    ])
    #expect(read.artifacts.isEmpty)
    #expect(artifactProblems(read).isEmpty)
    #expect(read.unread == VaultUnread(paths: ["y.md"], artifactLists: [], notRecognised: []))
  }

  @Test func aMarkedNoteIsNotReadWhileTheMarkerIsAmbiguous() throws {
    let read = try read([
      "a.md": "moonshine: budget\n" + year(2026, "  - {id: a, title: T}", "  - {id: a}"),
      "b.md": "moonshine: budget",
    ])
    #expect(read.artifacts.isEmpty)
    #expect(
      problems(read.issues) == [
        "a.md:2:budgetNoteDuplicate (moonshine)", "b.md:2:budgetNoteDuplicate (moonshine)",
      ])
    #expect(
      read.unread == VaultUnread(paths: ["a.md", "b.md"], artifactLists: [], notRecognised: []))
  }

  // MARK: Duplicates, carries, several notes for one period

  @Test func anIdTwiceInOneNoteSkipsBothAndReadsTheRest() throws {
    let read = try read([
      "y.md": year(
        2026, "  - {id: a, title: First}", "  - {id: b, title: Other}",
        "  - {id: a, title: Second}")
    ])
    #expect(read.artifacts == [artifact("b", "Other")])
    #expect(
      artifactProblems(read) == [
        "y.md:5:duplicateArtifactId (artifacts.id)", "y.md:7:duplicateArtifactId (artifacts.id)",
      ])
    #expect(read.unread == VaultUnread(paths: [], artifactLists: ["y.md"], notRecognised: []))
  }

  @Test func aDuplicateIsReportedOnAnItemThatIsInvalidForAnotherReason() throws {
    let read = try read([
      "y.md": year(2026, "  - {id: a, title: First}", "  - {id: a, status: started}")
    ])
    #expect(read.artifacts.isEmpty)
    #expect(
      artifactProblems(read) == [
        "y.md:5:duplicateArtifactId (artifacts.id)", "y.md:6:missingKey (artifacts.title)",
        "y.md:6:invalidValue (artifacts.status)", "y.md:6:duplicateArtifactId (artifacts.id)",
      ])
  }

  @Test func anIdInAYearAndOneOfItsQuartersIsADuplicateInBoth() throws {
    let read = try read([
      "Y/2026.md": year(2026, "  - {id: a, title: Year}", "  - {id: b, title: Year only}"),
      "Q/q4.md": quarter("2026-Q4", "  - {id: a, title: Quarter}", "  - {id: c, title: Q}"),
      "Q/q1.md": quarter("2027-Q1", "  - {id: a, title: Next year}"),
    ])
    #expect(
      read.artifacts == [
        artifact("a", "Next year", period: "2027-Q1", in: "Q/q1.md"),
        artifact("c", "Q", period: "2026-Q4", in: "Q/q4.md"),
        artifact("b", "Year only", in: "Y/2026.md"),
      ])
    #expect(
      artifactProblems(read) == [
        "Q/q4.md:5:duplicateArtifactId (artifacts.id)",
        "Y/2026.md:5:duplicateArtifactId (artifacts.id)",
      ])
    #expect(
      read.unread.artifactLists == ["Q/q4.md", "Y/2026.md"])
  }

  @Test func aYearClashesWithEachQuarterInsideItAndQuartersAloneAreCarries() throws {
    let read = try read([
      "a.md": quarter("2026-Q1", "  - {id: x, title: Q1}"),
      "b.md": quarter("2026-Q2", "  - {id: x, title: Q2}"),
      "c.md": year(2026, "  - {id: x, title: Year}"),
      "d.md": quarter("2027-Q1", "  - {id: y, title: Q1}"),
      "e.md": quarter("2027-Q2", "  - {id: y, title: Q2}"),
      "f.md": quarter("2027-Q3", "  - {id: y, title: Q3}"),
    ])
    #expect(read.artifacts.map(\.periodKey) == ["2027-Q1", "2027-Q2", "2027-Q3"])
    #expect(
      artifactProblems(read) == [
        "a.md:5:duplicateArtifactId (artifacts.id)", "b.md:5:duplicateArtifactId (artifacts.id)",
        "c.md:5:duplicateArtifactId (artifacts.id)",
      ])
    #expect(read.unread.artifactLists == ["a.md", "b.md", "c.md"])
  }

  @Test func theSameIdInPeriodsThatDoNotOverlapIsACarry() throws {
    let read = try read([
      "a.md": year(2026, "  - {id: b1, title: Certificate, status: in_progress}"),
      "b.md": year(2027, "  - {id: b1, title: \"Certificate, written part\"}"),
      "c.md": quarter("2026-Q3", "  - {id: rec, title: Programme}"),
      "d.md": quarter("2026-Q4", "  - {id: rec, title: Programme chosen, status: done}"),
    ])
    #expect(
      read.artifacts == [
        artifact("b1", "Certificate", status: .inProgress, in: "a.md"),
        artifact("b1", "Certificate, written part", period: "2027", in: "b.md"),
        artifact("rec", "Programme", period: "2026-Q3", in: "c.md"),
        artifact("rec", "Programme chosen", period: "2026-Q4", status: .done, in: "d.md"),
      ])
    #expect(artifactProblems(read).isEmpty)
    #expect(read.unread == .nothing)
    #expect(
      read.report.contains(
        "artifacts: 4 read (year_artifacts 2 · quarter_focus 2) · without a status: 2"
          + " · ids in more than one period: 2"))
  }

  @Test func ofSeveralNotesForOnePeriodOnlyTheFirstByPathIsRead() throws {
    let read = try read([
      "A/y.md": year(2026, "  - {id: a, title: First}"),
      "B/y copy.md": year(2026, "  - {id: a, title: Copy}", "  - {id: bad}"),
      "C/q.md": "type: quarter_focus\nquarter: 2026-Q4\nartifacts: [{id: q, title: Q}]",
      "D/q.md": "type: quarter_focus\nperiod_start: 2026-10-01\nartifacts: [{id: q, title: D}]",
    ])
    #expect(
      read.artifacts == [
        artifact("a", "First", in: "A/y.md"), artifact("q", "Q", period: "2026-Q4", in: "C/q.md"),
      ])
    #expect(
      artifactProblems(read) == [
        "B/y copy.md:2:duplicatePeriodNote (notes.period)",
        "D/q.md:2:duplicatePeriodNote (notes.period)",
      ])
    #expect(
      read.unread
        == VaultUnread(paths: [], artifactLists: ["B/y copy.md", "D/q.md"], notRecognised: []))
    #expect(read.notes.map(\.path) == ["A/y.md", "B/y copy.md", "C/q.md", "D/q.md"])
  }

  // MARK: Report

  @Test func theReportCountsArtifactsAndProblemsAndNothingFromTheNotes() throws {
    let read = try read([
      "Secret/y.md": year(
        2026, "  - {id: secret-id, title: Secret title}", "  - {id: secret-id, title: X}",
        "  - {id: other, title: Other}", "  - {title: No id}"),
      "Secret/y2.md": year(2026),
    ])
    let report = read.report
    #expect(
      report.contains(
        "artifacts: 1 read (year_artifacts 1 · quarter_focus 0) · without a status: 1"
          + " · ids in more than one period: 0"))
    #expect(report.contains("artifacts skipped: 3 · lists not read in full: 2"))
    #expect(
      report.contains(
        "artifact problems: missingKey 1 · invalidValue 0 · duplicateArtifactId 2"
          + " · duplicatePeriodNote 1"))
    #expect(!report.joined().contains("ecret"))
  }
}
