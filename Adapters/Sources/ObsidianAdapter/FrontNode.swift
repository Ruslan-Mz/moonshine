import Foundation
import MoonShineCore
import Yams

/// Frontmatter in the reader's own bounded form. Yams' nodes never leave this file; anchors (and
/// so aliases) are rejected before parsing, the node and depth caps bound the parsed tree, and
/// scalars stay raw strings (no YAML date or number types).
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

  /// Parses frontmatter text; the root must be a mapping.
  static func parse(_ text: String, limits: VaultLimits) throws(FrontmatterFailure) -> FrontNode {
    // libyaml parses flow collections recursively: reject deep `[[[…` before it sees them.
    // Yams expands aliases while composing (it hashes mapping keys), before any cap of ours
    // runs, so anchors are rejected outright: no anchor, no alias, no alias bomb.
    guard flowDepth(of: text) <= limits.maxDepth else {
      throw FrontmatterFailure(kind: .yamlTooComplex, line: nil)
    }
    guard !hasAnchor(text) else { throw FrontmatterFailure(kind: .yamlAnchor, line: nil) }
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
  private static func hasAnchor(_ text: String) -> Bool {
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
