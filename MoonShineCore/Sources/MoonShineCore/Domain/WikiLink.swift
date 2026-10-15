import Foundation

/// An Obsidian wikilink written in a frontmatter value (a line's or a note's `parent`).
public enum WikiLink {
  /// The index in `paths` (vault-relative note paths) of the note `link` points to, or nil.
  /// `[[Name]]`, `[[Name|alias]]` and `[[Name#heading]]` match a file name; `[[Folder/Name]]`
  /// a path that equals it or ends with `/Folder/Name`; `[[/Folder/Name]]` the whole path
  /// only. `.md` is optional, in any case. A whole path wins over the end of one; of several
  /// matches otherwise, the first in path order.
  public static func target(of link: String, in paths: [String]) -> Int? {
    var text = Substring(link.trimmingCharacters(in: .whitespaces))
    if text.hasPrefix("[["), text.hasSuffix("]]") { text = text.dropFirst(2).dropLast(2) }
    var target = stem(text.prefix { $0 != "|" && $0 != "#" }.trimmingCharacters(in: .whitespaces))
    let fromRoot = target.hasPrefix("/")
    if fromRoot { target = target.dropFirst() }
    guard !target.isEmpty else { return nil }
    // Paths are matched on their stems; of several, the first in path order.
    func first(_ matches: (Substring) -> Bool) -> Int? {
      paths.indices.filter { matches(stem(paths[$0])) }.min { paths[$0] < paths[$1] }
    }
    if let whole = first({ $0 == target }) { return whole }
    return fromRoot ? nil : first { $0.hasSuffix("/" + target) }
  }

  /// `text` without a final `.md` in any case.
  private static func stem<Text: StringProtocol>(_ text: Text) -> Substring {
    let whole = Substring(text)
    return whole.suffix(3).lowercased() == ".md" ? whole.dropLast(3) : whole
  }
}
