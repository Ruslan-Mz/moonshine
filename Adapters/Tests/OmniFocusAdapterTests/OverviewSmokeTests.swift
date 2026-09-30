import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import OmniFocusAdapter

/// Core services on the whole Demo data set: fixture snapshot + Demo vault.
@Suite struct OverviewSmokeTests {
  func overview() async throws -> Overview {
    let source = try SnapshotMapper.map(try fixtureDocument())
    var identities = IdentityMap()
    let workspace = Importer().makeWorkspace(
      tasks: source, vault: try await DemoVault().vault(), identities: &identities,
      now: source.generatedAt)
    return Overview(workspace: workspace, now: source.generatedAt)
  }

  /// The fixture's quiet line (last completion 29 days ago) is Piano, which the Demo vault
  /// keeps in maintenance: only active lines are ever reported quiet.
  @Test func quietLinesAreActiveOnlySoTheMaintenancePianoIsNotReported() async throws {
    let overview = try await overview()
    let piano = try #require(
      overview.lines().blocks.flatMap(\.rows).first { $0.line.key == "piano" })
    let lastActivity = try #require(piano.activity.lastActivity)
    let daysAgo = overview.calendar.dateComponents(
      [.day], from: overview.calendar.startOfDay(for: lastActivity),
      to: overview.calendar.startOfDay(for: overview.now)
    ).day
    #expect(piano.line.state == .maintenance)
    #expect(daysAgo == 29)
    #expect(overview.today().quietLines.isEmpty)
  }

  @Test func everyViewRendersOnTheFixture() async throws {
    let overview = try await overview()
    let today = overview.today()
    #expect(!today.groups.isEmpty)
    #expect(today.groups.flatMap(\.items).filter(\.isUrgent).allSatisfy { $0.task.dueAt != nil })
    let week = overview.week()
    #expect(week.days.count == 7)
    #expect(week.header.count == 9)
    let lines = overview.lines()
    #expect(lines.blocks.flatMap(\.rows).count == 8)
    #expect(lines.blocks.flatMap(\.rows).allSatisfy { $0.activity.sparkline.count == 8 })
  }
}
