import Foundation
import MoonShineCore
import MoonShineFixtures
import ObsidianAdapter
import OmniFocusAdapter
import Synchronization
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5).
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

/// The vault folder in the live import (S4-4d): the bookmark, the provider, the Settings row
/// and the status bar. Every folder is a temporary one with invented notes.
@MainActor @Suite struct VaultFolderTests {
  nonisolated static let budget =
    "---\nmoonshine: budget\nlines:\n  - {id: violin, name: Violin, block: Creative, state: active}\n---\n"

  /// Temporary vault folders, removed when the test ends (PR #53 round 1).
  final class Folders {
    private var made: [URL] = []

    /// With `.obsidian` and the budget note unless told otherwise.
    func make(vault: Bool = true) throws -> URL {
      let root = try VaultFolderTests.folder(vault: vault)
      made.append(root)
      return root
    }

    deinit {
      for root in made { try? FileManager.default.removeItem(at: root) }
    }
  }

  let folders = Folders()

  /// A temporary folder; the caller removes it (`Folders` does).
  nonisolated static func folder(vault: Bool = true) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "vault-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if vault {
      try FileManager.default.createDirectory(
        at: root.appending(path: ".obsidian"), withIntermediateDirectories: false)
    }
    try Data(budget.utf8).write(to: root.appending(path: "Budget.md"))
    return root
  }

  /// Bookmarks as the folder's path; `stale` and `fails` script the resolution.
  final class FakeBookmarks: @unchecked Sendable {
    var stale = false
    var fails = false
    var makeFails = false
    /// Runs inside `resolve`, which runs off the main actor.
    var whileResolving: (@Sendable () -> Void)?
    /// Run once on the main actor inside the next `make` off it, as a choice landing during a
    /// refresh would.
    var duringMake: (@MainActor () -> Void)?

    var bookmarks: VaultFolder.Bookmarks {
      VaultFolder.Bookmarks(
        make: { [self] url in
          if makeFails { throw CocoaError(.fileWriteNoPermission) }
          if let run = duringMake {
            duringMake = nil
            if Thread.isMainThread {
              MainActor.assumeIsolated { run() }
            } else {
              DispatchQueue.main.sync { MainActor.assumeIsolated { run() } }
            }
          }
          return Data(url.path(percentEncoded: false).utf8)
        },
        resolve: { [self] data in
          whileResolving?()
          if fails { throw CocoaError(.fileReadCorruptFile) }
          return (URL(filePath: String(decoding: data, as: UTF8.self)), stale)
        })
    }
  }

  static let chosenAt = Date(timeIntervalSince1970: 1_790_000_000)

  func vaultWide(_ snapshot: VaultSnapshot) -> [VaultProblem.Kind] {
    snapshot.issues.compactMap { issue in
      if case .vaultWide(let problem) = issue { problem.kind } else { nil }
    }
  }

  // MARK: The provider

  @Test func noBookmarkMeansTheVaultIsNotChosen() async {
    let snapshot = await BookmarkedVault(folder: VaultFolder(settings: CountingSettings(nil)))
      .vault(timeZone: DemoVault.calendar.timeZone)
    #expect(!snapshot.isRead)
    #expect(vaultWide(snapshot) == [.vaultNotChosen])
  }

  /// PR #53 round 1: resolving runs off the main actor, so a slow or unreachable folder never
  /// blocks the window. The fake resolution waits for a main-actor task: on the main actor it
  /// would wait out its 5 s and report that the main actor was busy.
  @Test func anUnresolvableBookmarkIsUnreadableWithoutBlockingTheMainActor() async throws {
    let settings = CountingSettings("live")
    let fake = FakeBookmarks()
    let folder = VaultFolder(settings: settings, bookmarks: fake.bookmarks)
    try folder.choose(folders.make())
    fake.fails = true
    let mainRan = DispatchSemaphore(value: 0)
    let mainWasFree = Mutex(false)
    fake.whileResolving = {
      let ran = mainRan.wait(timeout: .now() + .seconds(5)) == .success
      mainWasFree.withLock { $0 = ran }
    }
    Task { @MainActor in mainRan.signal() }
    let snapshot = await BookmarkedVault(folder: folder).vault(timeZone: .gmt)
    #expect(mainWasFree.withLock { $0 })
    #expect(!snapshot.isRead)
    #expect(vaultWide(snapshot) == [.vaultUnreadable])
  }

  @Test func theRealResolutionNeverShowsUIOrMounts() {
    #expect(
      VaultFolder.Bookmarks.resolveOptions == [.withSecurityScope, .withoutUI, .withoutMounting])
  }

  /// The real security-scoped bookmark, made and resolved in the test host (unsandboxed).
  @Test func aBookmarkOfATemporaryFolderReadsItsBudgetNote() async throws {
    let root = try folders.make()
    let settings = CountingSettings("live")
    let folder = VaultFolder(settings: settings)
    try folder.choose(root)
    #expect(settings.vaultWrites.count == 1)
    #expect(folder.chosen?.name == root.lastPathComponent)
    let snapshot = await BookmarkedVault(folder: folder).vault(timeZone: .gmt)
    #expect(snapshot.isRead)
    #expect(snapshot.lines.read.map(\.key) == ["violin"])
  }

  @Test func aFolderWithoutObsidianIsRefusedAndNothingIsSaved() throws {
    let settings = CountingSettings("live")
    let model = AppModel(isTestHost: false, settings: settings) { _ in nil }
    model.chooseVault(try folders.make(vault: false))
    #expect(model.vaultRefusal == .notAVault)
    #expect(settings.vaultWrites.isEmpty)
    #expect(model.vaultFolder.chosen == nil)
    model.chooseVault(try folders.make())
    #expect(model.vaultRefusal == nil)
    #expect(settings.vaultWrites.count == 1)
  }

  /// Owner, 2026-11-10 (PR #53 round 1): a new folder whose bookmark cannot be made keeps the
  /// old vault, and the sentence says so.
  @Test func aNewFolderThatCannotBeKeptKeepsTheOldVaultAndSaysSo() throws {
    let settings = CountingSettings("live")
    let fake = FakeBookmarks()
    let folder = VaultFolder(settings: settings, bookmarks: fake.bookmarks)
    let model = AppModel(isTestHost: false, settings: settings, vaultFolder: folder) { _ in nil }
    #expect(VaultRefusalLine(refusal: .bookmarkFailed, chosen: nil) == .notKept)
    let old = try folders.make()
    model.chooseVault(old)
    fake.makeFails = true
    model.chooseVault(try folders.make())
    #expect(model.vaultRefusal == .bookmarkFailed)
    #expect(model.vaultFolder.chosen?.name == old.lastPathComponent)
    #expect(settings.vaultWrites.count == 1)
    #expect(
      VaultRefusalLine(refusal: .bookmarkFailed, chosen: model.vaultFolder.chosen)
        == .keptPrevious(old.lastPathComponent))
    #expect(VaultRefusalLine(refusal: .notAVault, chosen: model.vaultFolder.chosen) == .notAVault)
  }

  @Test func aStaleBookmarkIsMadeAgainAndKeepsItsTime() async throws {
    let settings = CountingSettings("live")
    let fake = FakeBookmarks()
    let folder = VaultFolder(settings: settings, bookmarks: fake.bookmarks, now: { Self.chosenAt })
    let root = try folders.make()
    try folder.choose(root)
    fake.stale = true
    #expect(await folder.resolve() == .folder(URL(filePath: root.path(percentEncoded: false))))
    #expect(settings.vaultWrites.count == 2)
    #expect(settings.vaultWrites.last?.savedAt == Self.chosenAt)
  }

  /// Compare-and-set: a choice that lands while a stale bookmark is made again wins.
  @Test func aRefreshNeverOverwritesANewerChoice() async throws {
    let settings = CountingSettings("live")
    let fake = FakeBookmarks()
    let folder = VaultFolder(settings: settings, bookmarks: fake.bookmarks)
    try folder.choose(folders.make())
    let newer = try folders.make()
    fake.stale = true
    fake.duringMake = { try? folder.choose(newer) }
    _ = await folder.resolve()
    #expect(settings.vaultWrites.count == 2)
    #expect(settings.vaultWrites.last?.name == newer.lastPathComponent)
    #expect(folder.chosen?.name == newer.lastPathComponent)
  }

  /// The owner's Q5 (2026-11-10): a folder that is still there but no longer holds `.obsidian`
  /// (a sync reset) is unreadable, and nothing stored is soft-deleted.
  @Test func aFolderThatLosesObsidianIsUnreadableAndNothingIsSoftDeleted() async throws {
    let root = try folders.make()
    let settings = CountingSettings("live")
    let folder = VaultFolder(settings: settings, bookmarks: FakeBookmarks().bookmarks)
    try folder.choose(root)
    let store = InMemoryStore(timeZone: .gmt)
    let service = ImportService(
      tasks: SnapshotFileTaskProvider(url: trackedSnapshot), notes: BookmarkedVault(folder: folder),
      store: store, importer: Importer(metaTagGroups: []),
      vaultTimeZone: { DemoVault.calendar.timeZone }, clock: DemoEnvironment.clock)
    let first = try await service.run(ImportRequest(trigger: .manual))
    try #require(first.lines.map(\.key) == ["violin"] && first.notes.count == 1)
    try FileManager.default.removeItem(at: root.appending(path: ".obsidian"))
    let second = try await service.run(ImportRequest(trigger: .manual))
    #expect(second.lines == first.lines)
    #expect(second.notes == first.notes)
    #expect(second.issues.contains(.vaultWide(VaultProblem(.vaultUnreadable))))
    #expect(try await store.stored().notes.allSatisfy { !$0.isRemoved })
  }

  // MARK: The Settings row and the status bar

  static let bookmark = StoredBookmark(data: Data([1]), name: "Life", savedAt: chosenAt)

  static func workspace(_ kinds: VaultProblem.Kind...) -> Workspace {
    Workspace(
      timeZone: .gmt, issues: kinds.map { .vaultWide(VaultProblem($0)) } + [.defaultTimesNotRead])
  }

  static func run(startedAt: Date) -> ImportRun {
    ImportRun(
      trigger: .manual, startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(4),
      waited: nil, duration: .seconds(4), providerHeld: nil,
      outcome: .committed(
        ImportCounts(lines: 1, notes: 1, artifacts: 0, projects: 0, tasks: 0, tags: 0)))
  }

  static let later = run(startedAt: chosenAt.addingTimeInterval(60))

  @Test func theVaultRowStates() {
    let live = { (chosen: StoredBookmark?, workspace: Workspace?, run: ImportRun?) in
      VaultLine(source: .live, chosen: chosen, workspace: workspace, lastImport: run)
    }
    #expect(live(nil, Self.workspace(.vaultNotChosen), Self.later) == .notChosen)
    #expect(live(Self.bookmark, nil, nil) == .notReadYet)
    #expect(live(Self.bookmark, Self.workspace(), Self.later) == .folder("Life"))
    #expect(live(Self.bookmark, Self.workspace(.vaultUnreadable), Self.later) == .unreadable)
    #expect(
      live(Self.bookmark, Self.workspace(.vaultTooLarge), Self.later)
        == .tooLarge(VaultLimits().maxNotes))
  }

  /// A choice made while an import ran: that import read the old folder, or none.
  @Test func aChoiceDuringAnImportReadsNotReadYet() {
    let started = Self.run(startedAt: Self.chosenAt.addingTimeInterval(-1))
    #expect(
      VaultLine(
        source: .live, chosen: Self.bookmark, workspace: Self.workspace(), lastImport: started)
        == .notReadYet)
    #expect(
      VaultLine(
        source: .live, chosen: Self.bookmark, workspace: Self.workspace(.vaultNotChosen),
        lastImport: Self.later) == .notReadYet)
  }

  @Test func demoNeverShowsTheBookmark() {
    #expect(
      VaultLine(
        source: .demo, chosen: Self.bookmark, workspace: Self.workspace(), lastImport: Self.later)
        == .notReadInDemo)
  }

  @Test func theStatusBarSaysVaultNotReadOnlyWhileItIsNot() {
    #expect(VaultLine.vaultNotRead(nil))
    #expect(VaultLine.vaultNotRead(Self.workspace(.vaultNotChosen)))
    #expect(VaultLine.vaultNotRead(Self.workspace(.vaultUnreadable)))
    #expect(VaultLine.vaultNotRead(Self.workspace(.vaultTooLarge)))
    #expect(!VaultLine.vaultNotRead(Self.workspace()))
    #expect(!VaultLine.vaultNotRead(Self.workspace(.budgetNoteMissing)))
  }

  // MARK: The kept approval's sentence

  @Test func anApprovalKeptByAnIncompleteReadSaysSoUnlessOmniFocusIsClosed() {
    let hold = { (closed: Bool, kept: Bool) in
      LineRemovalHold(
        isApproved: true, omniFocusClosed: closed, keptByIncompleteRead: kept, approve: {})
    }
    #expect(hold(false, false).approvedNote == .nextImport)
    #expect(hold(false, true).approvedNote == .notReadInFull)
    #expect(hold(true, true).approvedNote == .onceOmniFocusIsOpen)
    #expect(hold(true, false).approvedNote == .onceOmniFocusIsOpen)
  }
}
