import Foundation
import MoonShineCore
import MoonShineFixtures
import Testing

@testable import OmniFocusAdapter

/// The Demo data set (fixture snapshot + `DemoVault`) gives the numbers of `design/demo-data.md`,
/// derived by Core at the snapshot's "now", Thu 1 Oct 2026 16:20 (spec, Demo data; S4-DD).
@Suite struct DemoDataGoldenTests {
  let overview: Overview

  init() async throws {
    let source = try SnapshotMapper.map(try fixtureDocument())
    var identities = IdentityMap()
    let workspace = Importer(metaTagGroups: DemoMapping.metaTagGroups).makeWorkspace(
      tasks: source, vault: DemoVault.snapshot, stored: Workspace(timeZone: .gmt),
      approvedLineRemovals: [], identities: &identities, now: source.generatedAt)
    overview = Overview(workspace: workspace, now: source.generatedAt)
  }

  func line(_ key: LineKey) throws -> Line {
    try #require(overview.workspace.lines.first { $0.key == key })
  }

  func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
    try #require(
      DemoVault.calendar.date(
        from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
  }

  /// Demo's meta groups are its own invented set: the fixture's top-level tags with children,
  /// and every tag under them is meta.
  @Test func theDemoFixtureUsesItsOwnInventedGroups() throws {
    let tags = overview.workspace.tags
    let parents = Set(tags.compactMap(\.parentID))
    let groups = tags.filter { $0.parentID == nil && parents.contains($0.id) }
    #expect(Set(groups.map(\.name)) == DemoMapping.metaTagGroups)
    #expect(tags.filter(\.isMeta).count == 4)
  }

  @Test func theClockIsTheDemoClock() {
    #expect(overview.now == DemoCalendar.now)
  }

  /// § Today: 29 tasks — 23 open, 6 done, ≈ 11 h 15 min est. (open only); § Draft-2: anchors
  /// 3 of 5 done, 5 flagged, 3 shown in Top 3.
  @Test func todayTotalsAnchorsAndTopThree() throws {
    let today = overview.today()
    #expect(today.items.count == 29)
    #expect(today.totals == TodayTotals(open: 23, done: 6, estimateMinutes: 675))
    #expect(today.anchors.count == 5)
    #expect(today.anchors.filter(\.isDone).count == 3)
    #expect(today.flaggedCount == 5)
    #expect(
      today.top.map(\.task.title) == [
        "Submit workshop abstract", "Allemande, bars 1–16 at ♩ = 60", "Chapter 3.A — exercises 1–6",
      ])
    #expect(
      today.fromEarlier.map(\.task.title) == [
        "Book dentist appointment for the kids", "Email co-author about the dataset licence",
        "Refactor tokenizer benchmark script",
      ])
    #expect(today.groups.last?.line == .lifeOps)
    #expect(today.groups.last?.items.count == 5)
    // Foundation first; 🧘's only open task, Evening session, is in the strip, so 🧘 has no
    // section and 💪 leads.
    #expect(today.groups.first?.line == .line(try line("calisthenics").id))
  }

  /// § Weekly stats W33–W40 and Draft-4's 🧘 row; where the design has `…` or `—` the count is 0,
  /// but for the 🇮🇹 and 🎹 one-offs of Wed 2 Sep (W36 progress 1; § Weekly stats note).
  @Test func eightWeeksPerLineMatchTheDesignTable() throws {
    let expected: [(LineKey, [Int], [Int])] = [
      ("core", [12, 13, 11, 9, 12, 13, 14, 8], [0, 0, 0, 0, 0, 0, 0, 0]),
      ("calisthenics", [4, 4, 3, 2, 3, 4, 4, 4], [0, 1, 0, 0, 0, 1, 0, 0]),
      ("ai", [0, 0, 0, 0, 0, 0, 0, 0], [3, 4, 2, 3, 3, 4, 2, 3]),
      ("research", [0, 0, 0, 0, 0, 0, 0, 0], [1, 2, 1, 0, 1, 2, 1, 1]),
      ("violin", [6, 5, 2, 1, 3, 6, 6, 4], [1, 2, 0, 0, 1, 2, 1, 1]),
      ("piano", [2, 1, 1, 0, 0, 0, 0, 0], [0, 0, 0, 1, 0, 0, 0, 0]),
      ("calligraphy", [0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0]),
      ("italian", [3, 2, 1, 0, 0, 0, 0, 0], [1, 1, 0, 1, 0, 0, 0, 0]),
      ("japanese", [0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0]),
      ("math", [2, 3, 2, 1, 2, 2, 3, 1], [2, 1, 2, 1, 2, 2, 1, 1]),
      ("family", [5, 6, 4, 6, 5, 5, 4, 3], [1, 0, 1, 1, 0, 2, 1, 1]),
    ]
    let rows = overview.lines().tiers.flatMap(\.rows)
    #expect(rows.count == expected.count)
    for (key, rhythm, progress) in expected {
      let row = try #require(rows.first { $0.line.key == key })
      #expect(row.activity.sparkline.map(\.week.week) == Array(33...40), "\(key)")
      #expect(row.activity.sparkline.map(\.counts.rhythm) == rhythm, "\(key)")
      #expect(row.activity.sparkline.map(\.counts.progress) == progress, "\(key)")
    }
  }

  /// Draft-4, "Measured facts" (W40 and the W36–W39 average), and the 🇮🇹 / 🎹 averages of the
  /// § Weekly stats note.
  @Test func weekFortyAgainstTheFourWeeksBefore() throws {
    let expected: [(LineKey, WeekCounts, WeekAverage)] = [
      ("core", WeekCounts(rhythm: 8), WeekAverage(rhythm: 12, progress: 0)),
      ("calisthenics", WeekCounts(rhythm: 4), WeekAverage(rhythm: 3.25, progress: 0.25)),
      ("ai", WeekCounts(progress: 3), WeekAverage(rhythm: 0, progress: 3)),
      ("research", WeekCounts(progress: 1), WeekAverage(rhythm: 0, progress: 1)),
      ("violin", WeekCounts(rhythm: 4, progress: 1), WeekAverage(rhythm: 4, progress: 1)),
      ("math", WeekCounts(rhythm: 1, progress: 1), WeekAverage(rhythm: 2, progress: 1.5)),
      ("family", WeekCounts(rhythm: 3, progress: 1), WeekAverage(rhythm: 5, progress: 1)),
      ("italian", .zero, WeekAverage(rhythm: 0, progress: 0.25)),
      ("piano", .zero, WeekAverage(rhythm: 0, progress: 0.25)),
    ]
    let header = overview.week().header
    #expect(header.count == 12)
    for (key, thisWeek, average) in expected {
      let id = try line(key).id
      let row = try #require(header.first { $0.line == .line(id) })
      #expect(row.thisWeek == thisWeek, "\(key)")
      #expect(row.previousAverage == average, "\(key)")
    }
  }

  /// § Draft-5, Lines: Last activity, Next actions and Estimated this week (S4-2a's rule; the
  /// column is the rule's output on Demo, owner 2026-11-12).
  @Test func linesMatchTheDraftFiveTable() throws {
    let since = try date(7, 6, 0)
    let expected: [(LineKey, LastActivity, Int, Int)] = [
      ("core", .today, 2, 150), ("calisthenics", .today, 2, 85), ("ai", .yesterday, 4, 205),
      ("research", .daysAgo(2), 3, 85), ("violin", .today, 9, 140),
      ("italian", .quiet(days: 29), 3, 0), ("japanese", .noCompletions(since: since), 2, 0),
      ("math", .yesterday, 5, 120), ("family", .today, 3, 20), ("piano", .daysAgo(29), 1, 0),
    ]
    let rows = overview.lines().tiers.flatMap(\.rows)
    for (key, last, nextActions, estimate) in expected {
      let row = try #require(rows.first { $0.line.key == key })
      #expect(row.activity.last == last, "\(key)")
      #expect(row.activity.nextActions == nextActions, "\(key)")
      #expect(row.activity.estimatedThisWeekMinutes == estimate, "\(key)")
    }
    // Paused, with no completed brush task in the fixture: `—`.
    let calligraphy = try #require(rows.first { $0.line.key == "calligraphy" })
    #expect(calligraphy.activity.last == .paused(last: nil))
  }

  /// § Draft-5, Lines: `11 lines · 2 foundation · 7 active · 1 maintenance · 1 paused`, by tier.
  @Test func linesTiersAndCounts() {
    let lines = overview.lines()
    #expect(
      lines.counts == LineCounts(lines: 11, foundation: 2, active: 7, maintenance: 1, paused: 1))
    #expect(
      lines.tiers.map { $0.rows.map(\.line.key.rawValue) } == [
        ["core", "calisthenics"],
        ["ai", "research", "violin", "italian", "japanese", "math", "family"],
        ["piano"], ["calligraphy"],
      ])
    #expect(lines.tiers.first?.dailyFloorHours == 4)
  }

  /// The rail: `quiet for 29 days · Last: 2 September` (owner, 2026-10-24), 🇯🇵 no completions
  /// since 6 July (S4-4c-3), ✒️ paused, and the Q4 focus, 2 of 5 done.
  @Test func theRailMatchesTheDesign() throws {
    let today = overview.today()
    #expect(today.quietLines.map(\.line.key) == ["italian", "japanese"])
    let italian = try #require(today.quietLines.first)
    guard case .quiet(let days, let last) = italian.reason else {
      Issue.record("Italian is not quiet")
      return
    }
    #expect(days == 29)
    #expect(last.title == "Lesson 14 review")
    #expect(last.completedAt == (try date(9, 2, 19)))
    #expect(italian.nextStep?.title == "Lesson 15 — passato prossimo")
    #expect(today.quietLines.last?.reason == .noActivity(since: try date(7, 6, 0)))
    #expect(today.quietLines.last?.nextStep?.title == "Hiragana row あ–お")
    #expect(today.pausedLines.map(\.key) == ["calligraphy"])
    #expect(
      today.touchedToday.map(\.counts) == [
        WeekCounts(rhythm: 1), WeekCounts(rhythm: 2), WeekCounts(rhythm: 2),
        WeekCounts(progress: 1),
      ])

    let focus = try #require(today.quarterFocus)
    #expect(focus.note.path == "00_Strategy/Years/Q4_2026_focus.md")
    #expect(
      focus.artifacts.map(\.title) == [
        "Spring recital programme chosen", "Eval toolkit v1 published",
        "Practice-drift paper draft", "Linear algebra ch. 1–4", "10 strict pull-ups",
      ])
    #expect(focus.doneCount == 2)
  }

  /// § Week 40 extras: Friday's task due 12:00 without a `deadline` tag; the no-plan tray holds
  /// the 8 undated tasks of the Week mockup that remain after Draft-5's Lines (owner, 2026-10-29).
  @Test func weekFortyExtras() throws {
    let week = overview.week()
    let friday = try #require(week.days.dropFirst(4).first)
    let rehearsal = try #require(
      friday.items.first { $0.task.title == "Book rehearsal room for November" })
    #expect(rehearsal.task.dueAt == (try date(10, 2, 12)))
    let deadline = Set(overview.workspace.tags.filter { $0.name == "deadline" }.map(\.id))
    #expect(rehearsal.task.tagIDs.allSatisfy { !deadline.contains($0) })
    #expect(
      Set(week.noPlan.map(\.task.title)) == [
        "Choose an encore piece", "Restring with the new set", "Find a problem book for ch. 4",
        "Write a one-page summary of ch. 2", "Lesson 15 — passato prossimo",
        "Podcast episode 12, with transcript", "Buy parallettes", "Photo book for 2026",
      ])
  }
}
