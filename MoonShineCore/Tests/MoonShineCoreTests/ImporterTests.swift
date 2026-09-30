import Foundation
import Testing

@testable import MoonShineCore

@Suite struct ImporterTests {
  let now = Date(timeIntervalSince1970: 1_790_000_000)

  let vault = VaultSnapshot(
    lines: [
      SourceLine(
        key: "violin", name: "Violin", block: "Creative", state: .active, tags: ["violin"]),
      SourceLine(
        key: "morning", name: "Morning", block: "Foundation", state: .active, tags: ["Утро"]),
    ],
    artifacts: [
      SourceArtifact(
        key: "a26-02", title: "Partita", lineKeys: ["violin"], status: .inProgress,
        notePath: "Years/Artifacts_2026.md"),
      SourceArtifact(
        key: "a26-09", title: "Orphan", lineKeys: ["cello"], status: .planned,
        notePath: "Years/Artifacts_2026.md"),
    ],
    notes: [
      SourceNote(
        path: "Years/Artifacts_2026.md", title: "Artifacts 2026", type: "year_artifacts",
        scale: .year)
    ])

  func snapshot(_ tasks: [SourceTask], projects: [SourceProject] = []) -> TaskSourceSnapshot {
    TaskSourceSnapshot(
      provider: .omnifocus, generatedAt: now, timeZone: TimeZone(identifier: "Europe/Moscow")!,
      tags: [
        SourceTag(externalId: "t-violin", name: "violin"),
        SourceTag(externalId: "t-cycle", name: "Цикл"),
        SourceTag(externalId: "t-morning", name: "Утро", parentExternalId: "t-cycle"),
        SourceTag(externalId: "t-time", name: "Время"),
        SourceTag(externalId: "t-time-low", name: "Низкая", parentExternalId: "t-time"),
        SourceTag(externalId: "t-energy", name: "Энергия"),
        SourceTag(externalId: "t-energy-low", name: "Низкая", parentExternalId: "t-energy"),
      ],
      projects: projects, tasks: tasks)
  }

  func run(_ source: TaskSourceSnapshot, identities: inout IdentityMap) -> Workspace {
    Importer().makeWorkspace(tasks: source, vault: vault, identities: &identities, now: now)
  }

  func run(_ source: TaskSourceSnapshot) -> Workspace {
    var identities = IdentityMap()
    return run(source, identities: &identities)
  }

  func task(_ workspace: Workspace, _ externalId: String) throws -> TaskItem {
    try #require(workspace.tasks.first { $0.refs.contains { $0.externalId == externalId } })
  }

  @Test func childrenOfMetaGroupsAreMetaAndNeverMapALine() throws {
    let ws = run(
      snapshot([SourceTask(externalId: "x", name: "Stretch", tagExternalIds: ["t-morning"])]))
    #expect(try task(ws, "x").line == .lifeOps)
    #expect(
      ws.tags.filter(\.isMeta).map(\.name).sorted() == [
        "Время", "Низкая", "Низкая", "Утро", "Цикл", "Энергия",
      ])
  }

  @Test func duplicateLeafNamesStayDistinctTagsReferencedByID() throws {
    let ws = run(
      snapshot([SourceTask(externalId: "x", name: "Tidy", tagExternalIds: ["t-energy-low"])]))
    let energyLow = try #require(ws.tags.first { $0.refs.first?.externalId == "t-energy-low" })
    let timeLow = try #require(ws.tags.first { $0.refs.first?.externalId == "t-time-low" })
    #expect(energyLow.id != timeLow.id)
    #expect(try task(ws, "x").tagIDs == [energyLow.id])
  }

  @Test func taskTagMapsLineAndProjectAndParentResolveToIDs() throws {
    let ws = run(
      snapshot(
        [
          SourceTask(externalId: "g", name: "Warm-up", projectExternalId: "p"),
          SourceTask(
            externalId: "c", name: "Scales", projectExternalId: "p", parentExternalId: "g",
            tagExternalIds: ["t-violin"]),
        ],
        projects: [
          SourceProject(externalId: "p", name: "Technique", folderPath: ["Music", "Strings"])
        ]))
    let project = try #require(ws.projects.first)
    let child = try task(ws, "c")
    #expect(child.projectID == project.id)
    #expect(child.parentTaskID == (try task(ws, "g")).id)
    #expect(child.line == .line(try #require(ws.lines.first).id))
    #expect(project.line == .lifeOps)
  }

  @Test func occurrenceFromRepeatOf() throws {
    let ws = run(
      snapshot([
        SourceTask(externalId: "live", name: "Pull-ups", status: .available),
        SourceTask(
          externalId: "live.3", name: "Pull-ups", status: .completed, completedAt: now,
          repeatOfExternalId: "live"),
      ]))
    #expect(try task(ws, "live.3").occurrenceOf == (try task(ws, "live")).id)
    #expect(try task(ws, "live").occurrenceOf == nil)
  }

  @Test func occurrenceFromIDPatternWhenRepeatOfIsMissing() throws {
    let ws = run(
      snapshot([
        SourceTask(externalId: "live", name: "Pull-ups"),
        SourceTask(externalId: "live.4", name: "Pull-ups", status: .completed, completedAt: now),
      ]))
    #expect(try task(ws, "live.4").occurrenceOf == (try task(ws, "live")).id)
  }

  @Test func dottedIDWithoutALiveTaskIsAOneOff() throws {
    let ws = run(
      snapshot([SourceTask(externalId: "v1.2", name: "Read", status: .completed, completedAt: now)])
    )
    #expect(try task(ws, "v1.2").occurrenceOf == nil)
  }

  @Test func clonedGroupChildrenAreOccurrencesUnderTheClonedGroup() throws {
    let ws = run(
      snapshot([
        SourceTask(externalId: "g", name: "Routine"),
        SourceTask(externalId: "c", name: "Step", parentExternalId: "g"),
        SourceTask(externalId: "g.2", name: "Routine", status: .completed, completedAt: now),
        SourceTask(
          externalId: "c.2", name: "Step", parentExternalId: "g.2", status: .completed,
          completedAt: now),
      ]))
    let clone = try task(ws, "c.2")
    #expect(clone.occurrenceOf == (try task(ws, "c")).id)
    #expect(clone.parentTaskID == (try task(ws, "g.2")).id)
  }

  @Test func reimportWithTheSameIdentityMapKeepsEveryID() {
    let source = snapshot(
      [SourceTask(externalId: "x", name: "A", projectExternalId: "p")],
      projects: [SourceProject(externalId: "p", name: "P")])
    var identities = IdentityMap()
    let first = run(source, identities: &identities)
    let second = run(source, identities: &identities)
    #expect(first.tasks.map(\.id) == second.tasks.map(\.id))
    #expect(first.projects.map(\.id) == second.projects.map(\.id))
    #expect(first.lines.map(\.id) == second.lines.map(\.id))
    #expect(first.artifacts.map(\.id) == second.artifacts.map(\.id))
    #expect(first.notes.map(\.id) == second.notes.map(\.id))
    #expect(first.tags.map(\.id) == second.tags.map(\.id))
  }

  @Test func artifactsResolveLinesAndNotesAndUnknownLineKeysAreReported() throws {
    let ws = run(snapshot([]))
    let partita = try #require(ws.artifacts.first { $0.key == "a26-02" })
    #expect(partita.lineIDs == [try #require(ws.lines.first).id])
    #expect(partita.noteID == ws.notes.first?.id)
    #expect(ws.issues.contains(.unknownLineKey("cello", in: "a26-09")))
  }

  @Test func refsCarryProviderAndLastSeen() throws {
    let ws = run(snapshot([SourceTask(externalId: "x", name: "A")]))
    #expect(
      try task(ws, "x").refs == [ExternalRef(provider: .omnifocus, externalId: "x", lastSeen: now)])
    #expect(
      ws.lines.first?.refs == [
        ExternalRef(provider: .obsidian, externalId: "violin", lastSeen: now)
      ])
    #expect(ws.timeZone.identifier == "Europe/Moscow")
  }
}
