import Foundation
import MoonShineCore

/// A `Store` kept in memory, for tests and until the GRDB store lands (S2).
public actor InMemoryStore: Store {
  private var identities = IdentityMap()
  private var current: Workspace

  public init(timeZone: TimeZone = .current) {
    current = Workspace(timeZone: timeZone)
  }

  public func identityMap() -> IdentityMap { identities }

  public func commit(_ workspace: Workspace, identities: IdentityMap) {
    self.current = workspace
    self.identities = identities
  }

  public func workspace() -> Workspace { current }
}
