import Testing

@testable import MoonShineCore

/// Invented note paths.
@Suite struct WikiLinkTests {
  let paths = [
    "Years/Artifacts_2026.md", "Archive/Years/Plan.md", "Years/Plan.md", "BA/Name.md",
    "Notes/Whole life.MD", "Top.md",
  ]

  func target(_ link: String) -> String? {
    WikiLink.target(of: link, in: paths).map { paths[$0] }
  }

  @Test func aNameMatchesAFileNameWithAnAliasOrAHeading() {
    for link in [
      "[[Artifacts_2026]]", "[[Artifacts_2026|This year]]", "[[Artifacts_2026#Q4]]",
      " [[ Artifacts_2026 ]] ", "Artifacts_2026", "[[Artifacts_2026.md]]",
    ] {
      #expect(target(link) == "Years/Artifacts_2026.md", "\(link)")
    }
    #expect(target("[[Whole life]]") == "Notes/Whole life.MD")
  }

  @Test func aPathQualifiedLinkMatchesTheWholePathOrItsEnd() {
    #expect(target("[[Years/Artifacts_2026]]") == "Years/Artifacts_2026.md")
    #expect(target("[[Years/Artifacts_2026.md|A]]") == "Years/Artifacts_2026.md")
    // `Archive/Years/Plan` ends with `/Years/Plan` and comes first by path, but a whole
    // path wins over the end of one.
    #expect(target("[[Years/Plan]]") == "Years/Plan.md")
    #expect(target("[[Archive/Years/Plan]]") == "Archive/Years/Plan.md")
    #expect(target("[[Notes/Whole life]]") == "Notes/Whole life.MD")
    // Only by its folder: no note is at `Archive/Plan` or `Years/Artifacts_2026` alone.
    #expect(target("[[Years/Artifacts_2026]]") == "Years/Artifacts_2026.md")
    #expect(WikiLink.target(of: "[[Years/Plan]]", in: ["Z/Years/Plan.md"]) == 0)
  }

  @Test func aNameSharedByTwoFoldersTakesTheFirstByPath() {
    #expect(target("[[Plan]]") == "Archive/Years/Plan.md")
    let reversed = Array(paths.reversed())
    #expect(
      WikiLink.target(of: "[[Plan]]", in: reversed).map { reversed[$0] } == "Archive/Years/Plan.md")
  }

  @Test func aFolderMatchesOnlyAtASlash() {
    #expect(target("[[A/Name]]") == nil)
    #expect(target("[[BA/Name]]") == "BA/Name.md")
    #expect(target("[[ears/Plan]]") == nil)
    #expect(target("[[Name]]") == "BA/Name.md")
  }

  @Test func aLinkFromTheVaultRootMatchesTheWholePathOnly() {
    #expect(target("[[/Years/Plan]]") == "Years/Plan.md")
    #expect(target("[[/Plan]]") == nil)
    #expect(target("[[/Top]]") == "Top.md")
  }

  @Test func anEmptyOrUnknownLinkResolvesToNothing() {
    for link in ["", "[[]]", "[[#Heading]]", "[[|Alias]]", "[[Missing]]", "[[/]]", "[[.md]]"] {
      #expect(target(link) == nil, "\(link)")
    }
  }
}
