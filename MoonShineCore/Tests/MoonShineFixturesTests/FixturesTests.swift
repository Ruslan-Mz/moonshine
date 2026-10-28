import Foundation
import MoonShineCore
import Testing

@testable import MoonShineFixtures

@Suite struct DemoVaultTests {
  let vault = DemoVault.snapshot

  @Test func mirrorsTheFixtureBudgetNote() {
    #expect(
      vault.lines.read.map(\.key.rawValue) == [
        "core", "calisthenics", "ai", "research", "violin", "piano", "calligraphy", "italian",
        "japanese", "math", "family",
      ])
    let calligraphy = vault.lines.read.first { $0.key == "calligraphy" }
    #expect(calligraphy?.state == .paused)
    #expect(vault.lines.read.first { $0.key == "piano" }?.state == .maintenance)
    let core = vault.lines.read.first { $0.key == "core" }
    #expect(core?.foundation == true && core?.floorHoursPerDay == 3)
    #expect(core?.budgetHoursPerWeek == nil)
    #expect(vault.lines.read.first { $0.key == "ai" }?.taskRules.projects.count == 3)
    #expect(vault.lines.read.first { $0.key == "math" }?.taskRules.folders == ["Study"])
    #expect(vault.lines.read.first { $0.key == "research" }?.taskRules.tags == ["исследование"])
  }

  @Test func mirrorsTheFixtureArtifactsAndNotes() {
    #expect(vault.artifacts.filter { $0.periodKey == "2026" }.count == 10)
    // `design/demo-data.md` § Draft-2: the Q4 focus, two of five done.
    let quarter = vault.artifacts.filter { $0.periodKey == "2026-Q4" }
    #expect(quarter.map(\.key) == ["q4-01", "q4-02", "q4-03", "q4-04", "q4-05"])
    #expect(quarter.filter { $0.status == .done }.count == 2)
    #expect(vault.notes.count == 6)
    let month = vault.notes.first { $0.type == "month_plan" }
    #expect(month?.scale == .month)
    #expect(
      month?.period?.contains(
        DemoVault.calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!) == true)
  }
}

@Suite struct InMemoryStoreTests {
  struct OneTaskProvider: TaskProvider {
    func snapshot(modifiedSince: Date?) async throws -> TaskSourceSnapshot {
      TaskSourceSnapshot(
        provider: .omnifocus, generatedAt: Date(timeIntervalSince1970: 0),
        timeZone: DemoVault.calendar.timeZone,
        tags: [SourceTag(externalId: "t", name: "violin")],
        projects: [SourceProject(externalId: "p", name: "Technique", tagExternalIds: ["t"])],
        tasks: [SourceTask(externalId: "x", name: "Scales", projectExternalId: "p")])
    }
  }

  @Test func reimportIsIdempotent() async throws {
    let store = InMemoryStore()
    let service = ImportService(tasks: OneTaskProvider(), notes: DemoVault(), store: store)
    let first = try await service.run()
    let second = try await service.run()
    let stored = await store.workspace()

    #expect(first.tasks.map(\.id) == second.tasks.map(\.id))
    #expect(first.projects.map(\.id) == second.projects.map(\.id))
    #expect(first.lines.map(\.id) == second.lines.map(\.id))
    #expect(stored.tasks.count == 1)
    #expect(stored.lines.count == 11)
    let violin = try #require(stored.lines.first { $0.key == "violin" })
    #expect(stored.tasks.first?.line == .line(violin.id))
  }

  @Test func emptyStoreHasNoData() async {
    let workspace = await InMemoryStore().workspace()
    #expect(workspace.tasks.isEmpty)
    #expect(workspace.lines.isEmpty)
  }
}
