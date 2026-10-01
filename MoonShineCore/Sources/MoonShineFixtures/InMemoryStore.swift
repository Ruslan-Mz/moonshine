import Foundation
import MoonShineCore

/// A `Store` kept in memory, for tests and Demo mode; same retention rule as the SQLite store.
public actor InMemoryStore: Store {
  private var identities = IdentityMap()
  private var current: StoredWorkspace

  public init(timeZone: TimeZone = .current) {
    current = StoredWorkspace(timeZone: timeZone)
  }

  public func identityMap() -> IdentityMap { identities }

  public func commit(_ workspace: Workspace, identities: IdentityMap, at now: Date) {
    current = current.merging(workspace, at: now)
    self.identities = identities
  }

  public func workspace() -> Workspace { current.workspace }

  public func stored() -> StoredWorkspace { current }
}
