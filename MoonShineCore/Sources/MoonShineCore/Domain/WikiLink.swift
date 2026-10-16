import Foundation

/// An Obsidian wikilink written in a frontmatter value (a line's or a note's `parent`),
/// resolved as ADR-0014 says (owner, 2026-10-15).
public enum WikiLink {
  /// The note a link points to, as an index into the paths it was resolved against.
  public struct Target: Equatable, Sendable {
    public let index: Int
    /// More than one note matched; the shortest path was taken.
    public let isAmbiguous: Bool
  }

  /// The note `link` points to among `paths` (vault-relative note paths), or nil.
  /// `[[Name]]`, `[[Name|alias]]` and `[[Name#heading]]` match a file name; `[[Folder/Name]]`
  /// a path that equals it or ends with `/Folder/Name`; `[[/Folder/Name]]` the whole path
  /// only. Case is ignored in every script, and `.md` is optional. Of several matches the
  /// shortest path wins, then the first by path, and the link is ambiguous.
  public static func target(of link: String, in paths: [String]) -> Target? {
    var text = Substring(link.trimmingCharacters(in: .whitespaces))
    if text.hasPrefix("[["), text.hasSuffix("]]") { text = text.dropFirst(2).dropLast(2) }
    var target = key(text.prefix { $0 != "|" && $0 != "#" }.trimmingCharacters(in: .whitespaces))
    let fromRoot = target.hasPrefix("/")
    if fromRoot { target.removeFirst() }
    guard !target.isEmpty else { return nil }
    let matches = paths.indices.filter { index in
      let path = key(paths[index])
      return path == target || (!fromRoot && path.hasSuffix("/" + target))
    }
    let shortest = matches.min { first, second in
      let (a, b) = (paths[first], paths[second])
      return a.count != b.count ? a.count < b.count : a < b
    }
    return shortest.map { Target(index: $0, isAmbiguous: matches.count > 1) }
  }

  /// `text` without a final `.md` in any case, with its case folded.
  private static func key<Text: StringProtocol>(_ text: Text) -> String {
    let whole = Substring(text)
    let stem = whole.suffix(3).lowercased() == ".md" ? whole.dropLast(3) : whole
    return stem.folding(options: .caseInsensitive, locale: nil)
  }
}
