import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

/// The tracked fixture, read from the checkout (CLAUDE.md rule 5), not the bundled copy.
private let trackedSnapshot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("fixtures/omnifocus.snapshot.json")

/// Friday's due task of `design/demo-data.md`, the one without the `deadline` tag.
private let friday = "Book rehearsal room for November"
private let tagged = DeadlineRule(mode: .dueDateAndTag, tag: "deadline")

/// Demo through the model, with `settings`.
@MainActor private func demo(_ settings: CountingSettings = CountingSettings(nil)) throws
  -> AppModel
{
  let environment = try AppEnvironment.demo(snapshot: trackedSnapshot)
  return AppModel(isTestHost: true, settings: settings) { $0 == .demo ? environment : nil }
}

@MainActor private func overview(_ model: AppModel) throws -> Overview {
  guard case .loaded(let overview) = model.state else { throw NotLoaded() }
  return overview
}

private struct NotLoaded: Error {}

/// Friday's due badge in Week, nil when the task is not placed in the week.
private func fridayBadge(_ overview: Overview) -> Bool? {
  overview.week().days.flatMap(\.items).first { $0.task.title == friday }?.hasDueBadge
}

private func urgent(_ overview: Overview) -> Set<TaskItemID> {
  Set(overview.today().items.filter(\.isUrgent).map(\.task.id))
}

/// The deadline rule through the app (`design/screens/settings.md` § Deadlines, S4-3c-2).
@Suite(.serialized) struct DeadlineSettingTests {
  /// Today's two deadlines carry the tag (`design/screens/today.md:53`); Friday's task does not
  /// (`design/screens/week.md:48`). The change rebuilds what is shown, with no import.
  @MainActor @Test func theRuleChangesOnlyWhichDueDatesAreDeadlinesWithoutAnImport() async throws {
    let settings = CountingSettings(nil)
    let model = try demo(settings)
    await model.load()
    let before = try overview(model)
    let outcomes = model.importOutcomes
    #expect(urgent(before).count == 2)
    #expect(fridayBadge(before) == true)

    model.setDeadlineRule(tagged)
    let after = try overview(model)
    #expect(settings.ruleWrites == [tagged])
    #expect(model.deadlineRule == tagged)
    #expect(urgent(after) == urgent(before))
    #expect(fridayBadge(after) == false)
    #expect(after.today().top.map(\.task.id) == before.today().top.map(\.task.id))
    #expect(model.importOutcomes == outcomes)

    model.setDeadlineRule(.allDueDates)
    #expect(fridayBadge(try overview(model)) == true)
  }

  @MainActor @Test func anEqualRuleIsNotWrittenAgain() async throws {
    let settings = CountingSettings(nil)
    let model = try demo(settings)
    await model.load()
    model.setDeadlineRule(.allDueDates)
    #expect(settings.ruleWrites.isEmpty)
  }

  /// `reload` after an import builds with the rule, not the default.
  @MainActor @Test func theRuleSurvivesAnImport() async throws {
    let model = try demo()
    await model.load()
    model.setDeadlineRule(tagged)
    let outcomes = model.importOutcomes
    model.refresh()
    for _ in 0..<1_000 where model.importOutcomes == outcomes {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.importOutcomes > outcomes)
    #expect(fridayBadge(try overview(model)) == false)
  }

  /// `showStored` and the first import build with the stored rule.
  @MainActor @Test func aStoredRuleShowsFromTheStart() async throws {
    let settings = CountingSettings(nil)
    settings.storedRule = tagged
    let model = try demo(settings)
    await model.load()
    #expect(model.deadlineRule == tagged)
    #expect(fridayBadge(try overview(model)) == false)
  }

  /// The caption under the tag field (owner, 2026-11-25).
  @MainActor @Test func theCaptionSaysWhenNoTagHasTheName() async throws {
    let model = try demo()
    await model.load()
    let workspace = try overview(model).workspace
    #expect(DeadlineTagLine(rule: tagged, workspace: workspace) == nil)
    #expect(DeadlineTagLine(rule: .allDueDates, workspace: workspace) == nil)
    let typo = DeadlineRule(mode: .dueDateAndTag, tag: "Deadlne")
    #expect(DeadlineTagLine(rule: typo, workspace: workspace) == .notFound("Deadlne"))
    #expect(DeadlineTagLine(rule: typo, workspace: nil) == nil)
  }
}
