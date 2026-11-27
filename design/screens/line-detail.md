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

Toolbar: breadcrumb `Lines › 🎻 Violin`, subtitle `Line detail · 4 projects · 9 next actions`, button "Open in OmniFocus" (opens the line's folder or tag perspective if possible, else the first project). As built in S4-5 (owner, 2026-11-25): it opens the line's first project in Projects order, `omnifocus:///project/<id>`, and is disabled when the line has none. Its menu command, Open in OmniFocus with ⌘↵ beside Refresh (⌘R), opens the same project and is enabled only here (owner, 2026-11-26; ⌘↵ opens in the other app everywhere, `design/principles.md`). OmniFocus's Copy as Link also has `omnifocus:///folder/<id>` (checked by the owner, 2026-11-25), but opening a folder-mapped line's folder waits for the usage period: it needs folder ids in the store (it keeps only `folderPath`), an ADR-0015 amendment adding `omnifocus:///folder/<id>` to the allowlist, and its tests; a folder often holds several lines (`docs/discovery/snapshot-contract.md:162-164`, rule 4). A tag perspective has no URL on the allowlist.

Main (scroll):

1. Header: emoji 34, name 24 bold, meta line on one line `Creative · active · 6 h / week · last activity today`. A budget with a floor stays on one line, the floor after the budget: `Science · active · 4 h / week · floor 20 min/day · last activity today` (the two-row budget cell is Lines' only). A paused line reads `last activity 14 July`, with "last" once, `—` without one (the last-activity wording, owner 2026-11-16, `docs/specs/phase-1-see.md` → S4-2b; built in S4-3b).
2. Two `MetricCard`s side by side: **Rhythm** (sessions per week, 4-week avg 4.0) and **Progress** (tasks done per week, avg 1.0), W33–W40, current week partial; the big number's context is `this week so far · Mon–Thu`, the days of the current week so far (`Mon` on a Monday; `components.md` § MetricCard).
3. **Projects** table: Project (folder symbol + name; no project due badge in phase 1, Q1.4, owner 2026-10-30) · Kind (`plan · 4 steps`, `repeating sessions`, `one-off tasks`) · Next actions · Remaining (`≈ 2 h 15 min est.`). A row counts only this line's own tasks: a task of another line in the same project does not count, nor an open child task of another line under this line's task (S4-2b, owner 2026-11-16).
4. **Next actions** (count): `TaskRow`s; the When column shows a due badge, or `today` / `Fri` / `12 Oct` / `no date`; a date in another year shows its year (`5 Jan 2027`). The due badge follows Today's: `Due 18:00` for a due time today, the date otherwise, a due today at OmniFocus' default time included (owner, 2026-11-16; built in S4-3c-1, 2026-11-24). The rule is in `docs/specs/phase-1-see.md` → S4-2b.

Inspector 360, shown by default; ⌃⌘I and the toolbar button hide and show it (S4-2b):

- **Parent artifact** card: label, title 17 bold, description, Horizon / Target / Note path grid, button "Open in Obsidian". As built in S4-2b (owner, 2026-11-16): label (`Parent artifact`, or `Parent note` when the thread ends at a note), title, and a Horizon / Note grid. **Horizon**, two cases: a parent artifact shows the year of the year note that holds it, `2026 · year` (artifacts come only from year notes, and the vault contract gives an artifact no period of its own, `docs/discovery/vault-contract.md` § 2.1); a parent note shows its own period, `2026 · year` or `Q3 2026 · quarter`, and a note of another scale shows no Horizon row. No Target row (a target year on an artifact may come later, together with milestones) and **no Status row**. "Open in Obsidian" opens the artifact's year note, or the parent note, through the link opener (built in S4-5). The mockup's `2027 · year`, `Target May 2027`, description paragraph and per-artifact Note path are stale (`README.md` § Pending design rounds, Before 3b); this spec wins.
- **Last 10 completions**: date (`Today`, `Wed 30 Sep`) · title · tag (`session` rhythm colour / `task` progress colour).

## Data

Line detail model (moved to S4 in the phase-1 spec): parent artifact (NoteRef), projects, next actions, last 10 completions, weekly rhythm and progress for 8 weeks plus the 4-week means.

Tasks with the reminder tag (ADR-0017, S4 bridge) are in none of these: not in next actions, completions, rhythm or progress (`today.md` § Reminders).

## Acceptance

- [x] Two separate charts; the average is a dashed rule, not a third series (S4-2b).
- [x] "Open in Obsidian" uses `obsidian://open?vault=…&file=…` (with the link opener, S4-5).
- Rows (S4-5, owner 2026-11-25): a double-click on a Projects, Next actions or Last 10 completions row opens it in OmniFocus. The keyboard path to those rows (selection, ↵) moves to S5 polish. ⌘↵ (Open in OmniFocus) is the keyboard path to the line's project (owner, 2026-11-26).
- [x] The kind "plan · 4 steps" appears only once plans exist (phase 2); in phase 1 show `one-off tasks` / `repeating sessions` (S4-2b).

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

## Draft-5 — the timer and periods

- **Start a timer** (Timer (Mac), phase 2; `timer-mac.md`): a toolbar button `▶ Start timer` next to "Open in OmniFocus"; ⌘T with no row selected starts the line, with a project or next-action row selected starts that row. Project rows and next-action rows get the ▶ `TimerButton` on hover and selection; the running subject shows the running pill.
- **A practice line** (ADR-0019) opens the practice card instead of the metric cards: entries this week and month, progress to each target, the streak of periods, the last entry's date. **Quota tasks** (ADR-0020) show their chip in the Next actions table's When column. Both are phase 2 and not drawn in this round; the Lines artboard `Lines-Periods` fixes their wording.
