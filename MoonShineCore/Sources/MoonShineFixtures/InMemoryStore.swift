import Foundation
import MoonShineCore

/// A `Store` kept in memory, for tests and Demo mode; same retention rule as the SQLite store.
public actor InMemoryStore: Store {
  private var identities = IdentityMap()
  private var current: StoredWorkspace
  private var version = 0

  public init(timeZone: TimeZone = .current) {
    current = StoredWorkspace(timeZone: timeZone)
  }

  public func identityMap() -> VersionedIdentityMap {
    VersionedIdentityMap(map: identities, version: version)
  }

  public func commit(
    _ workspace: Workspace, identities: IdentityMap, expectedVersion: Int, at now: Date
  ) throws {
    guard expectedVersion == version else {
      throw IdentityConflict(expectedVersion: expectedVersion, actualVersion: version)
    }
    current = current.merging(workspace, at: now)
    self.identities = identities
    version += 1
  }

  public func workspace() -> Workspace { current.workspace }

  public func stored() -> StoredWorkspace { current }
}
