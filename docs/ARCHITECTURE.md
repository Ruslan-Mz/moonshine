# MoonShine — Architecture

Ports & adapters (hexagonal). The domain and the UI never know which tool the data came from.

```
                ┌──────────────────────── Apps ────────────────────────┐
                │  MoonShineMac (SwiftUI+AppKit)   MoonShineiOS (later)│
                │  MoonShineMCP (CLI, MCP server over the same API)    │
                └───────────────┬──────────────────────────────────────┘
                                │ view models / commands
┌───────────────────────────────▼──────────────────────────────────────┐
│ MoonShineCore  (pure Swift package, no UI imports, tests on Linux)   │
│  Domain:   Line · Goal · Artifact · Project · Milestone · TaskItem ·  │
│            Plan · Step · EffortLevels · Scenario · Capacity ·         │
│            TimeEntry · Measurement · ForecastSnapshot · NoteRef ·     │
│            Horizon · ExternalRef                                      │
│  Services: Overview (day…lifetime) · Trace (task→…→horizon) ·         │
│            Calibration · ForecastEngine (Monte Carlo) · Planner ·     │
│            Stats · CommandBus (+ change/undo log)                     │
│  Assistant: ToolRegistry (typed tools over Services) · Conversation   │
│  Ports:    TaskProvider · NoteProvider · AIProvider · TimeSource ·    │
│            Importer · Store                                           │
└──────┬──────────────┬──────────────┬──────────────┬──────────────────┘
       │              │              │              │
 OmniFocusAdapter ObsidianAdapter  ClaudeAdapter   ExcelImporter   SQLiteStore (GRDB)
 (JXA now; plug-in (vault folder,  (Messages API,  (xlsx/csv →    (local cache +
  export for       frontmatter)    tool use)       TimeEntry)      native data)
  sandbox later)                   FoundationModels
                                   Adapter (later)
 NativeTaskProvider / MarkdownNotesProvider — phase 7, same ports
```

## Domain model (v0, will evolve through ADRs)

| Entity              | Key fields                                                                                                                          | Source today                                                                              |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Horizon`           | scale (`day…year, years(n), lifetime`), start, end                                                                                  | computed from settings (birth date, lifetime length)                                      |
| `Line`              | id, name, emoji, block, state (`active/maintenance/paused`), budget h/week                                                          | Obsidian budget note frontmatter                                                          |
| `Artifact` / `Goal` | title, horizon, target period, parent, line, status                                                                                 | Obsidian notes (year artifacts, quarter focus)                                            |
| `Project`           | title, line, artifact?, milestones, status                                                                                          | OmniFocus projects (mapped by tag/folder)                                                 |
| `TaskItem`          | title, project?, line?, planned/defer/due, estimate, status, completedAt                                                            | OmniFocus tasks                                                                           |
| `Plan`              | project, steps (DAG), template?                                                                                                     | MoonShine native                                                                          |
| `Step`              | criterion (`effort`/`sessions`/`quantity`/`metric`/`checkpoint`), 3-point estimate, prerequisites, minDuration, maxRate, status     | MoonShine native (may link to an OmniFocus task)                                          |
| `EffortLevels`      | project, min / normal / max (h/week or sessions/week), unit                                                                         | native; initial normal from vault budget                                                  |
| `Capacity`          | weekly hours for lines, exceptions (trips, illness)                                                                                 | native; seeded from vault budget / month plan                                             |
| `Scenario`          | name, level or value per project, pinned target dates                                                                               | native                                                                                    |
| `TimeEntry`         | line/project/step, start, duration, source                                                                                          | quick log, OmniFocus completions × estimate, Excel import                                 |
| `Measurement`       | step/metric, value, unit, date                                                                                                      | quick log, import                                                                         |
| `ForecastSnapshot`  | project/step, takenAt, p10 / p50 / p90, mode, inputs hash                                                                           | computed weekly, stored                                                                   |
| `NoteRef`           | path/uri, title, frontmatter                                                                                                        | Obsidian                                                                                  |
| `ExternalRef`       | provider, externalId, lastSeen                                                                                                      | on every imported entity                                                                  |
| `Take`              | subject (a line; optionally a project), ISO week, direction (`leap/rise/steady/dip`), dated notes, state (`draft/confirmed`), setAt | native, set only by the owner; synced (ADR-0010); never written to OmniFocus or the vault |
| `Capture`           | text as dictated, device, time, state (`new/interpreted/closed`)                                                                    | native, saved before any network call (ADR-0013)                                          |
| `Proposal`          | source capture, summary, commands with previews, impact, alternatives, state                                                        | native, made by the assistant (ADR-0013)                                                  |
| `Command`           | typed change, target ids, parameters, autonomy class (`auto/confirm`), origin, state, undo data                                     | native; executed by the `CommandBus` (ADR-0013)                                           |

**Identity:** every entity has a MoonShine `UUIDv7` id plus zero or more `ExternalRef`s. Swapping OmniFocus for another provider re-links refs; ids and history (time entries, forecasts) survive.

## Key flows

- **Sync-in (phase 1):** providers produce snapshots → `Store` upserts by `ExternalRef` → Services read only from `Store`. Completed tasks outlive the import window; other missing items are soft-deleted (ADR-0002). Imports are single-flight per service, and a commit names the store version its identity map was read at (stale → `IdentityConflict`). UI is fast and works offline; providers refresh on launch / ⌘R / timer.
- **Commands (phase 2 for native data; the Act phase for providers):** UI or assistant emits `Command` (e.g. `LogTime`, `AddTakeNote`; later `CompleteTask(id)`) → `CommandBus` → every command lands in the activity log with undo. Phase 2 introduces the bus for MoonShine-native writes (time entries, takes, capacity exceptions). In the Act phase the bus checks provider **capabilities** → adapter executes → Store refreshed; a provider command created on another device is queued and executed by the Mac (ADR-0013).
- **Take (phase 2):** the owner's judgement of a line's week. Rhythm, progress and take are three tracks, never summed; a take does not change forecasts.
- **Forecast (phase 2–3):** evidence → Calibration (bias, adherence per line) → ForecastEngine simulates the scenario over Capacity → bands per step/project → Planner view models; weekly job stores ForecastSnapshots.
- **Assistant (phase 4):** conversation → `AIProvider` with tool schemas from `ToolRegistry` → read tools execute immediately; write tools return a _proposal_ (a `Command` preview) the user confirms. From phase 4 a voice `Capture` becomes `auto` commands on native data (applied at once) or a `Proposal` the owner confirms; provider changes in a proposal are shown as a checklist with deep links until the Act phase (ADR-0013).

## Module / folder layout

```
MoonShineCore/        SwiftPM: Domain, Services, Assistant, Ports, Fixtures
Adapters/             SwiftPM targets per adapter (OmniFocus, Obsidian, Claude, Excel, SQLite)
Apps/Mac/             SwiftUI app (XcodeGen project.yml)
Apps/MCP/             swift executable exposing ToolRegistry as MCP server
bridge/               Omni Automation JS for the OmniFocus adapter
fixtures/             synthetic data only
docs/                 VISION, ROADMAP, ARCHITECTURE, adr/, specs/, method/
```
