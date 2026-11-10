import Foundation
import MoonShineFixtures
import Testing

@testable import MoonShineCore

/// The vault is read in the zone of the task snapshot, which `Workspace.timeZone` takes
/// (`docs/specs/phase-1-see.md`, S4; S4-4d). Invented data.
@Suite struct VaultTimeZoneTests {
  static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

  struct Tasks: TaskProvider {
    let timeZone: TimeZone
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        timeZone: timeZone, defaultTimes: DefaultTimeSettings(), tags: [], projects: [],
        tasks: [])
    }
  }

  /// Records each zone it is read in, and names its one line after it.
  actor ZoneVault: NoteProvider {
    private(set) var zones: [String] = []
    func vault(timeZone: TimeZone) async -> VaultSnapshot {
      zones.append(timeZone.identifier)
      return VaultSnapshot(
        lines: .read(
          [
            SourceLine(
              key: "zone", name: timeZone.identifier, block: "B", state: .active, tags: ["z"])
          ], complete: true),
        artifacts: [], notes: [], unread: .nothing)
    }
  }

  func run(tasks: TimeZone, firstRead: TimeZone) async throws -> (Workspace, [String]) {
    let vault = ZoneVault()
    let service = ImportService(
      tasks: Tasks(timeZone: tasks), notes: vault, store: InMemoryStore(timeZone: tasks),
      importer: Importer(metaTagGroups: []), vaultTimeZone: { firstRead },
      clock: .frozen(at: Date(timeIntervalSince1970: 1_790_000_000)))
    let workspace = try await service.run(ImportRequest(trigger: .manual))
    return (workspace, await vault.zones)
  }

  @Test func theVaultIsReadOnceWhenItsZoneIsTheSnapshots() async throws {
    let (workspace, zones) = try await run(tasks: TestWorld.timeZone, firstRead: TestWorld.timeZone)
    #expect(zones == [TestWorld.timeZone.identifier])
    #expect(workspace.lines.map(\.name) == [TestWorld.timeZone.identifier])
  }

  @Test func aVaultReadInAnotherZoneIsReadAgainInTheSnapshotsZone() async throws {
    let (workspace, zones) = try await run(tasks: TestWorld.timeZone, firstRead: Self.tokyo)
    #expect(zones == [Self.tokyo.identifier, TestWorld.timeZone.identifier])
    #expect(workspace.timeZone == TestWorld.timeZone)
    #expect(workspace.lines.map(\.name) == [TestWorld.timeZone.identifier])
  }
}
