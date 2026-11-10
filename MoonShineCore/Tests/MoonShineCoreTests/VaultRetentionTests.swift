import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// "Could not read" is not "is gone": a stored note or artifact leaves the store only when the
/// read saw that it is gone. Invented data.
@Suite struct VaultRetentionTests {
  let first = Date(timeIntervalSince1970: 1_790_000_000)
  let second = Date(timeIntervalSince1970: 1_790_086_400)
  let third = Date(timeIntervalSince1970: 1_790_172_800)
  static let year = "Years/Artifacts_2026.md"

  var source: TaskSourceSnapshot {
    TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: first, timeZone: TestWorld.timeZone,
      defaultTimes: DefaultTimeSettings(),
      tags: [SourceTag(externalId: "t-violin", name: "violin")], projects: [],
      tasks: [SourceTask(externalId: "x", name: "Scales", tagExternalIds: ["t-violin"])])
  }

  func yearNote(_ year: Int = 2026, path: String? = nil, title: String = "Artifacts") -> SourceNote
  {
    SourceNote(
      path: path ?? "Years/Artifacts_\(year).md", title: title, type: "year_artifacts",
      scale: .year,
      period: Horizon.containing(
        TestWorld.date(year, 6, 1), scale: .year, calendar: TestWorld.calendar))
  }

  func artifact(
    _ key: String, title: String? = nil, period: String = "2026", note: String = year
  ) -> SourceArtifact {
    SourceArtifact(
      key: key, periodKey: period, title: title ?? key, lineKeys: ["violin"], status: .planned,
      notePath: note)
  }

  func vault(
    _ notes: [SourceNote], _ artifacts: [SourceArtifact], unread: VaultUnread = .nothing
  ) -> VaultSnapshot {
    let violin = SourceLine(
      key: "violin", name: "Violin", block: "Creative", state: .active, tags: ["violin"])
    return VaultSnapshot(
      lines: .read([violin], complete: true), artifacts: artifacts, notes: notes, unread: unread)
  }

  /// Imports the snapshots in order into one store; returns each import's workspace and the
  /// store after the last one.
  func importing(_ snapshots: VaultSnapshot...) -> (runs: [Workspace], stored: StoredWorkspace) {
    var identities = IdentityMap()
    var stored = StoredWorkspace(timeZone: TestWorld.timeZone)
    var runs: [Workspace] = []
    for (snapshot, now) in zip(snapshots, [first, second, third]) {
      let workspace = Importer(metaTagGroups: []).makeWorkspace(
        tasks: source, vault: snapshot, stored: stored.workspace, approvedLineRemovals: [],
        identities: &identities, now: now)
      stored = stored.merging(workspace, at: now)
      runs.append(workspace)
    }
    return (runs, stored)
  }

  let notRecognised = ImportIssue.vault(
    path: year, line: nil, problem: VaultProblem(.noteNotRecognised))

  @Test func aNoteThatExistsButWasNotReadKeepsItsFieldsAndItsArtifacts() {
    let unread = VaultUnread(paths: [Self.year], artifactLists: [], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b")]), vault([], [], unread: unread))
    #expect(runs[1].notes == runs[0].notes)
    #expect(runs[1].artifacts == runs[0].artifacts)
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
    // The reader has already reported why; the importer adds nothing.
    #expect(runs[1].issues.isEmpty)
  }

  @Test func anUnreadFolderCoversWhatIsBelowItAndNothingBesideIt() {
    let unread = VaultUnread(paths: ["A/b", "C/d.md"], artifactLists: [], notRecognised: [])
    #expect(unread.covers("A/b/c.md") && unread.covers("A/b/c/d.md") && unread.covers("A/b"))
    #expect(unread.covers("C/d.md"))
    #expect(!unread.covers("A/b.md") && !unread.covers("A/bc/d.md") && !unread.covers("A"))
    #expect(!unread.covers("X/A/b/c.md") && !unread.covers("C/d.md.md") && !unread.covers(""))
    #expect(!VaultUnread.nothing.covers("A/b"))
  }

  @Test func aNoteUnderAnUnreadFolderIsKept() {
    let unread = VaultUnread(paths: ["Years"], artifactLists: [], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a")]), vault([], [], unread: unread))
    #expect(runs[1].notes == runs[0].notes && runs[1].artifacts == runs[0].artifacts)
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
  }

  @Test func aNoteStillInTheVaultButNotRecognisedIsKeptWithItsArtifactsAndReported() {
    let unread = VaultUnread(paths: [], artifactLists: [], notRecognised: [Self.year, "Other.md"])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b")]), vault([], [], unread: unread),
      vault([yearNote()], [artifact("a"), artifact("b")]))
    #expect(runs[1].notes == runs[0].notes)
    #expect(runs[1].artifacts == runs[0].artifacts)
    // Once, for the stored note only: a file that never was a note is not a problem.
    #expect(runs[1].issues == [notRecognised])
    // Recognised again: the problem goes, and the ids are the same.
    #expect(runs[2].issues.isEmpty)
    #expect(runs[2].notes.map(\.id) == runs[0].notes.map(\.id))
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  @Test func aNoteWhoseFileIsGoneIsSoftDeletedAndReturnsWithItsId() {
    let full = vault([yearNote()], [artifact("a")])
    let (gone, afterGone) = importing(full, vault([], []))
    #expect(gone[1].notes.isEmpty && gone[1].artifacts.isEmpty && gone[1].issues.isEmpty)
    #expect(afterGone.notes.map(\.removedAt) == [second])
    #expect(afterGone.artifacts.map(\.removedAt) == [second])
    let (back, afterBack) = importing(full, vault([], []), full)
    #expect(back[2].notes.map(\.id) == back[0].notes.map(\.id))
    #expect(back[2].artifacts.map(\.id) == back[0].artifacts.map(\.id))
    #expect(afterBack.notes.allSatisfy { !$0.isRemoved })
  }

  @Test func anIncompleteArtifactListUpdatesWhatWasReadAndKeepsTheRestInPlace() {
    let lists = VaultUnread(paths: [], artifactLists: [Self.year], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b"), artifact("c")]),
      vault(
        [yearNote(title: "Renamed")],
        [artifact("a", title: "A2"), artifact("c"), artifact("d")], unread: lists))
    // `b` was skipped in the middle of the list: it keeps its place, as stored.
    #expect(runs[1].artifacts.map(\.key) == ["a", "b", "c", "d"])
    #expect(runs[1].artifacts.map(\.title) == ["A2", "b", "c", "d"])
    #expect(runs[1].artifacts[1] == runs[0].artifacts[1])
    #expect(runs[1].notes.map(\.title) == ["Renamed"])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  @Test func aCleanReadTakesItsOwnOrderAndRemovesWhatItNoLongerLists() {
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b"), artifact("c")]),
      vault([yearNote()], [artifact("c"), artifact("a")]))
    #expect(runs[1].artifacts.map(\.key) == ["c", "a"])
    #expect(stored.artifacts.filter(\.isRemoved).map(\.entity.key) == ["b"])
  }

  @Test func aVaultThatWasNotReadKeepsEveryLineNoteAndArtifact() {
    let (runs, stored) = importing(vault([yearNote()], [artifact("a")]), .notRead())
    #expect(runs[1].lines == runs[0].lines)
    #expect(runs[1].notes == runs[0].notes && runs[1].artifacts == runs[0].artifacts)
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  /// "Nothing was read" cannot come with lines: only `notRead` says it, and it fixes the rest.
  @Test func onlyNotReadSaysTheVaultWasNotReadAndItNeverCarriesLines() {
    let issue = ImportIssue.vaultWide(VaultProblem(.unreadable))
    let notRead = VaultSnapshot.notRead(issues: [issue])
    #expect(!notRead.isRead && notRead.lines == .unavailable)
    #expect(notRead.notes.isEmpty && notRead.artifacts.isEmpty && notRead.issues == [issue])
    // Every snapshot built by the initialiser was read, whatever unread value it is given,
    // the one taken from `notRead` included.
    #expect(vault([], [], unread: notRead.unread).isRead)
    #expect(vault([], []).isRead)
  }

  @Test func theSameIdInAnotherPeriodIsAnotherAppearanceWithItsOwnIdentity() throws {
    let both = vault(
      [yearNote(2026), yearNote(2027)],
      [
        artifact("a"),
        artifact("a", title: "A, carried", period: "2027", note: "Years/Artifacts_2027.md"),
      ])
    let (runs, _) = importing(both, both)
    let ids = runs[0].artifacts.map(\.id)
    #expect(Set(ids).count == 2)
    #expect(runs[0].artifacts.map(\.key) == ["a", "a"])
    #expect(runs[1].artifacts.map(\.id) == ids)
    #expect(
      runs[0].artifacts.map { $0.refs.map(\.externalId) } == [["a@2026"], ["a@2027"]])
    // The trace ends at the appearance whose period contains "now".
    let task = try #require(runs[0].tasks.first)
    for (now, title) in [
      (TestWorld.date(2026, 10, 10), "a"), (TestWorld.date(2027, 3, 1), "A, carried"),
    ] {
      guard case .artifact(let target) = Tracer(workspace: runs[0], now: now).trace(task).target
      else {
        Issue.record("no artifact target")
        continue
      }
      #expect(target.title == title)
    }
  }

  @Test func aCarriedAppearanceStaysWhenTheSameIdIsReadInAPeriodThatDoesNotOverlap() {
    let unread = VaultUnread(paths: [Self.year], artifactLists: [], notRecognised: [])
    let next = "Years/Artifacts_2027.md"
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a")]),
      vault([yearNote(2027)], [artifact("a", period: "2027", note: next)], unread: unread))
    #expect(runs[1].artifacts.map { $0.refs.map(\.externalId) } == [["a@2026"], ["a@2027"]])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  var quarter: SourceNote {
    SourceNote(
      path: "Years/Q4_2026.md", title: "Q4", type: "quarter_focus", scale: .quarter,
      period: Horizon.containing(
        TestWorld.date(2026, 11, 1), scale: .quarter, calendar: TestWorld.calendar))
  }

  func quarterItem(_ key: String) -> SourceArtifact {
    artifact(key, period: "2026-Q4", note: quarter.path)
  }

  func appearances(_ workspace: Workspace) -> [String] {
    workspace.artifacts.flatMap { $0.refs.map(\.externalId) }
  }

  /// "The item read wins" only for the same identity, where it is an update.
  @Test func theSameAppearanceReadFromAnotherNoteIsAnUpdate() {
    let unread = VaultUnread(paths: [Self.year], artifactLists: [], notRecognised: [])
    let copy = "Years/Copy_2026.md"
    let (runs, _) = importing(
      vault([yearNote()], [artifact("a")]),
      vault([yearNote(path: copy)], [artifact("a", title: "A2", note: copy)], unread: unread))
    #expect(runs[1].artifacts.map(\.title) == ["A2"])
    #expect(runs[1].artifacts.map(\.id) == runs[0].artifacts.map(\.id))
    #expect(runs[1].artifacts.first?.noteID == runs[1].notes.first { $0.path == copy }?.id)
  }

  /// A duplicate id in a year note and its quarter. The duplicate check runs over read items
  /// only, so while the duplicate is in the vault the store depends on what could be read.
  /// Direction one: the year note is unread for one import, so the quarter's item is read.
  @Test func aCarriedAppearanceStaysWhateverIsReadElsewhereAndBothSurviveTheDuplicate() {
    let yearUnread = VaultUnread(paths: [Self.year], artifactLists: [], notRecognised: [])
    // Both notes read: the reader skips both items and names both lists as incomplete.
    let duplicate = VaultUnread(
      paths: [], artifactLists: [Self.year, quarter.path], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b")]),
      vault([quarter], [quarterItem("a")], unread: yearUnread),
      vault([yearNote(), quarter], [artifact("b")], unread: duplicate))
    #expect(appearances(runs[1]) == ["a@2026", "b@2026", "a@2026-Q4"])
    #expect(appearances(runs[2]) == ["a@2026", "b@2026", "a@2026-Q4"])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  /// Direction two: the same vault state without the unread import stores the year's only.
  @Test func theSameDuplicateWithoutTheUnreadImportKeepsOnlyWhatWasStored() {
    let duplicate = VaultUnread(
      paths: [], artifactLists: [Self.year, quarter.path], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a"), artifact("b")]),
      vault([yearNote(), quarter], [artifact("b")], unread: duplicate))
    #expect(appearances(runs[1]) == ["a@2026", "b@2026"])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  /// Stored positions are kept only inside a note that has something carried; a note read in
  /// full takes the order of the read, whatever happens to other notes.
  @Test func aNoteReadInFullKeepsItsOwnOrderNextToAnUnreadNote() {
    let unread = VaultUnread(paths: [quarter.path], artifactLists: [], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote(), quarter], [artifact("a"), artifact("b"), quarterItem("q")]),
      vault([yearNote()], [artifact("n"), artifact("b"), artifact("a")], unread: unread))
    #expect(runs[1].artifacts.map(\.key) == ["n", "b", "a", "q"])
    // Notes stay in path order with one carried between or after the read ones.
    #expect(runs[1].notes.map(\.path) == [Self.year, quarter.path])
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  @Test func aCarriedNoteTakesItsPlaceInPathOrder() {
    let first = SourceNote(path: "A.md", title: "A", type: "month_plan")
    let last = SourceNote(path: "Z.md", title: "Z", type: "month_plan")
    let unread = VaultUnread(paths: ["A.md"], artifactLists: [], notRecognised: [])
    let (runs, _) = importing(
      vault([first, yearNote(), last], []), vault([last, yearNote()], [], unread: unread))
    #expect(runs[1].notes.map(\.path) == ["A.md", Self.year, "Z.md"])
  }

  /// An incomplete artifact list means the note's file exists: the note is kept even when a
  /// reader names it nowhere else.
  @Test func aNoteNamedOnlyByItsArtifactListIsKeptWithItsArtifacts() {
    let lists = VaultUnread(paths: [], artifactLists: [Self.year], notRecognised: [])
    let (runs, stored) = importing(
      vault([yearNote()], [artifact("a")]), vault([], [], unread: lists))
    #expect(runs[1].notes == runs[0].notes && runs[1].artifacts == runs[0].artifacts)
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }

  /// Serves the given snapshots in turn.
  actor Vaults: NoteProvider {
    private var snapshots: [VaultSnapshot]
    init(_ snapshots: [VaultSnapshot]) { self.snapshots = snapshots }
    func vault() async throws -> VaultSnapshot { snapshots.removeFirst() }
  }

  struct Tasks: TaskProvider {
    let source: TaskSourceSnapshot
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot { source }
  }

  @Test func theServiceKeepsAStoredNoteAndItsArtifactsWhenTheNoteCannotBeRead() async throws {
    let unread = VaultUnread(paths: [Self.year], artifactLists: [], notRecognised: [])
    let store = InMemoryStore(timeZone: TestWorld.timeZone)
    let time = SettableClock(first)
    let service = ImportService(
      tasks: Tasks(source: source),
      notes: Vaults([vault([yearNote()], [artifact("a")]), vault([], [], unread: unread)]),
      store: store, importer: Importer(metaTagGroups: []), clock: time.clock)
    let before = try await service.run(ImportRequest(trigger: .manual))
    time.set(second)
    try await service.run(ImportRequest(trigger: .manual))
    let stored = await store.stored()
    #expect(stored.notes.map(\.entity) == before.notes)
    #expect(stored.artifacts.map(\.entity) == before.artifacts)
    #expect(stored.notes.allSatisfy { !$0.isRemoved })
    #expect(stored.artifacts.allSatisfy { !$0.isRemoved })
  }
}
