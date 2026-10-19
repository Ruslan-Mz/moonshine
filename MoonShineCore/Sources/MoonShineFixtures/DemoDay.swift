import Foundation
import MoonShineCore

/// The tasks with a time on Thu 1 Oct 2026 (`design/demo-data.md` § Draft-3, invented). Only
/// their times, estimates and status are canonical; flags, lines and repeats are not set. They are
/// the timed tasks of `fixtures/omnifocus.snapshot.json`; `DemoDayGoldenTests` checks that the two
/// agree.
public enum DemoDay {
  /// The snapshot's defaults: planned 09:00, due 17:00.
  public static let defaultTimes = DefaultTimes(
    timeZone: DemoCalendar.calendar.timeZone, due: TimeOfDay(hour: 17, minute: 0),
    defer: TimeOfDay(hour: 6, minute: 0), planned: TimeOfDay(hour: 9, minute: 0))

  public static let tasks: [TaskItem] = [
    task(1, "Mobility — hips & shoulders", planned: (7, 30), estimate: 15, done: (7, 50)),
    task(2, "Definitions deck — 15 cards", planned: (12, 0), estimate: 10),
    task(
      3, "Scales & arpeggios — G minor, 3 octaves", planned: (15, 0), estimate: 20, done: (15, 25)),
    task(4, "Allemande, bars 1–16 at ♩ = 60", planned: (20, 30), estimate: 45),
    task(5, "Send recital repertoire list to teacher", due: (18, 0), estimate: 10),
    task(6, "Submit workshop abstract", due: (23, 59), estimate: 30),
  ]

  private static func task(
    _ number: UInt8, _ title: String, planned: (Int, Int)? = nil, due: (Int, Int)? = nil,
    estimate: Int, done: (Int, Int)? = nil
  ) -> TaskItem {
    let plannedAt = planned.map { DemoCalendar.at(10, 1, $0.0, $0.1) }
    let dueAt = due.map { DemoCalendar.at(10, 1, $0.0, $0.1) }
    return TaskItem(
      id: TaskItemID(
        uuid: UUID(uuid: (0, 0, 0, 0, 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0xD1, number))),
      refs: [], title: title, projectID: nil, parentTaskID: nil, tagIDs: [],
      status: done == nil ? .available : .completed, flagged: false, plannedAt: plannedAt,
      deferUntil: nil, dueAt: dueAt, effectivePlannedAt: plannedAt, effectiveDeferUntil: nil,
      effectiveDueAt: dueAt, estimateMinutes: estimate,
      completedAt: done.map { DemoCalendar.at(10, 1, $0.0, $0.1) }, modifiedAt: nil,
      occurrenceOf: nil, line: .lifeOps)
  }
}
