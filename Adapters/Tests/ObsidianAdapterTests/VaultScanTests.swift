import Foundation
import MoonShineCore
import Testing

@testable import ObsidianAdapter

/// `fixtures/vault/` at the repository root (synthetic data).
let fixtureVault = URL(filePath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appending(path: "fixtures/vault")

/// The zone of `DemoVault`.
let moscow = TimeZone(identifier: "Europe/Moscow")!

/// A throwaway vault in the temporary directory; every note in it is invented.
struct TemporaryVault {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "vault-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  @discardableResult
  func write(_ path: String, _ text: String) throws -> URL {
    try write(path, Data(text.utf8))
  }

  @discardableResult
  func write(_ path: String, _ data: Data) throws -> URL {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }

  func link(_ path: String, to target: URL) throws {
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: path), withDestinationURL: target)
  }
}

func note(_ yaml: String) -> String { "---\n\(yaml)\n---\n\n# Body\n" }

func problems(_ issues: [ImportIssue]) -> [String] {
  issues.map { issue in
    guard case .vault(let path, let line, let problem) = issue else { return "\(issue)" }
    return "\(path):\(line.map(String.init) ?? "-"):\(problem)"
  }
}

@Suite struct VaultWalkTests {
  @Test func findsMarkdownNotesInPathOrderAndSkipsHiddenFolders() throws {
    let vault = try TemporaryVault()
    try vault.write("b.md", note("type: x"))
    try vault.write("A/c.md", note("type: x"))
    try vault.write("A/image.png", "not a note")
    try vault.write(".obsidian/workspace.md", note("type: x"))
    let (files, issues, _) = try VaultWalk.markdownFiles(in: vault.root, limits: VaultLimits())
    #expect(files.map(\.path) == ["A/c.md", "b.md"])
    #expect(issues.isEmpty)
  }

  @Test func skipsSymbolicLinksToFilesAndFolders() throws {
    let vault = try TemporaryVault()
    let outside = try TemporaryVault()
    let secret = try outside.write("secret.md", note("type: x"))
    try vault.write("a.md", note("type: x"))
    try vault.link("linked.md", to: secret)
    try vault.link("Linked folder", to: outside.root)
    let (files, issues, _) = try VaultWalk.markdownFiles(in: vault.root, limits: VaultLimits())
    #expect(files.map(\.path) == ["a.md"])
    #expect(
      problems(issues).sorted() == ["Linked folder:-:symlinkSkipped", "linked.md:-:symlinkSkipped"])
  }

  @Test func aResolvedPathOutsideTheRootIsNotInsideTheVault() {
    let root = URL(filePath: "/Vault", directoryHint: .isDirectory)
    #expect(VaultWalk.relativePath(of: URL(filePath: "/Vault/A/b.md"), under: root) == "A/b.md")
    #expect(VaultWalk.relativePath(of: URL(filePath: "/Vault/../etc/b.md"), under: root) == nil)
    #expect(VaultWalk.relativePath(of: URL(filePath: "/Vault2/b.md"), under: root) == nil)
    #expect(VaultWalk.relativePath(of: URL(filePath: "/etc/b.md"), under: root) == nil)
  }

  @Test func tooManyNotesStopsTheRead() throws {
    let vault = try TemporaryVault()
    for name in ["a", "b", "c"] { try vault.write("\(name).md", note("type: x")) }
    var limits = VaultLimits()
    limits.maxNotes = 2
    #expect(throws: VaultReadError.tooManyNotes(limit: 2)) {
      try VaultWalk.markdownFiles(in: vault.root, limits: limits)
    }
  }

  @Test func anUnreadableFolderIsAnIssueAndTheRestStillLoads() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    try vault.write("Locked/b.md", note("type: x"))
    let locked = vault.root.appending(path: "Locked").path
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked)
    }
    let (files, issues, _) = try VaultWalk.markdownFiles(in: vault.root, limits: VaultLimits())
    #expect(files.map(\.path) == ["a.md"])
    #expect(problems(issues) == ["Locked:-:unreadable"])
  }

  @Test func aRootThatExistsButCannotBeListedIsUnreadable() throws {
    let vault = try TemporaryVault()
    try vault.write("a.md", note("type: x"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.root.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: vault.root.path)
    }
    #expect(throws: VaultReadError.rootUnreadable) {
      try VaultWalk.markdownFiles(in: vault.root, limits: VaultLimits())
    }
  }

  @Test func aRootThatIsAFileIsUnreadable() throws {
    let vault = try TemporaryVault()
    let file = try vault.write("a.md", note("type: x"))
    #expect(throws: VaultReadError.rootUnreadable) {
      try VaultWalk.markdownFiles(in: file, limits: VaultLimits())
    }
  }

  @Test func aMissingRootIsUnreadable() {
    let missing = FileManager.default.temporaryDirectory.appending(path: "no-vault-\(UUID())")
    #expect(throws: VaultReadError.rootUnreadable) {
      try VaultWalk.markdownFiles(in: missing, limits: VaultLimits())
    }
  }
}

@Suite struct FrontmatterTests {
  func extract(_ text: String, atEnd: Bool = true, limit: Int = 1024) throws(FrontmatterFailure)
    -> String?
  {
    try Frontmatter.extract(from: Array(text.utf8), atEnd: atEnd, limit: limit)
  }

  @Test func returnsTheTextBetweenTheDelimiters() throws {
    #expect(try extract("---\na: 1\nb: 2\n---\nbody") == "a: 1\nb: 2\n")
    #expect(try extract("---\r\na: 1\r\n---\r\n") == "a: 1\r\n")
    #expect(try extract("---\na: 1\n---") == "a: 1\n")
    #expect(try extract("---\n---\n") == "")
  }

  @Test func aNoteWithoutFrontmatterHasNone() throws {
    #expect(try extract("# Title\n---\na: 1\n---\n") == nil)
    #expect(try extract("") == nil)
  }

  @Test func frontmatterOverTheCapIsTooLarge() {
    let text = "---\nkey: \(String(repeating: "x", count: 100))\n---\n"
    #expect(throws: FrontmatterFailure(kind: .frontmatterTooLarge, line: nil)) {
      try extract(text, limit: 64)
    }
    #expect(throws: FrontmatterFailure(kind: .frontmatterTooLarge, line: nil)) {
      try extract(String(text.prefix(72)), atEnd: false, limit: 64)
    }
  }

  @Test func frontmatterThatNeverClosesIsMalformed() {
    #expect(throws: FrontmatterFailure(kind: .malformedYAML, line: 1)) {
      try extract("---\na: 1\nbody\n")
    }
  }

  @Test func frontmatterThatIsNotUTF8IsRejected() {
    let bytes: [UInt8] = Array("---\na: ".utf8) + [0xFF, 0xFE] + Array("\n---\n".utf8)
    #expect(throws: FrontmatterFailure(kind: .notUTF8, line: nil)) {
      try Frontmatter.extract(from: bytes, atEnd: true, limit: 1024)
    }
  }

  @Test func aNoteReadFromDiskKeepsFrontmatterOfExactlyTheCapAndRejectsOneByteMore() throws {
    let vault = try TemporaryVault()
    let limit = 64
    let atCap = String(repeating: "x", count: limit - 1) + "\n"
    let fits = try vault.write("fits.md", "---\n\(atCap)---\nbody\n")
    let over = try vault.write("over.md", "---\nx\(atCap)---\nbody\n")
    #expect(try Frontmatter.text(of: fits, limit: limit) == atCap)
    #expect(throws: FrontmatterFailure(kind: .frontmatterTooLarge, line: nil)) {
      try Frontmatter.text(of: over, limit: limit)
    }
  }

  @Test func aNoteThatCannotBeOpenedIsUnreadable() throws {
    let vault = try TemporaryVault()
    let url = try vault.write("locked.md", note("type: x"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }
    #expect(throws: FrontmatterFailure(kind: .unreadable, line: nil)) {
      try Frontmatter.text(of: url, limit: 1024)
    }
  }
}

@Suite struct FrontNodeTests {
  func parse(_ yaml: String, limits: VaultLimits = VaultLimits()) throws(FrontmatterFailure)
    -> FrontNode
  {
    try FrontNode.parse(yaml, limits: limits)
  }

  @Test func keepsScalarsRawAndTellsNullFromTheStringNull() throws {
    let root = try parse("a: 2026-10-01\nb: \"null\"\nc: null\nd:\ne: [x, 1.5]\n")
    let expected = FrontNode(
      value: .mapping([
        .init(key: "a", node: FrontNode(value: .scalar("2026-10-01"), line: 2)),
        .init(key: "b", node: FrontNode(value: .scalar("null"), line: 3)),
        .init(key: "c", node: FrontNode(value: .null, line: 4)),
        .init(key: "d", node: FrontNode(value: .null, line: 5)),
        .init(
          key: "e",
          node: FrontNode(
            value: .sequence([
              FrontNode(value: .scalar("x"), line: 6), FrontNode(value: .scalar("1.5"), line: 6),
            ]), line: 6)),
      ]), line: 2)
    #expect(root == expected)
  }

  @Test func invalidYAMLIsMalformedWithItsLineInTheNote() {
    #expect(throws: FrontmatterFailure(kind: .malformedYAML, line: 4)) {
      try parse("a: 1\nb: 2\n  c: 3\n")
    }
  }

  @Test func aRootThatIsNotAMappingIsMalformed() {
    #expect(throws: FrontmatterFailure(kind: .malformedYAML, line: nil)) {
      try parse("- a\n- b\n")
    }
  }

  @Test func deepFlowNestingIsRejectedBeforeParsing() {
    let yaml = "a: " + String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
    #expect(throws: FrontmatterFailure(kind: .yamlTooComplex, line: nil)) { try parse(yaml) }
  }

  @Test func deepBlockNestingIsRejected() {
    let yaml =
      (0..<40).map { String(repeating: "  ", count: $0) + "k\($0):" }.joined(separator: "\n")
      + " leaf\n"
    #expect(throws: FrontmatterFailure(kind: .yamlTooComplex, line: nil)) { try parse(yaml) }
  }

  /// An alias bomb: each level is ten aliases of the one below, 10^9 scalars at the top.
  func aliasBomb(levels: Int) -> [String] {
    var lines = ["a0: &a0 [x, x, x, x, x, x, x, x, x, x]"]
    for level in 1...levels {
      let previous = Array(repeating: "*a\(level - 1)", count: 10).joined(separator: ", ")
      lines.append("a\(level): &a\(level) [\(previous)]")
    }
    return lines
  }

  @Test func anAliasBombInValuesIsRejectedBeforeParsing() {
    #expect(throws: FrontmatterFailure(kind: .yamlAnchor, line: nil)) {
      try parse(aliasBomb(levels: 8).joined(separator: "\n"))
    }
  }

  /// Yams hashes mapping keys while composing, so an alias in key position would expand there.
  @Test(.timeLimit(.minutes(1))) func anAliasBombInKeyPositionIsRejectedBeforeParsing() {
    for key in ["*a8 : v", "? *a8\n: v", "b: {*a8 : v}", "b: [*a8 : v]"] {
      #expect(throws: FrontmatterFailure(kind: .yamlAnchor, line: nil)) {
        try parse((aliasBomb(levels: 8) + [key]).joined(separator: "\n"))
      }
    }
  }

  @Test func everyAnchorFormWithAnAliasIsRejected() {
    for yaml in [
      "a: &x 1", "a: [&x 1]", "a: {b: &x 1}", "- &x a", "a:\n  - &x 1", "a: !!str &x 1",
      "a: \"q\" \n&x b: 1",
    ] {
      #expect(throws: FrontmatterFailure(kind: .yamlAnchor, line: nil), "\(yaml)") {
        try parse(yaml + "\nz: *x")
      }
    }
  }

  @Test(arguments: [
    "R&D, Q&A and AT&T",
    "Музыка&танец",
    "音楽&舞踊",
    "מוזיקה&ריקוד",
    "Ж&Д and 2&3",
    "कि&ख",
    "x & y",
  ])
  func anAmpersandAfterALetterDigitOrMarkInAnyScriptIsPlainText(title: String) throws {
    let root = try parse("title: \(title)")
    #expect(
      root.value == .mapping([.init(key: "title", node: FrontNode(value: .scalar(title), line: 2))])
    )
  }

  @Test(arguments: ["a: Музыка &танец", "a: 音楽 &x 1", "a: [&מ 1]", "a: (&x)"])
  func anAmpersandAfterSpaceOrPunctuationIsStillAnAnchor(yaml: String) {
    #expect(FrontNode.hasAnchor(yaml))
    #expect(throws: FrontmatterFailure(kind: .yamlAnchor, line: nil)) { try parse(yaml + " *x") }
  }

  @Test func theNodeCapBoundsALongDocument() {
    var limits = VaultLimits()
    limits.maxNodes = 5
    #expect(throws: FrontmatterFailure(kind: .yamlTooComplex, line: nil)) {
      try parse("a: [1, 2, 3, 4, 5, 6]", limits: limits)
    }
  }
}

@Suite struct VaultScanTests {
  @Test func readsEveryFixtureNoteWithoutIssues() throws {
    let scan = try VaultScan.notes(in: fixtureVault)
    let (notes, issues) = (scan.notes, scan.issues)
    #expect(notes.count == 6)
    #expect(notes.first?.path == "00_Strategy/Hours_budget_by_line.md")
    #expect(issues.isEmpty)
  }

  @Test func aBadNoteBecomesAnIssueWithItsPathAndTheRestStillLoads() throws {
    let vault = try TemporaryVault()
    try vault.write("good.md", note("type: x"))
    try vault.write("plain.md", "# No frontmatter\n")
    try vault.write("Bad/broken.md", note("a: [unclosed"))
    let scan = try VaultScan.notes(in: vault.root)
    let (notes, issues) = (scan.notes, scan.issues)
    #expect(notes.map(\.path) == ["good.md"])
    #expect(problems(issues) == ["Bad/broken.md:3:malformedYAML"])
  }

  @Test func noteContentNeverReachesAnIssue() throws {
    let vault = try TemporaryVault()
    let secret = "planted-secret-title"
    try vault.write("a.md", note("title: \(secret)\n  bad: [\(secret)"))
    try vault.write("b.md", "---\ntitle: \(secret)\n")
    try vault.write(
      "c.md", Data("---\ntitle: \(secret) ".utf8) + Data([0xFF]) + Data("\n---\n".utf8))
    let issues = try VaultScan.notes(in: vault.root).issues
    #expect(issues.count == 3)
    #expect(!"\(issues)".contains(secret))
  }
}
