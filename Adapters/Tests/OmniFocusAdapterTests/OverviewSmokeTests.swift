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
      tasks: source, vault: try await DemoVault().vault(), stored: Workspace(timeZone: .gmt),
      identities: &identities,
      now: source.generatedAt)
    return Overview(workspace: workspace, now: source.generatedAt)
  }

  func daysSinceLastActivity(_ key: LineKey, in overview: Overview) throws -> Int? {
    let row = try #require(overview.lines().blocks.flatMap(\.rows).first { $0.line.key == key })
    let lastActivity = try #require(row.activity.lastActivity)
    return overview.calendar.dateComponents(
      [.day], from: overview.calendar.startOfDay(for: lastActivity),
      to: overview.calendar.startOfDay(for: overview.now)
    ).day
  }

  /// Italian (active) and Piano (maintenance) both last moved 29 days ago; only the active
  /// line is quiet, because maintenance is never quiet. Japanese has no activity yet.
  @Test func activeItalianIsQuietAndMaintenancePianoIsNot() async throws {
    let overview = try await overview()
    #expect(try daysSinceLastActivity("italian", in: overview) == 29)
    #expect(try daysSinceLastActivity("piano", in: overview) == 29)
    let quiet = overview.today().quietLines
    #expect(quiet.map(\.line.key) == ["italian", "japanese"])
    guard case .quiet(let days, let last) = quiet.first?.reason else {
      Issue.record("Italian is not quiet")
      return
    }
    #expect(days == 29)
    #expect(
      last.completedAt
        == DemoVault.calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 19)))
  }

  @Test func everyViewRendersOnTheFixture() async throws {
    let overview = try await overview()
    let today = overview.today()
    #expect(!today.groups.isEmpty)
    #expect(today.groups.flatMap(\.items).filter(\.isUrgent).allSatisfy { $0.task.dueAt != nil })
    let week = overview.week()
    #expect(week.days.count == 7)
    #expect(week.header.count == 12)
    let lines = overview.lines()
    #expect(lines.blocks.flatMap(\.rows).count == 11)
    #expect(lines.blocks.flatMap(\.rows).allSatisfy { $0.activity.sparkline.count == 8 })
  }
}
