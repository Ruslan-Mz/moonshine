# Phase 1 — See (2 weekends, read-only)

**Goal:** one macOS window where the owner sees everything he has to do and how his lines are moving, for today, this week and this month — fast, keyboard-first, calm. Timebox: 2 weekends; cut scope if exceeded (cut order: S6 → S5 polish → Month view).

## Views
### Today
- Available tasks with planned/defer = today, flagged, and real `due` ≤ today (only these may use the urgent colour).
- Grouped by line (emoji + name); each task shows project and trace chip (`project → line → artifact`).
- Right rail: lines touched today, "quiet lines" (active, no completion ≥ 14 days), neutral wording.

### Week
- 7 columns (Mon–Sun, ISO week), tasks by planned/defer/due date; "No plan" tray for available tasks in active lines without any date (mirrors the owner's "Без плана" perspective).
- Header: per line completions this week vs. last 4-week average (numbers, not red/green).

### Month
- Calendar grid with counts per day per line (dots/heatmap in neutral palette); click day → Today-style list for that day.
- Month plan note from Obsidian (if a note with `type: month_plan` / name `Месяц_YYYY-MM` exists) shown in a side panel, read-only.

### Lines
- One row per line from the vault, grouped by `block`, ordered active → maintenance → paused: budget h/week (from vault), 8-week completions sparkline, last activity, available next actions, planned effort (estimate, labelled as estimate).
- Line detail: parent artifact (open in Obsidian via `obsidian://open`), projects, next actions, last 10 completions.

### Global
- Sidebar: Today, Week, Month, Lines. ⌘1–⌘4. ⌘K command palette (navigate, search tasks/projects/lines/notes). ⌘R refresh.
- Every task/project opens in OmniFocus via `omnifocus:///task/<id>`; every note in Obsidian.
- Status bar: source (Demo / Live), "updated N min ago".
- Settings: vault folder (security-scoped bookmark), source Demo | Live, refresh interval.

## Slices (one PR each)
- [ ] **S1 — Core:** domain types (ARCHITECTURE.md v0 subset: Line, Artifact, Project, Task, NoteRef, ExternalRef, Horizon), ports, fixture adapters, Overview/Trace/Stats services with tests (ISO weeks, local time zone).
- [ ] **S2 — Store:** GRDB records (core columns + `attrs` JSON), numbered migrations, `changes` log table, upsert by ExternalRef, re-import idempotency test (ADR-0002). Only phase-1 entities; plan/forecast tables come in phase 2.
- [ ] **S3 — Adapters:** OmniFocus JXA bridge (`bridge/snapshot.js`) + Obsidian vault reader; measure the full live import (target ≤ 20 s, runs in the background) and an incremental refresh (only items modified since the last import) → method log. If the full import is > 20 s: stop, propose ADR.
- [ ] **S4 — App shell + Today + Lines** on the store (Demo mode first).
- [ ] **S5 — Week + Month + ⌘K palette.**
- [ ] **S6 — README (English):** vision in 3 lines, Demo-mode GIF, architecture diagram, "How this was built" → `docs/method/`, ADR index, licence.

## Acceptance
- Fresh clone → `xcodegen generate` → run → Demo mode works without OmniFocus or a vault.
- The UI always renders from the local store: any view in < 1 s, with or without a running import.
- Full background import of the live data ≤ 20 s; it never blocks the UI.
- Refreshes after the first import are incremental (items modified since the last import), not full re-reads.
- No write APIs to OmniFocus or the vault in the code.
- Tone rules in CLAUDE.md §8 pass a copy review.
