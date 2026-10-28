import Foundation
import MoonShineCore

/// Demo-mode vault: the frontmatter of `fixtures/vault/` as Swift values (synthetic data).
/// S3's vault reader gets a golden test against these values so the two cannot drift.
public struct DemoVault: NoteProvider {
  public static let calendar = Calendar.iso8601(in: TimeZone(identifier: "Europe/Moscow")!)

  public init() {}

  public func vault() async throws -> VaultSnapshot { Self.snapshot }

  private static let budget = "00_Strategy/Hours_budget_by_line.md"
  private static let year = "00_Strategy/Years/Artifacts_2026.md"
  private static let quarter = "00_Strategy/Years/Q4_2026_focus.md"
  private static let parent = "[[Artifacts_2026]]"

  public static let snapshot = VaultSnapshot(
    lines: .read(
      [
        SourceLine(
          key: "core", name: "Core practice", emoji: "🧘", block: "Foundation", state: .active,
          parentLink: parent, tags: ["practice"], foundation: true, floorHoursPerDay: 3),
        SourceLine(
          key: "calisthenics", name: "Calisthenics", emoji: "💪", block: "Foundation",
          state: .active, parentLink: parent, tags: ["calisthenics"], foundation: true,
          floorHoursPerDay: 1),
        SourceLine(
          key: "ai", name: "AI/ML", emoji: "🤖", block: "Profession", state: .active,
          budgetHoursPerWeek: 6, parentLink: parent,
          projects: ["Eval toolkit", "Paper reading", "Workshop 2026"]),
        SourceLine(
          key: "research", name: "Research", emoji: "🔬", block: "Profession", state: .active,
          budgetHoursPerWeek: 3, parentLink: parent, tags: ["исследование"]),
        SourceLine(
          key: "violin", name: "Violin", emoji: "🎻", block: "Creative", state: .active,
          budgetHoursPerWeek: 6, parentLink: parent, tags: ["violin"]),
        SourceLine(
          key: "piano", name: "Piano", emoji: "🎹", block: "Creative", state: .maintenance,
          budgetHoursPerWeek: 1, parentLink: parent, tags: ["piano"]),
        SourceLine(
          key: "calligraphy", name: "Calligraphy", emoji: "✒️", block: "Creative", state: .paused,
          tags: ["calligraphy"]),
        SourceLine(
          key: "italian", name: "Italian", emoji: "🇮🇹", block: "Languages", state: .active,
          budgetHoursPerWeek: 2, parentLink: parent, tags: ["italian"], language: "it"),
        SourceLine(
          key: "japanese", name: "Japanese", emoji: "🇯🇵", block: "Languages", state: .active,
          budgetHoursPerWeek: 1, parentLink: parent, tags: ["japanese"], language: "ja"),
        SourceLine(
          key: "math", name: "Math", emoji: "📐", block: "Science", state: .active,
          budgetHoursPerWeek: 4, parentLink: parent, folders: ["Study"]),
        SourceLine(
          key: "family", name: "Family", emoji: "👨‍👩‍👧", block: "Life", state: .active,
          parentLink: parent, folders: ["Family"]),
      ], complete: true),
    artifacts: [
      artifact("a26-01", "Daily practice 2026", "core", priority: true),
      artifact("a26-02", "20 strict pull-ups", "calisthenics"),
      artifact("a26-03", "Eval toolkit v1", "ai", priority: true),
      artifact("a26-04", "Practice-drift paper", "research"),
      artifact("a26-05", "Spring recital 2027", "violin", priority: true),
      artifact("a26-06", "Keep repertoire alive", "piano"),
      artifact("a26-07", "B1 by summer 2027", "italian", .planned),
      artifact("a26-08", "Kana and first 300 words", "japanese", .planned),
      artifact("a26-09", "Linear algebra foundation", "math"),
      artifact("a26-10", "Family year 2026", "family"),
      artifact("q4-01", "Spring recital programme chosen", "violin", .done, in: .quarter),
      artifact("q4-02", "Eval toolkit v1 published", "ai", in: .quarter),
      artifact("q4-03", "Practice-drift paper draft", "research", in: .quarter),
      artifact("q4-04", "Linear algebra ch. 1–4", "math", .done, in: .quarter),
      artifact("q4-05", "10 strict pull-ups", "calisthenics", in: .quarter),
    ],
    // In path order, as the vault reader returns them (its golden test compares the two).
    notes: [
      SourceNote(
        path: budget, title: "Hours budget by line", type: "strategic",
        parentLink: "[[_index]]", status: "active"),
      // `horizons: [2036, 2041, 2051]` is a list of target years; the Zoom out phase models it.
      SourceNote(
        path: "00_Strategy/Long_horizons.md", title: "Long horizons", type: "horizon_corridor",
        parentLink: "[[_index]]", status: "draft"),
      SourceNote(
        path: "00_Strategy/Months/Month_2026-10.md", title: "October 2026 — month plan",
        type: "month_plan", scale: .month, period: period(.month, 2026, 10),
        parentLink: "[[Q4_2026_focus]]", status: "active"),
      SourceNote(
        path: year, title: "Artifacts 2026", type: "year_artifacts", scale: .year,
        period: period(.year, 2026, 1), parentLink: "[[Corridor_2026-2030]]", status: "active"),
      SourceNote(
        path: "00_Strategy/Years/Corridor_2026-2030.md", title: "Corridor 2026–2030",
        type: "horizon_corridor", scale: .years(5),
        period: Horizon(
          scale: .years(5), start: date(2026, 1), end: date(2031, 1)),
        parentLink: "[[Long_horizons]]", status: "draft"),
      SourceNote(
        path: quarter, title: "Q4 2026 focus",
        type: "quarter_focus", scale: .quarter, period: period(.quarter, 2026, 10),
        parentLink: "[[Artifacts_2026]]", status: "active"),
    ], unread: .nothing)

  private enum Period { case year, quarter }

  private static func artifact(
    _ key: String, _ title: String, _ line: LineKey, _ status: ArtifactStatus = .inProgress,
    priority: Bool = false, in period: Period = .year
  ) -> SourceArtifact {
    SourceArtifact(
      key: key, periodKey: period == .year ? "2026" : "2026-Q4", title: title, lineKeys: [line],
      status: status, priority: priority, notePath: period == .year ? year : quarter)
  }

  private static func date(_ year: Int, _ month: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: 1))!
  }

  private static func period(_ scale: Scale, _ year: Int, _ month: Int) -> Horizon? {
    Horizon.containing(date(year, month), scale: scale, calendar: calendar)
  }
}
