import Foundation
import MoonShineCore
import Testing

@testable import ObsidianAdapter

/// `mapping.yaml` in the data folder (S4-4c-2): only `meta_tag_groups`, a list of names. A
/// missing file means no groups; anything else that is not a valid file is a problem, never an
/// empty list. Every name here is invented.
@Suite struct MappingFileTests {
  let folder: URL

  init() throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "mapping-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func write(_ text: String) throws {
    try Data(text.utf8).write(to: folder.appending(path: MappingFile.name))
  }

  func read() throws(MappingFileError) -> MappingFile.Read {
    try MappingFile.read(folder: folder)
  }

  @Test func aMappingFileReadsItsGroups() throws {
    try write("# the owner's groups\nmeta_tag_groups:\n  - Effort\n  - \"Work kind\"\n")
    #expect(try read() == .groups(["Effort", "Work kind"]))
  }

  @Test func aFlowListReadsToo() throws {
    try write("meta_tag_groups: [Effort, Setting]\n")
    #expect(try read() == .groups(["Effort", "Setting"]))
  }

  @Test func aMissingMappingFileMeansNoGroups() throws {
    #expect(try read() == .missing)
  }

  @Test func anEmptyListMeansNoGroups() throws {
    try write("meta_tag_groups: []\n")
    #expect(try read() == .groups([]))
  }

  @Test func twentyNamesAreAllowed() throws {
    try write("meta_tag_groups:\n" + (1...20).map { "  - Group \($0)\n" }.joined())
    #expect(try read() == .groups(Set((1...20).map { "Group \($0)" })))
  }

  @Test func aNameOfOneHundredTwentyCharactersIsAllowed() throws {
    let name = String(repeating: "x", count: 120)
    try write("meta_tag_groups: [\(name)]\n")
    #expect(try read() == .groups([name]))
  }

  static let invalid: [(String, VaultProblem.Kind, MappingFileError.Key)] = [
    ("%YAML 1.2\n---\nmeta_tag_groups: [Effort]\n", .yamlDirective, .root),
    ("meta_tag_groups: &a [Effort]\nother: *a\n", .yamlAnchor, .root),
    ("meta_tag_groups: " + String(repeating: "[", count: 40) + "\n", .yamlTooComplex, .root),
    ("meta_tag_groups: [Effort\n", .malformedYAML, .root),
    ("- Effort\n", .malformedYAML, .root),
    ("", .invalidValue, .root),
    ("# only a comment\n", .invalidValue, .root),
    ("Effort:\n  - Low\n", .invalidValue, .root),
    ("meta_tag_groups: [Effort]\nlines: []\n", .invalidValue, .root),
    ("meta_tag_groups:\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups: Effort\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  Effort: Low\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  - [Effort]\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  - {name: Effort}\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  - \"\"\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  - ~\n", .invalidValue, .metaTagGroups),
    (
      "meta_tag_groups:\n  - " + String(repeating: "x", count: 121) + "\n", .invalidValue,
      .metaTagGroups
    ),
    // 120 characters, each a letter with four combining marks: 1,080 bytes, over 1 KiB.
    (
      "meta_tag_groups:\n  - \"" + String(repeating: "e\u{301}\u{301}\u{301}\u{301}", count: 120)
        + "\"\n", .invalidValue, .metaTagGroups
    ),
    ("meta_tag_groups:\n  - \"Eff\\tort\"\n", .invalidValue, .metaTagGroups),
    ("meta_tag_groups:\n  - \"Eff\\x7Fort\"\n", .invalidValue, .metaTagGroups),
    (
      "meta_tag_groups:\n" + (1...21).map { "  - Group \($0)\n" }.joined(), .invalidValue,
      .metaTagGroups
    ),
    ("meta_tag_groups: [Effort, Setting, Effort]\n", .invalidValue, .metaTagGroups),
  ]

  @Test(arguments: invalid.indices)
  func eachInvalidFileIsAProblemWithItsKindAndKey(_ index: Int) throws {
    let (text, kind, key) = Self.invalid[index]
    try write(text)
    #expect(throws: MappingFileError.invalid(kind, key: key)) { try read() }
  }

  @Test func aFileOverSixtyFourKiBIsTooLarge() throws {
    try write("meta_tag_groups: [Effort]\n# " + String(repeating: "x", count: 64 * 1024) + "\n")
    #expect(throws: MappingFileError.invalid(.frontmatterTooLarge, key: .root)) { try read() }
  }

  @Test func aFileThatIsNotUTF8IsAProblem() throws {
    try Data([0x6D, 0x3A, 0x20, 0xFF, 0xFE, 0x0A]).write(
      to: folder.appending(path: MappingFile.name))
    #expect(throws: MappingFileError.invalid(.notUTF8, key: .root)) { try read() }
  }

  @Test func aFolderAtThePathIsUnreadable() throws {
    try FileManager.default.createDirectory(
      at: folder.appending(path: MappingFile.name), withIntermediateDirectories: false)
    #expect(throws: MappingFileError.unreadable) { try read() }
  }

  /// A link is never followed, dangling or not: `fileExists` would call a dangling one missing.
  @Test func aLinkAtThePathIsUnreadable() throws {
    let target = folder.appending(path: "elsewhere.yaml")
    try FileManager.default.createSymbolicLink(
      at: folder.appending(path: MappingFile.name), withDestinationURL: target)
    #expect(throws: MappingFileError.unreadable) { try read() }
    try Data("meta_tag_groups: [Effort]\n".utf8).write(to: target)
    #expect(throws: MappingFileError.unreadable) { try read() }
  }

  /// The owner's group names are his labels: an error names a kind and a fixed key only, even
  /// when a name stands where a key belongs.
  @Test func noErrorNamesAValue() throws {
    for text in [
      "Secretgroup:\n  - Low\n", "meta_tag_groups: [Secretgroup, Secretgroup]\n",
      "Secretgroup: 1\nmeta_tag_groups: []\n",
    ] {
      try write(text)
      do {
        _ = try read()
        Issue.record("read a file it should refuse")
      } catch {
        #expect(!String(describing: error).contains("Secretgroup"))
        #expect(!String(reflecting: error).contains("Secretgroup"))
      }
    }
  }

  @Test func everyProblemIsTheMappingFailureKind() {
    for error in [
      MappingFileError.unreadable, .invalid(.malformedYAML, key: .root),
      .invalid(.invalidValue, key: .metaTagGroups),
    ] {
      #expect(error.importFailure == .mappingInvalid)
    }
  }
}
