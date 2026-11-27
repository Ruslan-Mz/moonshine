import Foundation

/// MoonShine's own OmniFocus URLs (ADR-0015, amendment of 2026-10-21): `omnifocus:///task/<id>`
/// and `omnifocus:///project/<id>`, the stored id and nothing else. An id outside OmniFocus's id
/// alphabet opens nothing.
public enum OmniFocusLink {
  /// `^[A-Za-z0-9_-]{1,64}(\.[0-9]{1,6})?$`: a live id, and an occurrence `<liveId>.<n>`
  /// (`docs/discovery/snapshot-contract.md`, `repeatOf`). Checked scalar by scalar, so no line
  /// break can end a match early.
  public static func isOpenableID(_ id: String) -> Bool {
    let parts = id.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let live = parts.first, (1...64).contains(live.count),
      live.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "_" || $0 == "-" })
    else { return false }
    guard parts.count == 2 else { return true }
    let occurrence = parts[1]
    return (1...6).contains(occurrence.count) && occurrence.allSatisfy { ("0"..."9").contains($0) }
  }

  public static func task(_ id: String) -> URL? { url("task", id) }

  public static func project(_ id: String) -> URL? { url("project", id) }

  /// The literal prefix and the checked id, then parsed back: no host, no query, no fragment.
  private static func url(_ kind: String, _ id: String) -> URL? {
    guard isOpenableID(id), let url = URL(string: "omnifocus:///\(kind)/\(id)"),
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "omnifocus", parts.host ?? "" == "",
      parts.percentEncodedPath == "/\(kind)/\(id)", parts.query == nil, parts.fragment == nil,
      parts.user == nil, parts.port == nil
    else { return nil }
    return url
  }

  private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
    ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
  }
}

/// MoonShine's own Obsidian URL (ADR-0015, correction of 2026-10-12): `obsidian://open` with
/// `vault` and `file` only; no `paneType` in phase 1.
public enum ObsidianLink {
  /// The longest vault name or vault-relative path, in UTF-8 bytes.
  public static let maximumBytes = 1024

  public static func open(vault: String, file: String) -> URL? {
    guard isAcceptable(vault), isAcceptable(file),
      let vaultValue = vault.addingPercentEncoding(withAllowedCharacters: unreserved),
      let fileValue = file.addingPercentEncoding(withAllowedCharacters: unreserved)
    else { return nil }
    var parts = URLComponents()
    parts.scheme = "obsidian"
    parts.host = "open"
    parts.percentEncodedQuery = "vault=\(vaultValue)&file=\(fileValue)"
    // Parsed back: exactly the two items, equal to the inputs.
    guard let url = parts.url,
      let back = URLComponents(url: url, resolvingAgainstBaseURL: false),
      back.scheme == "obsidian", back.host == "open", back.path == "", back.fragment == nil,
      back.queryItems
        == [URLQueryItem(name: "vault", value: vault), URLQueryItem(name: "file", value: file)]
    else { return nil }
    return url
  }

  /// RFC 3986's unreserved set, ASCII only: `&`, `=`, `+`, `#`, `%`, `?`, `/` and spaces are
  /// escaped, so no value can add a parameter.
  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  private static func isAcceptable(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= maximumBytes
      && !value.unicodeScalars.contains { scalar in
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: true
        default: false
        }
      }
  }
}
