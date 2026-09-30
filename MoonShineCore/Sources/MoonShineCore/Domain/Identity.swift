import Foundation

/// MoonShine's own identity for an entity: a UUIDv7, typed by the entity it identifies.
/// Survives provider swaps; providers are linked through `ExternalRef`s.
public struct EntityID<Entity>: Hashable, Comparable, Sendable, CustomStringConvertible {
  public let uuid: UUID

  public init(uuid: UUID) {
    self.uuid = uuid
  }

  public static func generate(at date: Date = Date()) -> Self {
    var generator = SystemRandomNumberGenerator()
    return generate(at: date, using: &generator)
  }

  /// RFC 9562 UUIDv7: 48-bit Unix milliseconds, version 7, 74 random bits, variant 0b10.
  public static func generate(at date: Date, using generator: inout some RandomNumberGenerator)
    -> Self
  {
    let milliseconds = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    var bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    for index in 0..<6 {
      bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - index)))
    }
    bytes[6] = 0x70 | (bytes[6] & 0x0F)
    bytes[8] = 0x80 | (bytes[8] & 0x3F)
    let uuid = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
    return Self(uuid: uuid)
  }

  public var timestampMilliseconds: UInt64 {
    withUnsafeBytes(of: uuid.uuid) { raw in
      raw.prefix(6).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.uuid.uuidString < rhs.uuid.uuidString
  }

  public var description: String { uuid.uuidString.lowercased() }
}

public typealias LineID = EntityID<Line>
public typealias ArtifactID = EntityID<Artifact>
public typealias ProjectID = EntityID<Project>
public typealias TaskItemID = EntityID<TaskItem>
public typealias TagID = EntityID<Tag>
public typealias NoteID = EntityID<NoteRef>

public struct ProviderID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let omnifocus = ProviderID(rawValue: "omnifocus")
  public static let obsidian = ProviderID(rawValue: "obsidian")
}

/// Where an entity lives in a provider. Every imported entity carries at least one.
public struct ExternalRef: Hashable, Sendable {
  public let provider: ProviderID
  public let externalId: String
  public let lastSeen: Date

  public init(provider: ProviderID, externalId: String, lastSeen: Date) {
    self.provider = provider
    self.externalId = externalId
    self.lastSeen = lastSeen
  }
}
