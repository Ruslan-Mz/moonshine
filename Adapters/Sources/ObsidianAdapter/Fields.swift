import MoonShineCore

/// The value checks the vault schemas share (contract §1 and §2): one mapping's keys, read one
/// by one. Every problem is reported with the schema's key (`lines.name`, `notes.title`) and
/// the line, never a value; a problem that skips the item sets `skip`.
struct Fields {
  let path: String
  let node: FrontNode
  /// `lines`, `notes` or `artifacts`: the first part of every reported key.
  let schema: String
  private(set) var issues: [ImportIssue] = []
  private(set) var skip = false

  init(path: String, node: FrontNode, schema: String) {
    self.path = path
    self.node = node
    self.schema = schema
  }

  /// A plain decimal from 0 to `max`: no sign, exponent, hex, `nan`, `inf` or decimal comma.
  static func number(_ text: String, max: Double) -> Double? {
    guard text.allSatisfy(\.isASCII), text.wholeMatch(of: #/[0-9]+(\.[0-9]+)?/#) != nil,
      let value = Double(text),
      value <= max
    else { return nil }
    return value
  }

  /// Non-empty, at most `characters` grapheme clusters (what the limit means to a reader) and
  /// `bytes` UTF-8 bytes (a cluster can hold any number of combining marks), no control.
  static func text(_ text: String, characters: Int, bytes: Int) -> Bool {
    !text.isEmpty && text.count <= characters && text.utf8.count <= bytes && !hasControl(text)
  }

  /// A C0 control character or DEL. The store's text columns end at a NUL, so `Life\0X` would
  /// come back as `Life`.
  static func hasControl(_ text: String) -> Bool {
    text.utf8.contains { $0 < 0x20 || $0 == 0x7F }
  }

  /// A line or artifact id: `[a-z0-9-]`, 1 to 64 bytes.
  static func isID(_ text: String) -> Bool {
    (1...64).contains(text.utf8.count) && text.utf8.allSatisfy(isSlug)
  }

  /// `[a-z0-9-]`, byte by byte: a Character range would let `a` + U+0332 through (a letter
  /// with a combining mark that has no precomposed form).
  private static func isSlug(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "-")
  }

  func line(of key: String) -> Int { node[key]?.line ?? node.line }

  /// The value of `key`; nil when absent or null.
  func present(_ key: String) -> FrontNode? {
    guard let child = node[key], child.value != .null else { return nil }
    return child
  }

  mutating func required(_ key: String, _ valid: (String) -> Bool) -> String? {
    guard let child = present(key) else {
      report(.missingKey, "\(schema).\(key)", node.line)
      return nil
    }
    return checked(key, child, valid)
  }

  mutating func optional(_ key: String, _ valid: (String) -> Bool) -> String? {
    present(key).flatMap { checked(key, $0, valid) }
  }

  mutating func checked(_ key: String, _ child: FrontNode, _ valid: (String) -> Bool) -> String? {
    guard let text = child.scalar, valid(text) else {
      report(.invalidValue, "\(schema).\(key)", child.line)
      return nil
    }
    return text
  }

  /// `key` is the full contract key. `skips` is false for a problem the item is still read with.
  mutating func report(
    _ kind: VaultProblem.Kind, _ key: String, _ line: Int, skips: Bool = true
  ) {
    issues.append(.vault(path: path, line: line, problem: VaultProblem(kind, key: key)))
    if skips { skip = true }
  }
}
