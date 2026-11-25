import Foundation
import Testing

@testable import MoonShineCore

/// The URLs the link opener builds (ADR-0015, amendments of 2026-10-12 and 2026-10-21), on
/// invented ids and paths.
@Suite struct OpenLinksTests {
  // MARK: OmniFocus

  @Test func aTaskAndAProjectGetExactlyTheirURLs() {
    #expect(OmniFocusLink.task("aB3dE5fG7hJ")?.absoluteString == "omnifocus:///task/aB3dE5fG7hJ")
    #expect(OmniFocusLink.project("kP9_q-2")?.absoluteString == "omnifocus:///project/kP9_q-2")
  }

  @Test func anOccurrenceIdOpens() {
    #expect(OmniFocusLink.isOpenableID("aB3dE5fG7hJ.3"))
    #expect(
      OmniFocusLink.task("aB3dE5fG7hJ.3")?.absoluteString == "omnifocus:///task/aB3dE5fG7hJ.3")
    #expect(OmniFocusLink.isOpenableID("a.123456"))
  }

  /// A path, a query, a fragment, an escape, a line break or a character outside the alphabet.
  @Test(arguments: [
    "a/b", "a?b", "a#b", "a%2Fb", "a b", "ä", "", String(repeating: "a", count: 65), "a.b",
    "a.1234567", "a.", ".1", "../task", "x?name=y", "aB3\n", "aB3\r", "aB3\u{00A0}",
    "\u{FF11}\u{FF12}", "a\u{0000}", "a.1.2",
  ])
  func anIdOutsideTheAlphabetOpensNothing(_ id: String) {
    #expect(!OmniFocusLink.isOpenableID(id))
    #expect(OmniFocusLink.task(id) == nil)
    #expect(OmniFocusLink.project(id) == nil)
  }

  @Test func sixtyFourCharactersIsTheLongestId() {
    let id = String(repeating: "Z", count: 64)
    #expect(OmniFocusLink.isOpenableID(id))
    #expect(OmniFocusLink.task(id)?.absoluteString == "omnifocus:///task/" + id)
  }

  // MARK: Obsidian

  private func items(_ url: URL?) -> [URLQueryItem]? {
    url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
  }

  @Test func aNoteGetsOnlyVaultAndFile() throws {
    let url = try #require(ObsidianLink.open(vault: "My Vault", file: "Notes/A & B+C #1?.md"))
    let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(parts.scheme == "obsidian")
    #expect(parts.host == "open")
    #expect(parts.path == "")
    #expect(parts.fragment == nil)
    #expect(
      parts.queryItems == [
        URLQueryItem(name: "vault", value: "My Vault"),
        URLQueryItem(name: "file", value: "Notes/A & B+C #1?.md"),
      ])
    // Every reserved character is escaped, so no `&`, `=` or `#` splits the query.
    let query = try #require(parts.percentEncodedQuery)
    #expect(query == "vault=My%20Vault&file=Notes%2FA%20%26%20B%2BC%20%231%3F.md")
  }

  /// A write parameter inside a file name stays inside `file` (ADR-0015 `:55`).
  @Test(arguments: ["a&append=x.md", "a&prepend=x.md", "a&paneType=tab.md", "a=b.md", "%41.md"])
  func aParameterInAFileNameStaysInsideFile(_ file: String) {
    #expect(
      items(ObsidianLink.open(vault: "v", file: file))
        == [URLQueryItem(name: "vault", value: "v"), URLQueryItem(name: "file", value: file)])
  }

  @Test(arguments: [
    ("", "a.md"), ("v", ""), ("v", "a\nb.md"), ("v", "a\u{0007}.md"), ("v", "a\u{007F}.md"),
    ("v", "a\u{2028}.md"), ("v\u{2029}", "a.md"), ("v", String(repeating: "é", count: 513)),
  ])
  func anEmptyControlOrOverlongValueOpensNothing(_ vault: String, _ file: String) {
    #expect(ObsidianLink.open(vault: vault, file: file) == nil)
  }

  @Test func aThousandAndTwentyFourBytesStillOpen() {
    #expect(ObsidianLink.open(vault: "v", file: String(repeating: "a", count: 1024)) != nil)
    #expect(ObsidianLink.open(vault: "v", file: String(repeating: "a", count: 1025)) == nil)
  }
}
