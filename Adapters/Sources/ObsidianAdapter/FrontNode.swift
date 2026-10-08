import Foundation
import MoonShineCore
import Yams

/// Frontmatter in the reader's own bounded form. Yams' nodes never leave this file; an anchor
/// with an alias and any directive are rejected before parsing, the node and depth caps bound
/// the parsed tree, and scalars stay raw strings (no YAML date or number types).
struct FrontNode: Equatable {
  enum Value: Equatable {
    case null
    case scalar(String)
    case sequence([FrontNode])
    case mapping([Entry])
  }

  struct Entry: Equatable {
    let key: String
    let node: FrontNode
  }

  let value: Value
  /// Line in the note (the frontmatter starts on line 2).
  let line: Int

  /// The value of `key` when this node is a mapping.
  subscript(key: String) -> FrontNode? {
    guard case .mapping(let entries) = value else { return nil }
    return entries.first { $0.key == key }?.node
  }

  /// The text of a scalar node; nil for null, sequences and mappings.
  var scalar: String? {
    if case .scalar(let text) = value { text } else { nil }
  }

  /// Parses frontmatter text; the root must be a mapping.
  static func parse(_ text: String, limits: VaultLimits) throws(FrontmatterFailure) -> FrontNode {
    if let kind = preParseFailure(of: text, limits: limits) {
      throw FrontmatterFailure(kind: kind, line: nil)
    }
    let composed: Node?
    do {
      composed = try Yams.compose(yaml: text)
    } catch {
      // Yams' own description quotes the YAML text, so only the line number is kept.
      throw FrontmatterFailure(kind: .malformedYAML, line: noteLine(of: error))
    }
    guard let composed else { return FrontNode(value: .mapping([]), line: firstLine) }
    guard case .mapping = composed else {
      throw FrontmatterFailure(kind: .malformedYAML, line: nil)
    }
    var budget = limits.maxNodes
    return try convert(composed, depth: 0, budget: &budget, limits: limits)
  }

  /// Why `text` is rejected before Yams sees it, if it is.
  static func preParseFailure(of text: String, limits: VaultLimits) -> VaultProblem.Kind? {
    // libyaml parses flow collections recursively: reject deep `[[[…` before it sees them.
    if flowDepth(of: text) > limits.maxDepth { return .yamlTooComplex }
    // libyaml copies a `%TAG` prefix into every tag that uses it, before any cap of ours runs.
    if hasDirective(text) { return .yamlDirective }
    // Yams expands aliases while composing (it hashes mapping keys), before any cap of ours
    // runs. An alias needs an anchor, so a document with only one of the two cannot expand.
    if hasAnchor(text) && hasAlias(text) { return .yamlAnchor }
    return nil
  }

  /// The frontmatter's first line is line 2 of the note, after the opening `---`.
  private static let firstLine = 2

  private static func convert(
    _ node: Node, depth: Int, budget: inout Int, limits: VaultLimits
  ) throws(FrontmatterFailure) -> FrontNode {
    budget -= 1
    guard budget >= 0, depth <= limits.maxDepth else {
      throw FrontmatterFailure(kind: .yamlTooComplex, line: nil)
    }
    let line = (node.mark?.line ?? 1) + firstLine - 1
    switch node {
    case .scalar(let scalar):
      return FrontNode(value: node.null != nil ? .null : .scalar(scalar.string), line: line)
    case .sequence(let sequence):
      var items: [FrontNode] = []
      for item in sequence {
        items.append(try convert(item, depth: depth + 1, budget: &budget, limits: limits))
      }
      return FrontNode(value: .sequence(items), line: line)
    case .mapping(let mapping):
      var entries: [Entry] = []
      for (key, value) in mapping {
        guard case .scalar(let name) = key else {
          throw FrontmatterFailure(kind: .malformedYAML, line: line)
        }
        let child = try convert(value, depth: depth + 1, budget: &budget, limits: limits)
        entries.append(Entry(key: name.string, node: child))
      }
      return FrontNode(value: .mapping(entries), line: line)
    case .alias:
      // Yams resolves aliases while composing; an unresolved one is not valid frontmatter.
      throw FrontmatterFailure(kind: .malformedYAML, line: line)
    }
  }

  /// The deepest nesting of `[` and `{`, counted lexically (brackets in quotes count too).
  private static func flowDepth(of text: String) -> Int {
    var depth = 0
    var deepest = 0
    for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "["), UInt8(ascii: "{"):
        depth += 1
        deepest = max(deepest, depth)
      case UInt8(ascii: "]"), UInt8(ascii: "}"):
        depth = max(0, depth - 1)
      default: break
      }
    }
    return deepest
  }

  /// Whether `text` may hold an anchor (`&name`). Lexical and deliberately coarse: quotes are
  /// not tracked, so an `&` in a quoted string counts too. A YAML token starts only after
  /// whitespace or an indicator, so an `&` right after a letter, mark or digit of any script
  /// (`R&D`, `Музыка&танец`, `音楽&舞踊`) is plain text.
  static func hasAnchor(_ text: String) -> Bool {
    var previous: Unicode.Scalar?
    var iterator = text.unicodeScalars.makeIterator()
    var current = iterator.next()
    while let scalar = current {
      let next = iterator.next()
      if scalar == "&", let next, !" \t\r\n,[]{}".unicodeScalars.contains(next),
        !(previous.map(isWordScalar) ?? false)
      {
        return true
      }
      previous = scalar
      current = next
    }
    return false
  }

  /// Whether `text` may hold an alias (`*name`): a `*` followed by a non-blank. Lexical and
  /// coarse like `hasAnchor`: a `*` in a quoted string or in Markdown `**bold**` counts too.
  static func hasAlias(_ text: String) -> Bool {
    zip(text.unicodeScalars, text.unicodeScalars.dropFirst()).contains { scalar, next in
      scalar == "*" && next != " " && next != "\t" && !lineBreaks.contains(next)
    }
  }

  /// Whether `text` may hold a directive: a `%` at its start or right after any line break
  /// libyaml knows, byte-order marks in between skipped. Coarse: a quoted scalar's continuation
  /// line that starts with `%` counts too.
  static func hasDirective(_ text: String) -> Bool {
    var atLineStart = true
    for scalar in text.unicodeScalars {
      if scalar == "%" && atLineStart { return true }
      if lineBreaks.contains(scalar) {
        atLineStart = true
      } else if scalar != "\u{FEFF}" {
        atLineStart = false
      }
    }
    return false
  }

  /// LF, CR, NEL, LS and PS: every line break libyaml knows.
  private static let lineBreaks: Set<Unicode.Scalar> = [
    "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}",
  ]

  /// Letters, combining marks and digits of any script.
  private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
      true
    default: false
    }
  }

  private static func noteLine(of error: any Error) -> Int? {
    let mark: Mark? =
      switch error as? YamlError {
      case .scanner(_, _, let mark, _), .parser(_, _, let mark, _), .composer(_, _, let mark, _):
        mark
      case .duplicatedKeysInMapping(_, let context): context.mark
      default: nil
      }
    return mark.map { $0.line + firstLine - 1 }
  }
}
