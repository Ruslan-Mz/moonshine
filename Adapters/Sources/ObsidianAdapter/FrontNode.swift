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
    // Yams composes collections recursively: reject deep `[[[…` and deep block nesting
    // (`- - - …`) before it sees them (S4-4d).
    if blockDepthBound(of: text) + flowDepth(of: text) > limits.maxDepth { return .yamlTooComplex }
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

  /// An upper bound on the block nesting Yams composes, counted lexically (S4-4d). A block
  /// collection opens at a column, a nested one at a greater column, except a sequence under a
  /// mapping key at the key's own column: so the nesting is at most two per distinct column
  /// where a collection can open. Those are the first token of a line and the token after each
  /// `- `, `? ` or `: ` (and after an anchor or tag that follows one). A column once seen stays
  /// counted, so a line left of open collections (a quoted or flow continuation) hides none.
  /// Comment and blank lines open nothing; block-scalar content is skipped only while libyaml
  /// reads it as content: right of the innermost collection on the header's line.
  static func blockDepthBound(of text: String) -> Int {
    var columns = Set<Int>()
    // The open block scalar: content must start right of `innermost`; `content` once known.
    var scalar: (innermost: Int, content: Int?)?
    for line in lines(of: text) {
      guard let first = line.firstIndex(where: { $0 != " " && $0 != "\t" }) else { continue }
      if let open = scalar {
        if let content = open.content, first >= content { continue }
        if open.content == nil, first > open.innermost {
          scalar = (open.innermost, first)
          continue
        }
        scalar = nil
      }
      if line[first] == "#" { continue }
      let opened = openingColumns(line, from: first)
      columns.formUnion(opened)
      scalar = blockScalarHeader(line, opened: opened)
    }
    return 2 * columns.count
  }

  /// The text split at every line break libyaml knows, each line without its leading
  /// byte-order marks (`hasDirective` skips them the same way).
  private static func lines(of text: String) -> [[Unicode.Scalar]] {
    var lines: [[Unicode.Scalar]] = [[]]
    for scalar in text.unicodeScalars {
      if lineBreaks.contains(scalar) {
        lines.append([])
      } else if !(scalar == "\u{FEFF}" && lines[lines.count - 1].isEmpty) {
        lines[lines.count - 1].append(scalar)
      }
    }
    return lines
  }

  /// The columns where a block collection can open on `line`: its first token, and the token
  /// after each indicator (`- `, `? `, `: `), past an anchor or tag that follows one.
  private static func openingColumns(_ line: [Unicode.Scalar], from first: Int) -> [Int] {
    let blank: (Int) -> Bool = { $0 >= line.count || line[$0] == " " || line[$0] == "\t" }
    let next: (Int) -> Int? = { start in
      var index = start
      while index < line.count, blank(index) { index += 1 }
      return index < line.count ? index : nil
    }
    var opened = [first]
    var index = first
    while true {
      let isIndicator = "-?:".unicodeScalars.contains(line[index]) && blank(index + 1)
      let isProperty = index != first && (line[index] == "&" || line[index] == "!")
      guard isIndicator || isProperty else { break }
      var end = index + 1
      while isProperty, !blank(end) { end += 1 }
      guard let token = next(end) else { break }
      opened.append(token)
      index = token
    }
    return opened
  }

  /// A block-scalar header (`|`, `>`, with chomping and indentation indicators) ending `line`
  /// right after an indicator or a key: the column content must start right of, and its fixed
  /// start when an indentation indicator gives one. Nil for anything else, which then counts as
  /// structure (a header followed by a comment included).
  private static func blockScalarHeader(
    _ line: [Unicode.Scalar], opened: [Int]
  ) -> (innermost: Int, content: Int?)? {
    var end = line.count
    while end > 0, line[end - 1] == " " || line[end - 1] == "\t" { end -= 1 }
    var start = end
    while start > 0, line[start - 1] != " ", line[start - 1] != "\t" { start -= 1 }
    let token = line[start..<end]
    guard let head = token.first, head == "|" || head == ">", token.count <= 3,
      token.dropFirst().allSatisfy({ "+-123456789".unicodeScalars.contains($0) })
    else { return nil }
    var before = start
    while before > 0, line[before - 1] == " " || line[before - 1] == "\t" { before -= 1 }
    guard before == 0 || ":-?".unicodeScalars.contains(line[before - 1]) else { return nil }
    let innermost = opened.filter { $0 < start }.max() ?? start
    let digit = token.dropFirst().first { $0.properties.numericType != nil }
    return (innermost, digit.map { innermost + Int($0.value - 48) })
  }

  /// The deepest nesting of `[` and `{`, counted lexically (brackets in quotes count too).
  static func flowDepth(of text: String) -> Int {
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
