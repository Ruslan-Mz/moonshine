---
title: Month
status: draft-2
date: 2026-10-01
slice: S5
artboards: [mockups/Month.dc.html, mockups/Month-Dark.dc.html]
---

# Month (draft-2)

## Layout

Toolbar: month name, subtitle, ‹ Today ›. **Opens on the current month**; ⌘← / ⌘→ step months (resolved open question, draft-2). The artboard shows September only to show a full heat strip. Main: calendar + selected-day list. Right inspector 380: month plan note.

**Calendar**

- Legend row: "Dot order 🎻🎹🇮🇹🇯🇵📐🤖🔬💪👨‍👩‍👧", dot examples (1, 2+ completions), "Cell tint = all completions that day".
- Weekday header Mon–Sun, then 5–6 rows of cells (86 high, radius 8, hairline border).
- Cell: date (today = accent circle), total completions top right (or "—"), and at the bottom a **dot strip**: one 7-pt dot per non-paused line in fixed order. Dot opacity 0.45 for 1 completion, 0.9 for 2+, empty slot in `separator`.
- Cell tint: `accent` at 3 % + 1.7 % per completion, capped at 10 completions (≈ 20 %).
- Days outside the month at 55 % opacity. Future days have no dots.
- Selected day: accent 1.5 border + `selection` fill.

**Selected day** (below the calendar): `Thursday, 24 September · 7 completed · 5 lines`, then rows: check (done) · title · chip `🎻 Violin → artifact` · kind tag (`session` in rhythm colour / `task` in progress colour).

**Note inspector**: header with note icon, `Месяц_2026-09`, "read-only", "Open in Obsidian". Frontmatter as a monospaced key/value grid, then rendered markdown (headings, lists, tables).

**Draft-2 — context chips (phase 2, slot reserved now):** a cell may carry a small text chip with the day's context (`dacha`, `Riga`, `ill`) from the hours tracker's context rows (see `docs/discovery/excel-contract.md`). These later feed capacity exceptions in the forecast. Phase 1 leaves the slot empty.

## Data

- Counts per day per line from the store (completed tasks; a completed repeating group counts one session per line it touches, as in S1b).
- Tasks with the reminder tag (ADR-0017, S4 bridge) are in no day list and no count.
- Note lookup: `type: month_plan` in frontmatter, or name `Месяц_YYYY-MM`. Absent → inspector shows "No month plan note for September" with no action.

## SwiftUI

`LazyVGrid(columns: 7)` of `Button(.plain)` cells bound to `selectedDay`. Dot strip: `HStack(spacing: 3) { ForEach(lineOrder) { Circle().frame(width: 7) } }`. Note: `ScrollView { MarkdownView }`, using `AttributedString(markdown:)` or swift-markdown for tables.

## Acceptance

- [ ] Line order is the same in the legend, every cell and the sidebar.
- [ ] Neutral palette only: dots use the text colour, tint uses the accent; no per-line hues.
- [ ] Clicking a day updates the list without reloading the note.
- [ ] The note is read-only; "Open in Obsidian" uses `obsidian://open`.

## Calendar (draft-3)

Artboards: `Month-Cal`, `Month-Cal-Dark`.

- **All-day / multi-day events**: a 14 pt `AllDayBar` segment in each day cell between the date row and the dot strip; the title is in the first cell, the bar continues across the gap into the next cell.
- **Timed events**: a small outlined count next to the date (`▢ 3`, 15 pt high, hairline border). It is a number in a box — deliberately unlike the per-line activity dots, which stay at the bottom of the cell.
- **Legend** adds `▢ 3 timed events` and the all-day swatch.
- **Selected-day list**: events first (dot · time · title · calendar; `all day` rows first), then tasks. Header: `Thursday, 1 October · today · 4 events · 6 completed · 4 lines`.
- Future days show their events (the calendar knows them) but still no activity dots.

**Acceptance.**

- [ ] Event marks cannot be mistaken for activity dots (shape, position, number).
- [ ] The cell tint still means completions only; events never tint a cell.
