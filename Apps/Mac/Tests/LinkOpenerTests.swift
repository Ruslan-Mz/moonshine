import Foundation
import MoonShineCore
import SwiftUI
import Synchronization
import Testing

@testable import MoonShineMac

/// The one opener (S4-5): what it opens, what it refuses, and its notice. A recorder stands in
/// for the system; the vault is a temporary folder with invented notes (CLAUDE.md rule 5).
@MainActor @Suite struct LinkOpenerTests {
  final class Recorder: URLOpening {
    var opened: [URL] = []
    var accepts = true

    func open(_ url: URL) -> Bool {
      opened.append(url)
      return accepts
    }
  }

  /// Each sleep waits until the test lets it go.
  final class ManualSleep: Sendable {
    let gates = Mutex<[CheckedContinuation<Void, Never>]>([])

    var count: Int { gates.withLock { $0.count } }

    func sleep() async {
      await withCheckedContinuation { gate in gates.withLock { $0.append(gate) } }
    }

    func release(_ index: Int) {
      gates.withLock { $0[index] }.resume()
    }

    /// Yields until `count` sleeps wait; bounded, so a notice that never starts a timer fails
    /// instead of hanging the run.
    @discardableResult
    func waitFor(_ count: Int) async -> Bool {
      for _ in 0..<10_000 {
        if self.count >= count { return true }
        await Task.yield()
      }
      return false
    }
  }

  static let now = Date(timeIntervalSince1970: 1_790_000_000)
  static let line = LineID.generate(at: now)
  static let taskID = TaskItemID.generate(at: now)
  static let bareTaskID = TaskItemID.generate(at: now)
  static let badTaskID = TaskItemID.generate(at: now)
  static let projectID = ProjectID.generate(at: now)
  static let noteIDs: [String: NoteID] = Dictionary(
    uniqueKeysWithValues: notePaths.map { ($0, NoteID.generate(at: now)) })
  /// Invented paths: present, missing, escaping, hidden, linked, in another case or form.
  static let notePaths = [
    "Notes/Plan.md", "Notes/Missing.md", "../outside.md", "/abs.md", ".obsidian/app.md",
    ".trash/Old.md", "Notes/Linked.md", "Linked folder/Inner.md", "Notes/plan.md",
    "Notes/Caf\u{00E9}.md", "Notes//Plan.md", "Notes", "Notes/A & B+C #1?.md",
    "Заметки/Йога.md",
  ]

  static func ref(_ id: String) -> [ExternalRef] {
    [ExternalRef(provider: .omnifocus, externalId: id, lastSeen: now)]
  }

  static func task(_ id: TaskItemID, refs: [ExternalRef]) -> TaskItem {
    TaskItem(
      id: id, refs: refs, title: "Invented task", projectID: projectID, parentTaskID: nil,
      tagIDs: [], status: .available, flagged: false, plannedAt: nil, deferUntil: nil,
      dueAt: nil, effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: nil,
      estimateMinutes: nil, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
      line: .line(line))
  }

  static let overview = Overview(
    workspace: Workspace(
      timeZone: .gmt,
      notes: notePaths.map { path in
        NoteRef(
          id: noteIDs[path]!, refs: [], path: path, title: "Invented note", type: nil,
          scale: nil, period: nil, parentLink: nil, lineKey: nil, status: nil)
      },
      projects: [
        Project(
          id: projectID, refs: ref("kP9_q-2"), title: "Invented project", status: .active,
          tagIDs: [], line: .line(line))
      ],
      tasks: [
        task(taskID, refs: ref("aB3dE5fG7hJ")), task(bareTaskID, refs: []),
        task(badTaskID, refs: ref("a/b?add=x")),
      ]),
    now: now)

  /// A vault with `.obsidian`, the invented notes, a file outside it and links that lead out.
  final class Vault {
    let root: URL
    let outside: URL

    init() throws {
      let fm = FileManager.default
      let base = fm.temporaryDirectory.appending(path: "opener-\(UUID().uuidString)")
      root = base.appending(path: "My Vault")
      outside = base.appending(path: "Outside")
      for folder in [".obsidian", ".trash", "Notes", "Заметки"] {
        try fm.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
      }
      try fm.createDirectory(at: outside, withIntermediateDirectories: true)
      for file in [
        "Notes/Plan.md", ".obsidian/app.md", ".trash/Old.md", "Notes/A & B+C #1?.md",
        "Заметки/Йога.md",
        // Decomposed é on disk; the store holds the composed form.
        "Notes/Cafe\u{0301}.md",
      ] {
        try Data("invented".utf8).write(to: root.appending(path: file))
      }
      try Data("invented".utf8).write(to: base.appending(path: "outside.md"))
      try Data("invented".utf8).write(to: outside.appending(path: "Inner.md"))
      try fm.createSymbolicLink(
        at: root.appending(path: "Notes/Linked.md"),
        withDestinationURL: base.appending(path: "outside.md"))
      try fm.createSymbolicLink(
        at: root.appending(path: "Linked folder"), withDestinationURL: outside)
    }

    deinit { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
  }

  let recorder = Recorder()
  let sleeper = ManualSleep()

  func opener(vault: VaultFolder) -> LinkOpener {
    let sleeper = sleeper
    return LinkOpener(
      opening: recorder, vault: vault, noticeDelay: .seconds(5),
      sleep: { _ in await sleeper.sleep() })
  }

  func chosen(_ vault: Vault) throws -> VaultFolder {
    let folder = VaultFolder(
      settings: CountingSettings("live"), bookmarks: VaultFolderTests.FakeBookmarks().bookmarks)
    try folder.choose(vault.root)
    return folder
  }

  func open(_ target: OpenTarget, vault: VaultFolder? = nil, isDemo: Bool = false) async
    -> OpenOutcome
  {
    await opener(vault: vault ?? VaultFolder(settings: CountingSettings(nil)))
      .open(target, in: Self.overview, isDemo: isDemo)
  }

  // MARK: OmniFocus

  @Test func aTaskAndAProjectOpenExactlyTheirURLs() async {
    #expect(await open(.task(Self.taskID)) == .opened)
    #expect(await open(.project(Self.projectID)) == .opened)
    #expect(
      recorder.opened.map(\.absoluteString) == [
        "omnifocus:///task/aB3dE5fG7hJ", "omnifocus:///project/kP9_q-2",
      ])
  }

  @Test func noRefAnUnknownIdOrARefusedIdOpensNothing() async {
    #expect(await open(.task(Self.bareTaskID)) == .notOpened)
    #expect(await open(.task(Self.badTaskID)) == .notOpened)
    #expect(await open(.task(TaskItemID.generate(at: Self.now))) == .notOpened)
    #expect(await open(.project(ProjectID.generate(at: Self.now))) == .notOpened)
    #expect(recorder.opened.isEmpty)
  }

  @Test func anAppThatTakesNothingIsNotOpened() async {
    recorder.accepts = false
    #expect(await open(.task(Self.taskID)) == .notOpened)
  }

  // MARK: Obsidian

  @Test func aNoteInTheVaultOpensWithVaultAndFileOnly() async throws {
    let vault = try Vault()
    let folder = try chosen(vault)
    #expect(await open(.note(Self.noteIDs["Notes/Plan.md"]!), vault: folder) == .opened)
    #expect(await open(.note(Self.noteIDs["Notes/A & B+C #1?.md"]!), vault: folder) == .opened)
    let items = recorder.opened.map {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    }
    #expect(
      items == [
        [
          URLQueryItem(name: "vault", value: "My Vault"),
          URLQueryItem(name: "file", value: "Notes/Plan.md"),
        ],
        [
          URLQueryItem(name: "vault", value: "My Vault"),
          URLQueryItem(name: "file", value: "Notes/A & B+C #1?.md"),
        ],
      ])
    #expect(recorder.opened.allSatisfy { $0.scheme == "obsidian" && $0.host == "open" })
  }

  /// Missing, escaping, absolute, hidden, linked, another case, another Unicode form, an empty
  /// component, a folder: nothing opens (ADR-0015, 2026-10-13; owner, 2026-11-25).
  @Test(arguments: [
    "Notes/Missing.md", "../outside.md", "/abs.md", ".obsidian/app.md", ".trash/Old.md",
    "Notes/Linked.md", "Linked folder/Inner.md", "Notes/plan.md", "Notes/Caf\u{00E9}.md",
    "Notes//Plan.md", "Notes",
  ])
  func aNoteNotFoundByteForByteOpensNothing(_ path: String) async throws {
    let vault = try Vault()
    let folder = try chosen(vault)
    #expect(await open(.note(Self.noteIDs[path]!), vault: folder) == .noteNotFound)
    #expect(recorder.opened.isEmpty)
  }

  /// Cyrillic with a letter that has a decomposed form (й): the stored path is what the vault
  /// walk reports (`ObsidianAdapter/VaultWalk.swift`: the enumerator's URLs, relative to the
  /// root), whatever form the file system keeps, and it opens.
  @Test func aNoteOpensInTheFormTheVaultWalkStoredIt() async throws {
    let vault = try Vault()
    let folder = try chosen(vault)
    let root = vault.root.resolvingSymlinksInPath().standardizedFileURL
    let walker = try #require(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    let stored = try #require(
      walker.compactMap { ($0 as? URL)?.standardizedFileURL.path }
        // `Заметки` has no letter with a decomposed form, so it matches in either form.
        .first { $0.hasSuffix(".md") && $0.contains("/Заметки/") }
        .map { String($0.dropFirst(root.path.count + 1)) })
    let id = NoteID.generate(at: Self.now)
    let overview = Overview(
      workspace: Workspace(
        timeZone: .gmt,
        notes: [
          NoteRef(
            id: id, refs: [], path: stored, title: "Invented note", type: nil, scale: nil,
            period: nil, parentLink: nil, lineKey: nil, status: nil)
        ]),
      now: Self.now)
    let outcome = await opener(vault: folder).open(.note(id), in: overview, isDemo: false)
    #expect(outcome == .opened)
    let items = recorder.opened.first.flatMap {
      URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    }
    #expect(items?.last == URLQueryItem(name: "file", value: stored))
  }

  @Test func aNoteNotInTheWorkspaceIsNotFound() async throws {
    let vault = try Vault()
    let folder = try chosen(vault)
    #expect(await open(.note(NoteID.generate(at: Self.now)), vault: folder) == .noteNotFound)
  }

  @Test func aVaultNotChosenOrUnreadableSaysSo() async throws {
    let note = OpenTarget.note(Self.noteIDs["Notes/Plan.md"]!)
    #expect(await open(note) == .vaultUnavailable(.notChosen))
    let vault = try Vault()
    let fake = VaultFolderTests.FakeBookmarks()
    let folder = VaultFolder(settings: CountingSettings("live"), bookmarks: fake.bookmarks)
    try folder.choose(vault.root)
    fake.fails = true
    #expect(await open(note, vault: folder) == .vaultUnavailable(.unreadable))
    fake.fails = false
    try FileManager.default.removeItem(at: vault.root.appending(path: ".obsidian"))
    #expect(await open(note, vault: folder) == .vaultUnavailable(.unreadable))
    #expect(recorder.opened.isEmpty)
  }

  // MARK: Demo and text

  @Test func inDemoNothingOpens() async throws {
    let vault = try Vault()
    let folder = try chosen(vault)
    for target in [
      OpenTarget.task(Self.taskID), .project(Self.projectID), .note(Self.noteIDs["Notes/Plan.md"]!),
    ] {
      #expect(await open(target, vault: folder, isDemo: true) == .demo)
    }
    #expect(recorder.opened.isEmpty)
  }

  /// An `obsidian://` link as note text would hold it, built from its items (the pre-push
  /// guard reads a literal one that names a file as a vault path).
  nonisolated static func obsidian(_ action: String, _ items: KeyValuePairs<String, String>)
    -> String
  {
    var parts = URLComponents()
    parts.scheme = "obsidian"
    parts.host = action
    parts.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
    return parts.string ?? ""
  }

  /// Each write parameter and each other action from text, and every other scheme: dropped in
  /// phase 1 (ADR-0015 `:60`, `:67`; owner, 2026-11-25).
  @Test(arguments: [
    obsidian("new", ["vault": "v", "name": "x"]),
    obsidian("open", ["vault": "v", "file": "f", "append": "x"]),
    obsidian("open", ["vault": "v", "file": "f", "prepend": "x"]),
    obsidian("open", ["vault": "v", "file": "f"]), obsidian("daily", ["vault": "v"]),
    obsidian("unique", ["vault": "v"]), "omnifocus:///add?name=x",
    "omnifocus:///paste?target=inbox&content=x", "omnifocus:///task/abc", "https://example.com",
    "http://example.com", "moonshine://x", "file:///etc/hosts",
  ])
  func aLinkFromTextIsDropped(_ link: String) throws {
    let url = try #require(URL(string: link))
    let result = opener(vault: VaultFolder(settings: CountingSettings(nil))).openFromText(url)
    #expect(String(describing: result) == String(describing: OpenURLAction.Result.discarded))
    #expect(recorder.opened.isEmpty)
  }

  // MARK: The notice

  @Test func aNewNoticeCancelsTheOldTimer() async throws {
    let opener = opener(vault: VaultFolder(settings: CountingSettings(nil)))
    await opener.open(.task(Self.bareTaskID), in: Self.overview, isDemo: false)
    #expect(opener.notice == .notOpened)
    let first = opener.clearing
    try #require(await sleeper.waitFor(1))
    await opener.open(.task(Self.taskID), in: Self.overview, isDemo: true)
    #expect(opener.notice == .demo)
    let second = opener.clearing
    try #require(await sleeper.waitFor(2))
    sleeper.release(0)
    await first?.value
    #expect(opener.notice == .demo)
    sleeper.release(1)
    await second?.value
    #expect(opener.notice == nil)
  }

  @Test func anOpenedItemLeavesNoNotice() async {
    let opener = opener(vault: VaultFolder(settings: CountingSettings(nil)))
    await opener.open(.task(Self.taskID), in: Self.overview, isDemo: false)
    #expect(opener.notice == nil)
  }

  /// No notice names the item: no path, file or vault name, id or title (owner, 2026-11-25).
  @Test func theNoticeHoldsNothingOfTheItem() {
    let outcomes: [OpenOutcome] = [
      .noteNotFound, .vaultUnavailable(.notChosen), .vaultUnavailable(.unreadable), .notOpened,
      .demo,
    ]
    let words =
      Self.notePaths.flatMap { $0.split(separator: "/").map(String.init) }
      + ["aB3dE5fG7hJ", "kP9_q-2", "My Vault", "Invented", Self.taskID.description]
    for outcome in outcomes {
      let text = LinkOpener.text(outcome) ?? ""
      #expect(!text.isEmpty)
      for word in words where !word.isEmpty {
        #expect(!text.localizedCaseInsensitiveContains(word))
      }
    }
    #expect(LinkOpener.text(.opened) == nil)
  }
}
