---
title: Week
status: draft-2
date: 2026-10-01
slice: S5
artboards: [mockups/Week.dc.html, mockups/Week-Dark.dc.html]
---

# Week (draft-2)

## Layout

Toolbar: `Week 40`, subtitle `28 September – 4 October 2026 · ISO week`; ‹ Today › buttons. No right rail.

1. **Line strip** (top): legend (rhythm / progress swatches, "Week in progress — Mon to Thu"), then one cell per line in a 9-column grid. Each cell shows emoji + name, `■ 4  avg 5.5` (rhythm) and `■ 1  avg 1.3` (progress). Plain numbers, no colour for up or down. "—" where a series doesn't apply (a line without repeating tasks has no rhythm).
2. **Days**: 7 equal columns Mon–Sun. Header: weekday + date (today: filled accent circle, column tinted with `selection`) + a summary (`5 done` for past days, `≈ 2 h 50 min` estimated for future days). Cards: checkbox + title (2 lines max), then line emoji + name, estimate and a due badge when the due date falls in this week. More than ~6 → `+ N more` link (opens Today-style list of that day).
3. **No plan tray** (bottom, 188 high): `No plan` + caption + count; a 4-column grid of compact cards (emoji, title, estimate). Caption on the right: "Drag onto a day to plan — phase 6".

## Data

- Placement: effective planned ?? defer ?? due. Each task appears once.
- Past days show completed tasks (checked, **dimmed**) and tasks still open from that day (resolved open question, draft-2).
- No plan: available tasks in **active** lines with no planned, defer or due date (mirrors the "Без плана" perspective).
- Strip: per line, this week's rhythm and progress vs the mean of the previous 4 ISO weeks (Stats service).

## Weekly review mode (draft-2, S5, first to cut)

The owner's Sunday review, inside Week. Toggle `Weekly review` (toolbar, ⇧⌘R). The day grid shrinks to the top half; the bottom half becomes a checklist of facts, each with "Open":

1. Quiet lines (active, ≥ 14 days) — with the suggested next step.
2. No plan tray (already on this screen).
3. Projects in active lines with **no next action** (`no next action`).
4. Next week's real due dates.
5. Links: month note, quarter note.

Each section has a "seen" circle (draft-2 mockup). Its state is **MoonShine-native** data (local store, keyed by ISO week) — not a write to OmniFocus or Obsidian, so it is allowed in phase 1. No counter (`3 of 5`), no scores, no completion percentage for the review itself.

## SwiftUI

`VStack { LineStrip; HStack(spacing: 0) { ForEach(days) { DayColumn } }; NoPlanTray }`. DayColumn = `ScrollView` + `LazyVStack`. Tray = `LazyVGrid(columns: 4 flexible)`. Use `VSplitView` if the tray should be resizable.

## Acceptance

- [ ] ISO week, Monday first, local time zone.
- [ ] Due badge only for due dates inside the week; amber only there.
- [ ] Averages shown as numbers with "avg"; no red or green, no arrows.
- [ ] Tray lists only active lines' undated available tasks.
