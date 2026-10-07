import Foundation
import MoonShineCore
import Testing
import Yams

@testable import ObsidianAdapter

/// The pre-parse guards for untrusted YAML: an anchor is rejected only with an alias, and a
/// directive always is. Every document here is invented.
@Suite struct YAMLGuardsTests {
  func parse(_ yaml: String) throws(FrontmatterFailure) -> FrontNode {
    try FrontNode.parse(yaml, limits: VaultLimits())
  }

  // MARK: Anchors need an alias

  @Test func aQuotedListItemStartingWithAnAmpersandIsReadAsText() throws {
    let root = try parse("tags:\n  - \"&x and y\"\n  - b")
    #expect(
      root["tags"]?.value
        == .sequence([
          FrontNode(value: .scalar("&x and y"), line: 3), FrontNode(value: .scalar("b"), line: 4),
        ]))
  }

  @Test func anAnchorWithoutAnAliasIsAcceptedAndOnlyLabelsItsNode() throws {
    let root = try parse("a: &x 1\nb: 2 * 3")
    #expect(root["a"]?.scalar == "1")
    #expect(root["b"]?.scalar == "2 * 3")
  }

  @Test(arguments: [
    "a: &x 1\nb: *x", "a: [&x 1, *x]", "a: {b: &x 1, c: *x}", "a: &x 1\nb: \"*x\"",
    "- &x a\n- *x", "a: &x 1\n*x : v",
  ])
  func anAnchorWithAnAliasIsRejected(yaml: String) {
    #expect(throws: FrontmatterFailure(kind: .yamlAnchor, line: nil)) { try parse(yaml) }
  }

  @Test func anAliasWithoutAnAnchorIsMalformed() {
    #expect(throws: FrontmatterFailure(kind: .malformedYAML, line: 3)) { try parse("a: 1\nb: *x") }
  }

  @Test(arguments: ["a *", "a * b", "a *\tb", "a *\nb", "a *\rb", "a *\u{85}b", "a *\u{2028}b"])
  func anAsteriskBeforeABlankOrALineBreakIsNoAlias(text: String) {
    #expect(!FrontNode.hasAlias(text))
  }

  @Test(arguments: ["*x", "a *x", "\"*x\"", "**bold**", "[*x]"])
  func anAsteriskBeforeANonBlankIsAnAliasCandidate(text: String) {
    #expect(FrontNode.hasAlias(text))
  }

  // MARK: Directives

  @Test(arguments: [
    "%YAML 1.1\n---\na: 1", "a: 1\n%TAG !e! tag:x,2026:\n", "a: 1\r%x", "a: 1\u{85}%x",
    "a: 1\u{2028}%x", "a: 1\u{2029}%x", "a: 1\r\n%x", "\u{FEFF}%TAG !e! tag:x,2026:\n",
  ])
  func aPercentAtTheStartOrAfterAnyLineBreakIsADirective(yaml: String) {
    #expect(throws: FrontmatterFailure(kind: .yamlDirective, line: nil)) { try parse(yaml) }
  }

  /// A false positive, accepted: libyaml reads this `%` as text inside the quoted scalar.
  @Test func aPercentStartingAQuotedContinuationLineIsRejectedToo() {
    #expect(throws: FrontmatterFailure(kind: .yamlDirective, line: nil)) {
      try parse("a: \"one\n%two\"")
    }
  }

  @Test func aPercentInsideALineIsText() throws {
    let root = try parse("a: 50%\nb: \"%x\"\nc: x %y")
    #expect(root["a"]?.scalar == "50%")
    #expect(root["b"]?.scalar == "%x")
    #expect(root["c"]?.scalar == "x %y")
  }

  // MARK: Yams' behaviour, pinned

  @Test func yamsCopiesATagPrefixIntoEveryTagThatUsesIt() throws {
    let prefix = "tag:" + String(repeating: "p", count: 1_000) + ":"
    let yaml = "%TAG !e! \(prefix)\n---\n[!e!a 1, !e!b 2, !e!c 3]"
    let tags = try #require(try Yams.compose(yaml: yaml)?.sequence).map(\.tag.rawValue)
    #expect(tags.count == 3)
    #expect(tags.allSatisfy { $0.count > prefix.count })
  }

  @Test func yamsReportsAnAnchorWithoutAnAliasAndKeepsTheValue() throws {
    let parser = try Parser(yaml: "a: &x 1")
    let root = try #require(try parser.singleRoot())
    withExtendedLifetime(parser) {
      #expect(root["a"]?.anchor?.rawValue == "x")
      #expect(root["a"]?.string == "1")
    }
  }

  @Test func yamsRejectsAnUndefinedAlias() {
    #expect(throws: YamlError.self) { try Yams.compose(yaml: "a: *x") }
  }

  // MARK: Line breaks

  /// `Frontmatter` ends the frontmatter only at a `---` line after LF; a `---` after any other
  /// line break libyaml knows starts a second document, which fails safe as `malformedYAML`.
  @Test(arguments: ["\r", "\u{85}", "\u{2028}", "\u{2029}"])
  func aDelimiterAfterAnotherLineBreakEndsAsMalformed(lineBreak: String) throws {
    let vault = try TemporaryVault()
    try vault.write("open.md", "---\na: 1\(lineBreak)---\(lineBreak)# Body\n")
    try vault.write("later.md", "---\na: 1\(lineBreak)---\(lineBreak)b: 2\n---\n# Body\n")
    let scan = try VaultScan.notes(in: vault.root)
    #expect(scan.notes.isEmpty)
    #expect(
      scan.noteIssues.map { issue -> VaultProblem.Kind? in
        guard case .vault(_, _, let problem) = issue else { return nil }
        return problem.kind
      } == [.malformedYAML, .malformedYAML])
  }

  // MARK: Differential test against Yams

  /// SplitMix64: a fixed seed gives the same documents on every run.
  struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// A prefix longer than the default one, so a directive that slips through shows in tags.
  static let tagDirective = "%TAG !e! tag:x,2026:" + String(repeating: "p", count: 200) + "\n---\n"

  static let taggedHead = tagDirective + "- !e!a 1\n- !e!a 2\n- !e!a 3\n- "

  static let pieces = [
    "a", "b1", "Ж", "音", "R&D", " ", "  ", "\t", "\n", "\n  ", "\r", "\u{85}", "\u{2028}",
    "\u{FEFF}", ":", ": ", "- ", "? ", ",", "[", "]", "{", "}", "\"", "'", "#", "|", ">", "&",
    "&a", "*", "*a", "!", "!!", "!e!", "!e!a ", "%", Self.tagDirective, "%YAML 1.1\n---\n",
    "@", "-",
  ]

  /// Yams' default tag prefix: `!!x` becomes `tag:yaml.org,2002:x` without any directive.
  static let defaultTagPrefix = "tag:yaml.org,2002:"

  /// Tags Yams' resolver fills in by itself: fixed names, whatever the document says.
  static let coreTags: Set<String> = Set(
    [Tag.Name.str, .seq, .map, .bool, .float, .null, .int, .binary, .merge, .timestamp, .value]
      .map(\.rawValue))

  /// The node's tag ("" when there is none). Read from the stored tag, so reading it never
  /// resolves an implicit tag in place.
  func storedTag(_ node: Node) -> String {
    switch node {
    case .scalar(let scalar): scalar.tag.description
    case .sequence(let sequence): sequence.tag.description
    case .mapping(let mapping): mapping.tag.description
    case .alias(let alias): alias.tag.description
    }
  }

  /// Nodes of `node` with aliases expanded, counted up to `cap + 1`.
  func nodes(_ node: Node, cap: Int, into found: inout [Node]) {
    guard found.count <= cap else { return }
    found.append(node)
    switch node {
    case .scalar, .alias: break
    case .sequence(let sequence): for item in sequence { nodes(item, cap: cap, into: &found) }
    case .mapping(let mapping):
      for (key, value) in mapping {
        nodes(key, cap: cap, into: &found)
        nodes(value, cap: cap, into: &found)
      }
    }
  }

  @Test func randomDocumentsNeverSlipAnAnchorADirectiveOrAnExpansionPastTheGuards() {
    var generator = SeededGenerator(state: 20_261_007)
    let limits = VaultLimits()
    let clock = ContinuousClock()
    var parsed = 0
    for _ in 0..<3_000 {
      let count = Int.random(in: 1...30, using: &generator)
      // A directive takes effect only at the start of the stream: a quarter of the documents
      // start with one and three nodes that use it, enough for its copies to outgrow the text.
      let head = Int.random(in: 0..<4, using: &generator) == 0 ? Self.taggedHead : ""
      let text =
        head + (0..<count).map { _ in Self.pieces.randomElement(using: &generator)! }.joined()
      let accepted = FrontNode.preParseFailure(of: text, limits: limits) == nil
      let start = clock.now
      guard let parser = try? Parser(yaml: text), let root = try? parser.singleRoot() else {
        continue
      }
      #expect(clock.now - start < .seconds(1), "\(text.debugDescription)")
      parsed += 1
      var found: [Node] = []
      withExtendedLifetime(parser) {
        nodes(root, cap: limits.maxNodes, into: &found)
        if found.contains(where: { $0.anchor != nil }) {
          #expect(FrontNode.hasAnchor(text), "\(text.debugDescription)")
        }
      }
      guard accepted else { continue }
      #expect(found.count <= limits.maxNodes, "\(text.debugDescription)")
      // Without a directive a tag other than a core one spells out only its own text, plus
      // the default prefix; a `%TAG` prefix would be copied into every tag that uses it.
      let tags = found.map(storedTag).filter { !$0.isEmpty && !Self.coreTags.contains($0) }
      let bound = text.utf8.count + tags.count * Self.defaultTagPrefix.utf8.count
      #expect(tags.map(\.utf8.count).reduce(0, +) <= bound, "\(text.debugDescription)")
    }
    // The generator must reach Yams often enough for the test to mean something.
    #expect(parsed > 300)
  }
}
