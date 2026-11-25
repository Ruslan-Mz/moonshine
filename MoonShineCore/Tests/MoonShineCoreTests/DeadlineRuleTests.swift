import Foundation
import Testing

@testable import MoonShineCore

/// The deadline rule (`docs/specs/phase-1-see.md` § Deadline rule), on invented data.
@Suite struct DeadlineRuleTests {
  typealias W = TestWorld
  /// Wednesday of ISO week 40.
  let now = W.date(2026, 9, 30)
  static let tagged = DeadlineRule(mode: .dueDateAndTag, tag: "deadline")

  func urgent(_ world: W, _ rule: DeadlineRule = Self.tagged) -> Set<String> {
    let today = Overview(workspace: world.workspace, now: now, deadlineRule: rule).today()
    return Set(today.items.filter(\.isUrgent).map(\.task.title))
  }

  // MARK: The tag

  @Test func anEmptyOrBlankTagRevertsToDeadline() {
    #expect(DeadlineRule(mode: .dueDateAndTag, tag: "").tag == "deadline")
    #expect(DeadlineRule(mode: .dueDateAndTag, tag: "  \n").tag == "deadline")
    #expect(DeadlineRule(mode: .allDueDates, tag: " ").tag == "deadline")
  }

  @Test func theTagIsTrimmedAndKeepsItsSpelling() {
    #expect(DeadlineRule(mode: .dueDateAndTag, tag: " Deadline ").tag == "Deadline")
    #expect(DeadlineRule(mode: .allDueDates, tag: "Hard").tag == "Hard")
  }

  @Test func theStoredModeNamesArePinned() {
    #expect(DeadlineRule.Mode.allDueDates.rawValue == "allDueDates")
    #expect(DeadlineRule.Mode.dueDateAndTag.rawValue == "dueDateAndTag")
    #expect(DeadlineRule.allDueDates == DeadlineRule(mode: .allDueDates, tag: "deadline"))
  }

  /// The Settings caption's fact (owner, 2026-11-25): no tag of the workspace has the name.
  @Test func aTagNoTagOfTheWorkspaceHasIsNotFound() {
    var world = W()
    world.tag("Work")
    world.tag("Deadline")
    let found = { (mode: DeadlineRule.Mode, tag: String) in
      DeadlineRule(mode: mode, tag: tag).tagFound(in: world.workspace)
    }
    #expect(found(.dueDateAndTag, "deadline"))
    #expect(!found(.dueDateAndTag, "Deadlne"))
    #expect(!found(.dueDateAndTag, "Work : Deadline"))
    #expect(found(.allDueDates, "Deadlne"))
  }

  @Test func noMatchingTagMeansNoDeadline() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Due", line: violin, due: W.date(2026, 9, 30, 18))
    #expect(Self.tagged.deadlineTasks(in: world.workspace) == [])
    #expect(urgent(world).isEmpty)
  }

  // MARK: All due dates

  @Test func underAllDueDatesEveryDueDateIsADeadline() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Due today", line: violin, due: W.date(2026, 9, 30, 18))
    world.task("Due yesterday", line: violin, due: W.date(2026, 9, 29, 18))
    world.task("Flagged", line: violin, flagged: true)
    #expect(DeadlineRule.allDueDates.deadlineTasks(in: world.workspace) == nil)
    #expect(urgent(world, .allDueDates) == ["Due today", "Due yesterday"])
  }

  // MARK: Due date + tag

  @Test func theTagCountsOnTheTaskAParentAGrandparentOrTheProject() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let deadline = world.tag("deadline").id
    let other = world.tag("errand").id
    let due = W.date(2026, 9, 30, 18)
    world.task("Own tag", line: violin, due: due, tags: [deadline])
    let group = world.task("Group", line: violin, tags: [deadline])
    let middle = world.task("Middle", line: violin, parent: group.id)
    world.task("Child", line: violin, parent: group.id, inheritedDue: due)
    world.task("Grandchild", line: violin, parent: middle.id, inheritedDue: due)
    let project = world.project("Recital", line: violin, tags: [deadline])
    world.task("In project", line: violin, project: project.id, inheritedDue: due)
    world.task("Other tag", line: violin, due: due, tags: [other])
    world.task("No tag", line: violin, due: due)
    world.task("Tag, no due", line: violin, flagged: true, tags: [deadline])
    #expect(urgent(world) == ["Own tag", "Child", "Grandchild", "In project"])
  }

  @Test func theLeafNameMatchesUnderAGroupWithCaseIgnored() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let work = world.tag("Work").id
    let leaf = world.tag(" Deadline ", parent: work).id
    world.task("Under a group", line: violin, due: W.date(2026, 9, 30, 18), tags: [leaf])
    world.task("Group only", line: violin, due: W.date(2026, 9, 30, 18), tags: [work])
    let upper = DeadlineRule(mode: .dueDateAndTag, tag: "DEADLINE")
    #expect(urgent(world, upper) == ["Under a group"])
  }

  @Test func aCyclicOrBrokenParentChainEnds() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let deadline = world.tag("deadline").id
    let due = W.date(2026, 9, 30, 18)
    // A damaged store: A's parent is B, B's parent is A; C's parent is not in the workspace.
    let a = TaskItemID.generate()
    let b = TaskItemID.generate()
    for (id, parent, title) in [(a, b, "A"), (b, a, "B")] {
      world.workspace.tasks.append(
        TaskItem(
          id: id, refs: [], title: title, projectID: nil, parentTaskID: parent, tagIDs: [],
          status: .available, flagged: false, plannedAt: nil, deferUntil: nil, dueAt: due,
          effectivePlannedAt: nil, effectiveDeferUntil: nil, effectiveDueAt: due,
          estimateMinutes: nil, completedAt: nil, modifiedAt: nil, occurrenceOf: nil,
          line: violin))
    }
    world.task("C", line: violin, parent: .generate(), due: due)
    world.task("Tagged", line: violin, due: due, tags: [deadline])
    #expect(urgent(world) == ["Tagged"])
  }

  // MARK: The flags

  @Test func weeksDueBadgeFollowsTheRule() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    let deadline = world.tag("deadline").id
    world.task("Tagged Friday", line: violin, due: W.date(2026, 10, 2, 12), tags: [deadline])
    world.task("Untagged Friday", line: violin, due: W.date(2026, 10, 2, 12))
    func badges(_ rule: DeadlineRule) -> [String: Bool] {
      let items = Overview(workspace: world.workspace, now: now, deadlineRule: rule).week().days
        .flatMap(\.items)
      return Dictionary(uniqueKeysWithValues: items.map { ($0.task.title, $0.hasDueBadge) })
    }
    #expect(badges(.allDueDates) == ["Tagged Friday": true, "Untagged Friday": true])
    #expect(badges(Self.tagged) == ["Tagged Friday": true, "Untagged Friday": false])
  }

  @Test func lineDetailsUrgencyFollowsTheRule() throws {
    var world = W()
    let line = world.line("violin")
    let violin = LineAssignment.line(line.id)
    let deadline = world.tag("deadline").id
    world.task("Tagged", line: violin, due: W.date(2026, 9, 30, 18), tags: [deadline])
    world.task("Untagged", line: violin, due: W.date(2026, 9, 30, 18))
    func urgent(_ rule: DeadlineRule) throws -> Set<String> {
      let detail = try #require(
        Overview(workspace: world.workspace, now: now, deadlineRule: rule).lineDetail(line.id))
      return Set(detail.nextActions.filter(\.isUrgent).map(\.task.title))
    }
    #expect(try urgent(.allDueDates) == ["Tagged", "Untagged"])
    #expect(try urgent(Self.tagged) == ["Tagged"])
  }

  @Test func topThreesOrderDoesNotFollowTheRule() {
    var world = W()
    let violin = LineAssignment.line(world.line("violin").id)
    world.task("Flagged", line: violin, flagged: true)
    world.task("Flagged, due", line: violin, flagged: true, due: W.date(2026, 9, 30, 18))
    for rule in [DeadlineRule.allDueDates, Self.tagged] {
      let top = Overview(workspace: world.workspace, now: now, deadlineRule: rule).today().top
      #expect(top.map(\.task.title) == ["Flagged, due", "Flagged"])
    }
  }
}
