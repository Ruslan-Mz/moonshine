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

  public static let snapshot = VaultSnapshot(
    lines: [
      SourceLine(
        key: "violin", name: "Violin", emoji: "🎻", block: "Creative", state: .active,
        budgetHoursPerWeek: 6, parentLink: "[[Artifacts_2026]]", tags: ["violin"]),
      SourceLine(
        key: "piano", name: "Piano", emoji: "🎹", block: "Creative", state: .maintenance,
        budgetHoursPerWeek: 1.25, tags: ["piano"]),
      SourceLine(
        key: "calligraphy", name: "Calligraphy", emoji: "✒️", block: "Creative", state: .paused,
        budgetHoursPerWeek: 0, tags: ["calligraphy"]),
      SourceLine(
        key: "italian", name: "Italiano", emoji: "🇮🇹", block: "Languages", state: .active,
        budgetHoursPerWeek: 2, tags: ["italian"]),
      SourceLine(
        key: "math", name: "Математика", emoji: "📐", block: "Foundation", state: .active,
        budgetHoursPerWeek: 1.5, folders: ["Study"]),
      SourceLine(
        key: "calisthenics", name: "Calisthenics", emoji: "💪", block: "Foundation",
        state: .active, budgetHoursPerWeek: 2, tags: ["calisthenics"]),
      SourceLine(
        key: "research", name: "Research", emoji: "🔬", block: "Professional", state: .active,
        budgetHoursPerWeek: 4, parentLink: "[[Artifacts_2026]]", tags: ["исследование"]),
      SourceLine(
        key: "work", name: "Client work", emoji: "💻", block: "Professional", state: .active,
        budgetHoursPerWeek: 13, folders: ["Work"]),
    ],
    artifacts: [
      SourceArtifact(
        key: "a26-01", title: "First paper draft submitted", lineKeys: ["research"],
        status: .inProgress, priority: true, notePath: year),
      SourceArtifact(
        key: "a26-02", title: "Partita first movement performed for friends",
        lineKeys: ["violin"], status: .inProgress, priority: true, notePath: year),
      SourceArtifact(
        key: "a26-03", title: "Italian B1 certificate", lineKeys: ["italian"], status: .planned,
        notePath: year),
      SourceArtifact(
        key: "a26-04", title: "10 strict pull-ups", lineKeys: ["calisthenics"],
        status: .inProgress, notePath: year),
      SourceArtifact(
        key: "a26-05", title: "Linear algebra course finished", lineKeys: ["math"],
        status: .inProgress, notePath: year),
      SourceArtifact(
        key: "a26-06", title: "Client North app v2 released", lineKeys: ["work"],
        status: .done, notePath: year),
    ],
    notes: [
      SourceNote(
        path: budget, title: "Hours budget by line", type: "strategic",
        parentLink: "[[_index]]", status: "active"),
      SourceNote(
        path: "00_Strategy/Months/Month_2026-10.md", title: "October 2026 — month plan",
        type: "month_plan", scale: .month, period: period(.month, 2026, 10),
        parentLink: "[[Q4_2026_focus]]", status: "active"),
      SourceNote(
        path: "00_Strategy/Years/Q4_2026_focus.md", title: "Q4 2026 focus",
        type: "quarter_focus", scale: .quarter, period: period(.quarter, 2026, 10),
        parentLink: "[[Artifacts_2026]]", status: "active"),
      SourceNote(
        path: year, title: "Artifacts 2026", type: "year_artifacts", scale: .year,
        period: period(.year, 2026, 1), parentLink: "[[Corridor_2026-2030]]", status: "active"),
      SourceNote(
        path: "00_Strategy/Years/Corridor_2026-2030.md", title: "Corridor 2026–2030",
        type: "horizon_corridor", scale: .years(5),
        period: Horizon(
          scale: .years(5), start: date(2026, 1), end: date(2031, 1)),
        parentLink: "[[Long_horizons]]", status: "draft"),
      // `horizons: [2036, 2041, 2051]` is a list of target years; phase 5 models it.
      SourceNote(
        path: "00_Strategy/Long_horizons.md", title: "Long horizons", type: "horizon_corridor",
        parentLink: "[[_index]]", status: "draft"),
    ])

  private static func date(_ year: Int, _ month: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: 1))!
  }

  private static func period(_ scale: Scale, _ year: Int, _ month: Int) -> Horizon? {
    Horizon.containing(date(year, month), scale: scale, calendar: calendar)
  }
}
