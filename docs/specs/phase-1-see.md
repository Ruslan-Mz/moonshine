# Phase 1 — See (2 weekends, read-only)

**Goal:** one macOS window where the owner sees everything he has to do and how his lines are moving, for today, this week and this month — fast, keyboard-first, calm. Timebox: 2 weekends; cut scope if exceeded (cut order: S6 → S5 polish → Month view).

## Views

### Today

- Available tasks with planned/defer = today, flagged, and real `due` ≤ today (only these may use the urgent colour).
- Grouped by line (emoji + name); each task shows project and trace chip (`project → line → artifact`).
- **From earlier:** available tasks planned on an earlier day, in their own section with the planned age ("planned 3 days ago"); urgent only with a real `due` (decision 2026-09-30).
- Right rail: lines touched today, "quiet lines" (active, no completion ≥ 14 days), neutral wording. An active line with no completions at all is "no activity yet", not quiet.

### Week

- 7 columns (Mon–Sun, ISO week); each task appears once, on its planned date, else defer date, else due date; a due date inside the same week adds a due badge on the item; "No plan" tray for available tasks in active lines without any date (mirrors the owner's "Без плана" perspective).
- Header: per line completions this week vs. last 4-week average (numbers, not red/green).

### Month

- Calendar grid with counts per day per line (dots/heatmap in neutral palette); click day → Today-style list for that day.
- Month plan note from Obsidian (if a note with `type: month_plan` / name `Месяц_YYYY-MM` exists) shown in a side panel, read-only.

### Lines

- One row per line from the vault, grouped by `block`, ordered active → maintenance → paused: budget h/week (from vault), 8-week completions sparkline (current week marked partial), last activity, available next actions, planned effort (estimate, labelled as estimate).
- Line detail: parent artifact (open in Obsidian via `obsidian://open`), projects, next actions, last 10 completions.

### Global

- Sidebar: Today, Week, Month, Lines. ⌘1–⌘4. ⌘K command palette (navigate, search tasks/projects/lines/notes). ⌘R refresh.
- Every task/project opens in OmniFocus via `omnifocus:///task/<id>`; every note in Obsidian.
- Status bar: source (Demo / Live), "updated N min ago".
- Settings: vault folder (security-scoped bookmark), source Demo | Live, refresh interval.
- Demo mode runs with a frozen clock at 2026-10-01 (Thursday, ISO week 40, local time zone), so it renders like `design/demo-data.md` and the mockups. Live mode uses the system clock.

## Slices (one PR each)

- [x] **S1a — Core model:** domain types (ARCHITECTURE.md v0 subset: Line, Artifact, Project, TaskItem, Tag, NoteRef, ExternalRef, Horizon; UUIDv7 ids), ports (TaskProvider, NoteProvider, Store), identity map, line mapping (task tag → project tag → project name → top-level folder → Life ops), importer (repeat occurrences), OmniFocus snapshot decoder + contract validator, fixture adapters (Demo vault, in-memory store), with tests (ISO weeks, local time zone).
- [x] **S1b — Core services:** Overview (Today, Week, Lines)/Trace/Stats (rhythm and progress per line per ISO week) with tests. The Month overview model comes with the Month view in S5. A completed repeating group counts one session per line it touches (its own line and each other line of its completed children).
- [x] **CI:** GitHub Actions on pull requests and pushes to `main` (macos-latest, newest stable Xcode): Core and Adapter tests, `swift format lint --strict`, `prettier --check` on Markdown; `.build` cached. README carries the CI badge.
- [x] **S2 — Store:** GRDB records (core columns + `attrs` JSON), numbered migrations, `changes` log table, upsert by ExternalRef, re-import idempotency test (ADR-0002). Only phase-1 entities; plan/forecast tables come in phase 2. Retention (decision 2026-10-01): completed tasks are never removed by an import; anything else missing is soft-deleted (`removed_at`) and restored with its id when it reappears. Effective date columns exist (NULL until S3); one shared contract suite runs against both stores.
- [ ] **S3a — OmniFocus bridge:** JXA bridge (`bridge/snapshot.js`); measure the full live import (target ≤ 20 s, runs in the background) and an incremental refresh (only items modified since the last import) → method log. If the full import is > 20 s: stop, propose ADR. **Required:** the bridge exports `effectiveDeferDate` / `effectiveDueDate` / `effectivePlannedDate` (snapshot contract), `TaskItem` carries them, and Today/Week placement and urgency use the effective dates (an inherited project due date is a real due date).
- [ ] **S3b — Obsidian vault reader:** golden test: its output on `fixtures/vault/` equals `DemoVault`. Vault contract additions (draft-2 design, all optional, absent = today's behaviour): in the budget note's `lines:` block, `foundation: true` and `floor_h_day: <number ≥ 0>` (a foundation line has a floor instead of `budget_h_week`); a quarter note with `scale: quarter` and an `artifacts:` list (same shape as the year note) feeds the Quarter focus card; quarter-note `artifacts:` items take optional `done: <date>` and `carried_to: <YYYY-Qn>` (quarterly review outcome, R1); the budget note takes optional `active_lines: {min, max}` (the "3–5 active lines" rule as data; absent = no such row).
- [ ] **Demo data (before S4):** align `fixtures/` and `DemoVault` with `design/demo-data.md`, including its "Draft-2 additions": foundation lines with a floor (🧘 Core practice, 💪 Calisthenics), `anchor`-tagged tasks, flagged tasks, and the Q4 quarter note with its artifacts. Invented data only.
- [ ] **S4 — App shell + Today + Lines** on the store (Demo mode first), including the Line detail model (moved from S1b). Follows `design/screens/` (today, lines, line-detail, settings); where a screen spec and its mockup differ, the screen spec wins.
- [ ] **S5 — Week + Month + ⌘K palette.** Follows `design/screens/` (week, month, command-palette); where a screen spec and its mockup differ, the screen spec wins.
- [ ] **S6 — README (English):** vision in 3 lines, Demo-mode GIF, architecture diagram, "How this was built" → `docs/method/`, ADR index, licence.

## Acceptance

- Fresh clone → `xcodegen generate` → run → Demo mode works without OmniFocus or a vault.
- The UI always renders from the local store: any view in < 1 s, with or without a running import.
- Full background import of the live data ≤ 20 s; it never blocks the UI.
- Refreshes after the first import are incremental (items modified since the last import), not full re-reads.
- No write APIs to OmniFocus or the vault in the code.
- Tone rules in CLAUDE.md §8 pass a copy review.
- S4 and S5 pass the **Acceptance** checklist of each matching `design/screens/*.md`, in English and in Russian.
