---
title: Line detail
status: draft-1
date: 2026-10-01
slice: S4
artboards: [mockups/LineDetail.dc.html, mockups/LineDetail-Dark.dc.html]
---

# Line detail (draft-1)

Example: 🎻 Violin.

## Layout

Toolbar: breadcrumb `Lines › 🎻 Violin`, subtitle `Line detail · 4 projects · 9 next actions`, button "Open in OmniFocus" (opens the line's folder or tag perspective if possible, else the first project).

Main (scroll):

1. Header: emoji 34, name 24 bold, meta line `Creative · active · budget 6 hours / week · last activity today`.
2. Two `MetricCard`s side by side: **Rhythm** (sessions per week, 4-week avg 4.0) and **Progress** (tasks done per week, avg 1.0), W33–W40, current week partial.
3. **Projects** table: Project (folder symbol + name + due badge if the project has a real due) · Kind (`plan · 4 steps`, `repeating sessions`, `one-off tasks`) · Next actions · Remaining (`≈ 2 h 15 min est.`).
4. **Next actions** (count): `TaskRow`s; the When column shows `today` / `Fri` / `no date`, or a due badge.

Inspector 360:

- **Parent artifact** card: label, title 17 bold, description, Horizon / Target / Note path grid, button "Open in Obsidian".
- **Last 10 completions**: date (`Today`, `Wed 30 Sep`) · title · tag (`session` rhythm colour / `task` progress colour).

## Data

Line detail model (moved to S4 in the phase-1 spec): parent artifact (NoteRef), projects, next actions, last 10 completions, weekly rhythm and progress for 8 weeks plus the 4-week means.

Tasks with the reminder tag (ADR-0017, S4 bridge) are in none of these: not in next actions, completions, rhythm or progress (`today.md` § Reminders).

## Acceptance

- [ ] Two separate charts; the average is a dashed rule, not a third series.
- [ ] "Open in Obsidian" uses `obsidian://open?vault=…&file=…`.
- [ ] The kind "plan · 4 steps" appears only once plans exist (phase 2); in phase 1 show `one-off tasks` / `repeating sessions`.

## Calendar (draft-3)

Artboards: `LineDetail-Cal`, `LineDetail-Cal-Dark`. For a line with a mapped calendar (Settings → Calendars → Line), the inspector shows **Upcoming** between the artifact card and the completions: the next 3 events (`CalendarDot` · `Today 17:00` · title · `in 40 min` on the next one) and the caption `from calendar "Music lessons"`. Absent when no calendar is mapped or there is no access.

## My take (draft-4)

Artboards: `LineDetail-Take`, `LineDetail-Take-Dark`.

### Layout

- **Three metric cards**, side by side and separate: Rhythm, Progress, **My take**. The third card has no bars and no axis: title (spark mark + `My take` + `set by you · not measured`), the current week's state in words (`▷ Rise` + `draft · this week so far`, or the confirmed direction, or nothing), and one row of `TakeMark`s (16 pt, Leap 21 pt) over the same week labels W33–W40 as the other cards.
- **Take history** in the inspector, between the parent artifact and the last completions: header `My take` + filter `All | ✦ Leaps` + link `Add a note`. Rows are `TakeHistoryRow`s, newest first: `W36 · Leap — Vibrato finally works` + `set Sun 6 Sep`; a draft reads `W40 · Rise — Bars 9–16 clean at ♩ = 60` + `draft · Mon 28 Sep`. Notes wrap. Under the list: `Confirm my take for week 40…` when the week has drafts — it opens the weekly review at step 2 for that week, where takes are confirmed — or `Set my take for this week` when it has none, which opens the `TakeControl` popover and saves a **draft** (outside the weekly review nothing is confirmed).
- **Projects table** gains a column `My take` (112): the project's latest take as a chip (`✦ Leap · W36`), otherwise a quiet `+` button (`Add my take`), which opens the same control for the project.

### Data

The line's takes and draft notes for the visible weeks; project-level takes for the Projects table (`week.md` § My take · Data). The Leaps filter is a view filter, not a count.

### Behaviour

`Add a note` opens a one-line field (optional `1`–`4`), saves a dated draft on the current week and shows it at once in the card and the take history. A past draft's take-history row links to its week in the weekly review, where it can be confirmed. Opening a confirmed row shows the dated notes kept under the take.

**Re-estimate row.** After a Leap on the line, a quiet row under the metric cards: `✦ W36 · my take: Leap │ Re-estimate what is left?` with the line's projects that have plans, each with `Open estimates`, and `Not now` to dismiss (same wording as `forecast.md` § My take). Project takes drawn here are independent of the line take; how a project take is confirmed is drawn in the 3b round. A take changed after its week ended shows `set Tue 29 Sep · changed after the week ended`.

### SwiftUI

Third `MetricCard` variant without `Chart`: `HStack` of marks in the same week columns. Take history: `List` section with a segmented `Picker` for the filter. Popover: `.popover` hosting `TakeControlView`.

### Acceptance

- [ ] Three cards, three things; the take card cannot be mistaken for a chart of measured values.
- [ ] Take history for 🎻 Violin, newest first: W40 draft (Wed, no direction) · W40 draft (Mon, Rise) · W39 Steady, set Tue 29 Sep · W38 Rise · W36 Leap · W35 Rise.
- [ ] `Leaps` filter leaves only W36.
- [ ] No "N takes", no percentages.

Also fixed in this round: the 4-week averages on the Rhythm and Progress cards are `avg 4.0` and `avg 1.0` (they showed 5.5 and 1.3, which did not match `demo-data.md`).
