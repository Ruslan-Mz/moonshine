import Foundation
import MoonShineCore

/// A note's frontmatter could not be read; `line` is the note's line number, when known.
struct FrontmatterFailure: Error, Equatable {
  let kind: VaultProblem.Kind
  let line: Int?
}

enum Frontmatter {
  /// The YAML text between a note's opening `---` line and its closing one (it starts on line 2
  /// of the note); nil when the note has no frontmatter. Reads at most the cap plus a few bytes.
  static func text(of url: URL, limit: Int) throws(FrontmatterFailure) -> String? {
    // Room for both delimiter lines, so frontmatter of exactly `limit` bytes still closes.
    let readCount = limit + 16
    let head: Data
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      head = try handle.read(upToCount: readCount) ?? Data()
    } catch {
      throw FrontmatterFailure(kind: .unreadable, line: nil)
    }
    return try extract(from: Array(head), atEnd: head.count < readCount, limit: limit)
  }

  /// `head` is the start of a note; `atEnd` says whether it is the whole note.
  static func extract(from head: [UInt8], atEnd: Bool, limit: Int) throws(FrontmatterFailure)
    -> String?
  {
    let lines = head.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
    guard let opening = lines.first, isDelimiter(opening), lines.count > 1 else { return nil }
    var offset = opening.count + 1
    for (index, line) in lines.enumerated().dropFirst() {
      // The last piece has no newline after it: a delimiter only if the note ends there.
      let complete = index < lines.count - 1 || atEnd
      if complete, isDelimiter(line) {
        let body = head[(opening.count + 1)..<offset]
        guard body.count <= limit else {
          throw FrontmatterFailure(kind: .frontmatterTooLarge, line: nil)
        }
        guard let text = String(validating: body, as: UTF8.self) else {
          throw FrontmatterFailure(kind: .notUTF8, line: nil)
        }
        return text
      }
      offset += line.count + 1
    }
    if !atEnd || offset - opening.count - 1 > limit {
      throw FrontmatterFailure(kind: .frontmatterTooLarge, line: nil)
    }
    throw FrontmatterFailure(kind: .malformedYAML, line: 1)
  }

  /// `---`, optionally followed by spaces, tabs or a carriage return.
  private static func isDelimiter(_ line: ArraySlice<UInt8>) -> Bool {
    let trimmed = line.reversed().drop { [9, 13, 32].contains($0) }
    return trimmed.count == 3 && trimmed.allSatisfy { $0 == UInt8(ascii: "-") }
  }
}
