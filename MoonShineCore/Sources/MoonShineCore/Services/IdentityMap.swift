import Foundation

/// Maps provider identities to MoonShine ids, so re-imports keep every id.
/// Keyed by entity kind too: OmniFocus projects and their root tasks share a primary key.
public struct IdentityMap: Sendable {
  public struct Key: Hashable, Sendable {
    public let kind: String
    public let provider: ProviderID
    public let externalId: String

    public init(kind: String, provider: ProviderID, externalId: String) {
      self.kind = kind
      self.provider = provider
      self.externalId = externalId
    }
  }

  public private(set) var entries: [Key: UUID] = [:]

  public init(entries: [Key: UUID] = [:]) {
    self.entries = entries
  }

  public mutating func id<Entity>(for ref: ExternalRef, now: Date) -> EntityID<Entity> {
    let key = Key(
      kind: String(describing: Entity.self), provider: ref.provider, externalId: ref.externalId)
    if let uuid = entries[key] {
      return EntityID(uuid: uuid)
    }
    let id = EntityID<Entity>.generate(at: now)
    entries[key] = id.uuid
    return id
  }
}
