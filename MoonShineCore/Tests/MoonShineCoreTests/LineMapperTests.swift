import Foundation
import Testing

@testable import MoonShineCore

func makeLine(
  _ key: String, state: LineState = .active,
  tags: [String] = [], folders: [String] = [], projects: [String] = []
) -> Line {
  Line(
    id: .generate(), refs: [], key: LineKey(key), name: key.capitalized, emoji: nil,
    block: "Test", state: state, budgetHoursPerWeek: nil, parentLink: nil,
    taskRules: LineTaskRules(tags: tags, folders: folders, projects: projects))
}

@Suite struct LineMapperTests {
  let violin = makeLine("violin", tags: ["violin"])
  let piano = makeLine("piano", tags: ["piano"])
  let research = makeLine("research", projects: ["Paper draft"])
  let work = makeLine("work", folders: ["Work"])

  var mapper: LineMapper { LineMapper(lines: [violin, piano, research, work]) }

  private func project(
    _ name: String = "Some project", tags: [String] = [], folder: String? = nil
  ) -> ProjectContext {
    ProjectContext(name: name, tagNames: tags, topLevelFolder: folder)
  }

  @Test func taskTagWinsOverProjectTag() {
    let line = mapper.assign(taskTags: ["piano"], project: project(tags: ["violin"]))
    #expect(line == .line(piano.id))
  }

  @Test func projectTagAppliesWhenTaskHasNoLineTag() {
    let line = mapper.assign(taskTags: ["errand"], project: project(tags: ["violin"]))
    #expect(line == .line(violin.id))
  }

  @Test func projectNameWinsOverFolder() {
    let line = mapper.assign(taskTags: [], project: project("Paper draft", folder: "Work"))
    #expect(line == .line(research.id))
  }

  @Test func topLevelFolderIsTheLastRule() {
    let line = mapper.assign(taskTags: [], project: project("Release", folder: "Work"))
    #expect(line == .line(work.id))
  }

  @Test func noMatchGoesToLifeOps() {
    let line = mapper.assign(taskTags: ["errand"], project: project("Groceries", folder: "Home"))
    #expect(line == .lifeOps)
  }

  @Test func inboxTaskUsesOnlyItsOwnTags() {
    #expect(mapper.assign(taskTags: [], project: nil) == .lifeOps)
    #expect(mapper.assign(taskTags: ["violin"], project: nil) == .line(violin.id))
  }

  @Test func projectAssignmentUsesProjectRules() {
    #expect(mapper.assign(project: project(tags: ["piano"], folder: "Work")) == .line(piano.id))
    #expect(mapper.assign(project: project(folder: "Home")) == .lifeOps)
  }

  @Test func tagMatchIsExactAndCaseSensitive() {
    #expect(mapper.assign(taskTags: ["Violin"], project: nil) == .lifeOps)
  }

  @Test func twoLinesClaimingOneTagFirstWinsAndAnIssueNamesBoth() {
    let second = makeLine("fiddle", tags: ["violin"])
    let mapper = LineMapper(lines: [violin, second])
    #expect(mapper.assign(taskTags: ["violin"], project: nil) == .line(violin.id))
    #expect(
      mapper.issues == [.ruleClaimedTwice(rule: "tag violin", kept: "violin", ignored: "fiddle")])
  }

  @Test func pausedLinesStillMapTheirTasks() {
    let paused = makeLine("calligraphy", state: .paused, tags: ["calligraphy"])
    let mapper = LineMapper(lines: [paused])
    #expect(mapper.assign(taskTags: ["calligraphy"], project: nil) == .line(paused.id))
  }
}
