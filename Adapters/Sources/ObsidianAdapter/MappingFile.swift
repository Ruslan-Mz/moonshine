import Foundation
import MoonShineCore

/// `mapping.yaml` in the data folder (S4-4c-2): which top-level OmniFocus tag groups hold task
/// attributes, not lines. The names are the owner's labels, so they live only there.
public enum MappingFile {
  public static let name = "mapping.yaml"

  public enum Read: Equatable, Sendable {
    /// No file: no group is meta.
    case missing
    case groups(Set<String>)
  }

  /// At most this many groups.
  public static let maxGroups = 20

  /// Reads `<folder>/mapping.yaml`: only `meta_tag_groups`, a list of 0–20 distinct names, each
  /// by the line `name` rule (vault contract §1). The whole file is valid or none of it is used.
  public static func read(folder: URL) throws(MappingFileError) -> Read {
    let limits = VaultLimits()
    let path = folder.appending(path: name).path(percentEncoded: false)
    // `attributesOfItem` does not follow a link: a link, dangling or not, is not the file.
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try FileManager.default.attributesOfItem(atPath: path)
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    {
      return .missing
    } catch {
      throw .unreadable
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else { throw .unreadable }
    if let size = attributes[.size] as? Int, size > limits.maxFrontmatterBytes {
      throw .invalid(.frontmatterTooLarge, key: .root)
    }
    // Read up to one byte past the cap, in case the file grew since its size was read.
    let data: Data
    do {
      let handle = try FileHandle(forReadingFrom: URL(filePath: path))
      defer { try? handle.close() }
      data = try handle.read(upToCount: limits.maxFrontmatterBytes + 1) ?? Data()
    } catch {
      throw .unreadable
    }
    guard data.count <= limits.maxFrontmatterBytes else {
      throw .invalid(.frontmatterTooLarge, key: .root)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw .invalid(.notUTF8, key: .root)
    }
    return .groups(try groups(in: text, limits: limits))
  }

  private static func groups(
    in text: String, limits: VaultLimits
  ) throws(MappingFileError) -> Set<String> {
    let root: FrontNode
    do {
      root = try FrontNode.parse(text, limits: limits)
    } catch {
      throw .invalid(error.kind, key: .root)
    }
    // Exactly one key, and only this one; an empty file is an empty mapping, so it is invalid.
    guard case .mapping(let entries) = root.value, entries.count == 1,
      entries[0].key == MappingFileError.Key.metaTagGroups.rawValue
    else { throw .invalid(.invalidValue, key: .root) }
    guard case .sequence(let items) = entries[0].node.value, items.count <= maxGroups else {
      throw .invalid(.invalidValue, key: .metaTagGroups)
    }
    let names = items.compactMap(\.scalar).filter {
      Fields.text($0, characters: 120, bytes: 1024)
    }
    let groups = Set(names)
    guard names.count == items.count, groups.count == names.count else {
      throw .invalid(.invalidValue, key: .metaTagGroups)
    }
    return groups
  }
}

/// Why `mapping.yaml` cannot be used: a kind and a fixed key, never a value or a key from the
/// file. Every import waits for a valid file.
public enum MappingFileError: Error, Equatable, Sendable, ImportFailureKind {
  public enum Key: String, Sendable {
    case root
    case metaTagGroups = "meta_tag_groups"
  }

  /// Not a regular file (a folder, a link), or the read failed.
  case unreadable
  case invalid(VaultProblem.Kind, key: Key)

  public var importFailure: ImportFailure { .mappingInvalid }
}
