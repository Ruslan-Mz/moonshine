import Testing

@testable import MoonShineCore

/// Invented note paths. Resolution follows ADR-0014 (owner, 2026-10-15).
@Suite struct WikiLinkTests {
  let paths = [
    "Years/Artifacts_2026.md", "Archive/Years/Plan.md", "Years/Plan.md", "BA/Name.md",
    "Notes/Whole life.MD", "Top.md", "Z/Top.md", "Old/Notes/Draft.md", "Планы/Год.md",
  ]

  /// The path a link resolves to, and whether it was ambiguous.
  func target(_ link: String, in paths: [String]? = nil) -> (String, Bool)? {
    let paths = paths ?? self.paths
    return WikiLink.target(of: link, in: paths).map { (paths[$0.index], $0.isAmbiguous) }
  }

  func expect(_ link: String, _ path: String, ambiguous: Bool = false, in paths: [String]? = nil) {
    let found = target(link, in: paths)
    #expect(found?.0 == path, "\(link)")
    #expect(found?.1 == ambiguous, "\(link)")
  }

  @Test func aNameMatchesAFileNameWithAnAliasOrAHeading() {
    for link in [
      "[[Artifacts_2026]]", "[[Artifacts_2026|This year]]", "[[Artifacts_2026#Q4]]",
      " [[ Artifacts_2026 ]] ", "Artifacts_2026", "[[Artifacts_2026.md]]",
    ] {
      expect(link, "Years/Artifacts_2026.md")
    }
    expect("[[Whole life]]", "Notes/Whole life.MD")
  }

  @Test func caseIsIgnoredInEveryScript() {
    expect("[[artifacts_2026]]", "Years/Artifacts_2026.md")
    expect("[[ARTIFACTS_2026.MD]]", "Years/Artifacts_2026.md")
    expect("[[год]]", "Планы/Год.md")
    expect("[[планы/ГОД]]", "Планы/Год.md")
    expect("[[years/plan]]", "Years/Plan.md", ambiguous: true)
  }

  @Test func aPathQualifiedLinkMatchesTheWholePathOrItsEnd() {
    expect("[[Years/Artifacts_2026]]", "Years/Artifacts_2026.md")
    expect("[[Years/Artifacts_2026.md|A]]", "Years/Artifacts_2026.md")
    expect("[[Archive/Years/Plan]]", "Archive/Years/Plan.md")
    // Only by the end of a path: no note is at `Notes/Draft`.
    expect("[[Notes/Draft]]", "Old/Notes/Draft.md")
    expect("[[Years/Plan]]", "Z/Years/Plan.md", in: ["Z/Years/Plan.md"])
  }

  @Test func ofSeveralCandidatesTheShortestPathWinsAndTheLinkIsAmbiguous() {
    // `Years/Plan` is a whole path and the end of `Archive/Years/Plan`: the shorter wins.
    expect("[[Years/Plan]]", "Years/Plan.md", ambiguous: true)
    expect("[[Plan]]", "Years/Plan.md", ambiguous: true)
    // A note at the root is the shortest path for its name.
    expect("[[Top]]", "Top.md", ambiguous: true)
    expect("[[Plan]]", "Plan.md", ambiguous: true, in: ["A/Plan.md", "Plan.md"])
    // Paths of one length: the first by path.
    expect("[[Plan]]", "A/Plan.md", ambiguous: true, in: ["B/Plan.md", "A/Plan.md"])
  }

  @Test func aFolderMatchesOnlyAtASlash() {
    #expect(target("[[A/Name]]") == nil)
    expect("[[BA/Name]]", "BA/Name.md")
    #expect(target("[[ears/Plan]]") == nil)
    expect("[[Name]]", "BA/Name.md")
  }

  @Test func aLinkFromTheVaultRootMatchesTheWholePathOnly() {
    expect("[[/Years/Plan]]", "Years/Plan.md")
    #expect(target("[[/Plan]]") == nil)
    expect("[[/top]]", "Top.md")
  }

  @Test func anEmptyOrUnknownLinkResolvesToNothing() {
    for link in ["", "[[]]", "[[#Heading]]", "[[|Alias]]", "[[Missing]]", "[[/]]", "[[.md]]"] {
      #expect(target(link) == nil, "\(link)")
    }
  }
}
