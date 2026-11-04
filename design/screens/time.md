---
title: Time — the day by the clock and the week table
status: draft-5
date: 2026-10-28
slice: Time view, phase 2 slices P2-RV, X5 and TM5 (docs/specs/phase-2-plan.md; ADR-0016)
artboards:
  [mockups/TimeDay.dc.html, mockups/TimeWeek.dc.html, "+ -Dark variants"]
related:
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[timer-mac]]"
  - "[[today]]"
---

# Time (draft-5)

The evening and week view of ADR-0016 § The day by the clock: what the day actually was, interval by interval, next to the calendar and the planned tasks, with editing; and the week as a table of lines by days, which reads like the workbook's grid. A sidebar view **Time** (⌘6; ⌘5 stays reserved for Plan; owner, 2026-10-28) with two modes, `Day | Week`.

Both modes count by ADR-0016: a line's time is the full duration of its own entries; the day's clock time is the union of all intervals; **in parallel** = tracked − by the clock. Every place a day total appears names which one it is.

## Day (`TimeDay`, 21:40 on Thu 1 Oct)

### Layout

- **Toolbar:** `Time`, subtitle `Thursday, 1 October · Tracked 21 h 25 min · by the clock 21 h 10 min · in parallel 15 min`; `Day | Week` (⌃⌘1 / ⌃⌘2); `‹ Today ›` (⌘← / ⌘→ step a day; View ▸ Go to Today); search.
- **Balance strip** (52): `since 06:40 · 15 h` · the `DayBalance` bar (220 wide) · `Work 6 h 44 min` · `Everything else 7 h 46 min` · `Not tracked 30 min` · `36 intervals` on the right.
- **Timeline.** It spans from the earlier of the day window's start and the end of the night's Sleep, rounded down to the hour, to the later of the window's end and now, rounded up: 06:00–22:00 on the demo day. 42 pt per hour at 1×; ⌘+ and ⌘− step 1× · 2× · 4×. Tracked time before the span is one pinned row (`00:00–06:00 · 😴 Sleep · 6 h`); plan items outside it are pinned rows as on the Day rail (`Due 23:59 Submit workshop abstract 🤖`).
- **Lanes:** hours 44 · **Plan** 290: events and timed tasks exactly as the Day rail draws them (`components.md` § Day rail marks) · **Tracked** 360 · **Day marks** (the rest).
- **Tracked blocks** (`TrackedBlock`): work in `workSegment`, everything else in `loadSegment`; up to three sub-lanes where sessions ran in parallel (the 08:15–08:30 📐 Math beside 🚌 Transport). Label: emoji, name and duration at 24 pt or more; emoji and duration from 11 pt; nothing below (tooltip). Running: 1.5 pt accent outline, growing with "now". Selected: 2 pt accent outline and two edge handles. Edited: a small pencil glyph. Confirmed from a calendar event: a calendar glyph. Marked (§ Check mark of `timer-mac.md`): dashed outline and `clock.badge.questionmark`.
- **Not tracked:** gaps between the end of the night's Sleep and now are hatched in the Tracked lane (12:40–13:00, 16:55–17:00, 18:25–18:30).
- **Day marks lane:** a flag where a floor or a day portion was reached: `🎻 1 h is in · 17:40` (20 min at 15:20 plus 40 min of the 17:00 lesson). A mark not reached draws nothing: never "missed" (ADR-0016).
- **Now** rule in accent with `now 21:40`.

### A day full of short switches

The owner switches constantly; the demo day has 15 intervals between 10:00 and 12:40, 5 to 18 minutes each. At 42 pt per hour a 5-minute interval is 3.5 pt: drawn one by one they would be a stripe of slivers with no labels.

- **Cluster rule:** a run of 3 or more consecutive intervals, each shorter than 20 min, with gaps under 5 min and no parallel session, is drawn as **one block** (`SwitchCluster`): one slice per interval with 1 pt between them, in its work or everything-else fill, and one label on a card chip: the subjects' emoji by share (`🤖 🔬 📥`) and `15 intervals`. The same rule makes the cluster on Today's rail.
- **Selecting the cluster** (click, or ↑↓ onto it) lists its intervals in the inspector, each editable. At 4× the cluster dissolves into separate blocks once every member is at least 11 pt high.
- **Not judged.** The count is a fact; there is no "fragmented" or "focus score", no colour for switching, and no longest-stretch figure in phase 2.
- In the **week table** short switches do not show at all: cells are sums. The `Intervals` row counts them per day.

### Inspector (340)

- **Selected cluster:** `10:00–12:40` · `2 h 40 min · 15 intervals` · the shares (`🤖 AI/ML 1 h 38 min · 🔬 Research 51 min · 📥 Inbox 11 min`) · one row per interval (time range · emoji · subject · minutes). The selected row opens an editor under it.
- **Selected interval:** Start and End fields (↑↓ step 5 min, typing allowed), `For` (the palette's subjects; nested lines are not offered, ADR-0019), Note, `Split…`, `Delete`, and a source line (`timer · session 10:35`).
- **Not tracked:** the day's gaps, each with `Fill…`, which opens a manual entry with the gap's bounds. `Fill…` arrives with the slice that builds `manual` entries, not in phase 2 (`docs/specs/phase-2-plan.md` § Non-goals).
- **Nothing selected:** the full `DayBalance` (as Today's card).
- Key hints: `↑↓ interval · ↩ edit · ⌫ delete · ⌘Z undo · ⌘+ ⌘− scale`.

### Editing

- Commands of ADR-0016, each undoable with ⌘Z: `EditTimeEntry` (fields, edge drag), `SplitTimeEntry`, `DeleteTimeEntry` (TM5); `LogTime` (`Fill…`) with the slice that builds `manual` entries, after phase 2.
- Edge drag snaps to 5 min; ⌥ drags by the minute.
- **An edit never overlaps silently** (ADR-0016): `New end 15:30 overlaps 🎻 Violin 15:20–15:40 by 10 min.` · `Trim 🎻 Violin to 15:30–15:40` · `Cancel` (`TimerStates`).
- Deleting leaves a gap; from the slice that builds `manual` entries, `Fill…` gives it to a neighbour or a new subject.

## Week (`TimeWeek`, week 40 so far)

### Layout

- **Toolbar:** subtitle `Week 40 · 28 Sep – 4 Oct · so far · Tracked 90 h 45 min · by the clock 90 h · in parallel 45 min`; `Day | Week`; `‹ This week ›`.
- **Table** (`TimeCell`): Line 184 · one column per day 64 · Week 92 · Budget 140. Rows 22, grouped by tier (Foundation · Active this season · Maintenance), then **Life ops** with one row per category that has time this week. Cells are `h:mm`, tabular, right-aligned; empty when zero. Today's column is headed `Thu 1 · so far` on the `track` fill (a running period, `principles.md` § Charts). Future days are empty.
- **Week** column: the line's total, `21 h 40 min`. **Budget** column: only numbers the owner set (CLAUDE.md rule 8): `6 h / week`, `floor 3 h/day`, `4 h / week · floor 20 min/day`. The two columns are never joined by a word, a colour or a bar; the owner compares them.
- **Work row** (after the groups): the work lines' sum per day with the `workSegment` swatch, `Work 🤖 🔬`.
- **Totals:** Tracked · By the clock · In parallel · Not tracked (the day so far minus by the clock) · Intervals; and under them one line of definitions.
- Nested lines have no row: their time is on the parent (ADR-0019). A paused line appears only when it has time that week.

### Two sources (ADR-0016)

- A cell whose (day, line) has native and workbook entries that differ by more than the tolerance carries a small `square.on.square` glyph. MoonShine's total is the one counted until the owner chooses; the two are never added.
- **Selecting the cell** shows, in the inspector: the totals of both (`MoonShine (timer) 5 h 40 min` · `Workbook 6 h`), the sentence `They differ by 20 min, more than the 10-min tolerance. MoonShine’s 5 h 40 min is counted until you choose; the two are never added.`, and the choices: `Keep MoonShine` · `Keep the workbook` · `Keep both — different sessions` · `The workbook’s total is right (+20 min)` (offered only when the workbook's total is larger).
- The toolbar shows `Two sources · N` while any pair is open; it steps through them (the reconcile list of ADR-0016).
- This choice ships in its own slice, **Time reconcile**, right after Timer (Mac) (owner, 2026-10-28; `docs/ROADMAP.md`, ADR-0016 amendment 2026-10-28). Until then the cell mark shows and MoonShine's total counts; the choices are not offered.

### Inspector (300)

The selected cell: `🤖 AI/ML · Mon 28 Sep`, `5 h 40 min · 9 intervals · timer`, then by project and task (`Eval toolkit 3 h 10 min`, under it `Eval harness — deterministic seeds 2 h 25 min`; `Paper reading 1 h`; `the line only 1 h 30 min`), then Two sources when the cell has them. Keys: `↑↓←→ cell · ↩ open the day · ⌘← ⌘→ week · ⌘Z undo`.

## Narrow windows

`principles.md`: the window must work at 1100 × 700; the inspector stays shown and hides with ⌃⌘I (owner, 2026-10-27), and columns truncate.

- **Week:** the day columns shrink from 64 to 52, Week from 92 to 80, Budget from 140 to 90 (tail truncation, the full text in a tooltip), Line from 184 to 140: 674 in all. At 1100 × 700 with the inspector hidden (864 for the table) every column shows; with it shown (564) the Line column stays pinned and the day columns scroll sideways.
- **Day:** the Plan lane shrinks from 290 to 180 and the Tracked lane from 360 to 220; Day marks become a glyph with the text in a tooltip. That is 512 with the hours and padding, so it fits at 1100 × 700 with the inspector shown (524).
- Nothing is dropped and no text changes; cells keep `h:mm`.

## Data

- Entries of the shown day or week (`TimeEntry`), sessions still running, events and timed tasks of the day (as the Day rail), floors and day portions (ADR-0016 § Nudges).
- Day boundaries: local days; an interval across midnight is split at stop (ADR-0016), so the night's Sleep is two entries.
- Tracked, by the clock, in parallel and not tracked are computed in Core; the view only displays them.

## SwiftUI

Day: a `ScrollView` with a fixed-height `ZStack` timeline, blocks placed with `.offset(y:)` from minutes (as `DayRail`), `TimelineView(.everyMinute)` for "now" and the running block; the inspector is `.inspector`. Week: `Grid` (not `Table`: the cells are uniform and the column count is fixed), `.monospacedDigit()`.

## Acceptance

- [ ] Every number on both artboards derives from `design/demo-data.md` § Draft-5 (`Tracked 21 h 25 min · by the clock 21 h 10 min · in parallel 15 min` on Thursday; `90 h 45 min · 90 h · 45 min` for the week so far).
- [ ] The 10:00–12:40 run is one cluster with `15 intervals`; selecting it lists 15 rows; at 4× it shows separate blocks.
- [ ] An edit that would overlap a neighbour offers trim or cancel and changes nothing until chosen; every edit undoes with ⌘Z.
- [ ] A day mark that was not reached draws nothing; no red, no "missed", no score for switching.
- [ ] The week table puts no word, colour or bar between the Week and Budget columns.
- [ ] A two-sources cell counts MoonShine's total until a choice; "The workbook’s total is right" appears only when the workbook's total is larger.
- [ ] Nested lines have no row; their time is in the parent's row.
- [ ] Checked in Russian at 1440 × 900 and 1100 × 700 (`h:mm` cells do not change length): at 1100 × 700 with the inspector hidden every week column shows; with it shown, the Line column stays pinned while the days scroll.
