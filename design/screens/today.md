---
title: Today
status: draft-2
date: 2026-10-01
slice: S4
artboards: [mockups/Today.dc.html, mockups/Today-Dark.dc.html]
---

# Today (draft-2)

## Layout

Sidebar (Today selected) · toolbar: title "Today", subtitle `Thursday, 1 October · Week 40 · 23 open · 6 done · ≈ 11 h 15 min est.` · main table · right rail 300 · status bar.

Main, top to bottom: 00. **Reminders strip** (ADR-0017, S4; § Reminders below): above everything else; absent when there are no reminders. 00b. **Held line removal** (S4-4e; `design/components.md` § LineRemovalNotice): below the Reminders strip and above the Anchors strip; absent while no removal is held. 0. **Draft-2 — Anchors strip** (40): `Anchors · 3 of 5 done`, then up to 5 compact chips (checkbox + short title + line emoji) for today's tasks tagged `anchor`, first 5 in source order. The count covers **all** of today's anchors (`3 of 6 done` when there are 6). Done chips are checked and dimmed, not hidden. Absent if no anchors. Only anchors **shown in the strip** are left out of their line sections; further anchor tasks stay there.
0b. **Draft-2 — Top 3 today**: open flagged tasks, max 3 rows, a real due date today or earlier first, then source order (owner, 2026-10-26), as normal `TaskRow`s under a section header `Top 3 today`. The candidates are the open flagged tasks not shown in the Anchors strip; if there are more than 3: caption `5 flagged — 3 shown` (it counts the candidates) and a "Show all" link, also in the View menu as "Show All Flagged Tasks" with ⌥⌘F (owner, 2026-10-26). These tasks are **not repeated** in their line sections. It is the table's first section, so it sits under the column header (item 1), as the mockup draws it; one ↑↓ selection runs through it and the sections (owner, 2026-10-24).

1. Column header (26): blank · Task · Project → Line → Artifact · Estimate · When.
2. One section per line touched by today's tasks, **foundation lines first**, then the vault order. `LineGroupHeader` + `TaskRow`s. Open tasks only: a done task moves to Done today (item 5).
3. **From earlier** (`arrow.uturn.backward`), header `From earlier (8)` / `С прошлых дней (8)`: a disclosure like Life ops, collapsed by default (owner, 2026-11-24, S4-3c-1; expanded by default until then), the state in `@SceneStorage` (owner, 2026-10-26), so a window that stored it expanded keeps it; available tasks whose planned date is before today. The "When" column shows `planned N days ago`. Never amber unless there is a real due date.
4. **Life ops** (🧺): collapsed disclosure with count and estimate; expands to plain rows.
5. **Done today** (`checkmark.circle`; owner, 2026-10-24): every task completed today, checked and struck through, most recent first; the 3 most recent are visible, the rest behind an `N more` disclosure (`@SceneStorage`). A done task is in no line section, Top 3 or From earlier. A done anchor shown in the strip stays only there, as a checked chip; an anchor beyond the first five is in Done today; the subtitle's `done` counts both (owner, 2026-10-26).

Right rail:

- **Draft-2 — Quarter focus** (top): card `Q4 focus · 2 of 5 done` listing the current quarter's artifacts (status dot neutral / check), each with its line emoji; footer link `Open quarter note`. Source: the quarter note (`scale: quarter`) and its artifacts. Absent if no quarter note.
- **Touched today**: a grid Line | Rhythm | Progress, e.g. `🎻 Violin | 1 session | —`. Rhythm values in `rhythm` colour, progress values in `progress` colour, "—" in tertiary.
- **Quiet lines**: `QuietLineCard`s, then `NoActivityCard`s, then a caption explaining the rule. Foundation lines are never quiet, but a foundation line with no completions at all gets a `NoActivityCard` with its first step (owner, 2026-10-28).
- **Paused on purpose**: greyed rows.

## Data (phase-1 spec)

- Included: available tasks with effective planned or defer = today, flagged, or effective due ≤ today; and every task completed today (Done today).
- Grouping: by mapped line (task tag → project tag → project name → folder → Life ops).
- Urgent styling: only for a **deadline** (a due date that counts under the deadline rule, `settings.md` § Deadlines) with effective due ≤ today. Any other due date is plain secondary text (`due 20:35`).
- Est. sums: open tasks only.

## Behaviour

- ↑↓ moves the selection, ↵ or double-click opens in OmniFocus (`omnifocus:///task/<id>`), space toggles Quick Look-like details (later).
- Checkbox is **read-only in phase 1**: it shows state and does not write. Clicking it opens in OmniFocus instead.
- Life ops, From earlier and `N more` expansion persists (`@SceneStorage`). On a disclosure row, → expands and ← collapses, the macOS standard; Space does not (owner, 2026-10-26).
- Focus (owner, 2026-10-26): the table has the keyboard focus at launch; a click on any row selects it and focuses the table, also after an earlier click went to the sidebar; Tab moves focus between the sidebar and the table.
- ⌥⌘F toggles "Show all" of Top 3 from the View menu, wherever the list is scrolled.

## SwiftUI

`NavigationSplitView` → detail: `Table(sections)` with `TableColumn`s (widths: 34 fixed; Task flex, minimum 120, about 15 characters; trace ideal 290, minimum 120; 100; When minimum 118). On a narrow window the trace column gives way first, down to its minimum; Today's minimum width is the sum of the column minimums plus 40 for the inset style's margins and column spacing (532; owner, 2026-10-26; `TodayColumns`). The When column's ideal is the widest When text among today's rows, every group counted whether expanded or collapsed, measured in the UI language with the font each part is drawn in (the `Due` badge semibold); its minimum stays 118 and Today's minimum stays 532, so 1100×700 with the rail still fits, and a When text can be cut only at the narrowest window (owner, 2026-11-24, S4-3c-1, option (a): the column was cut at `planned 3 days a…`). At 1100×700 with the rail the column keeps about 184 pt; the Russian planned age reads `назначено N дней назад` so that a three-digit age fits there, English unchanged (owner, 2026-11-25, PR #70 round 1; `WhenWidthTests`). A From earlier row with a due date shows only the due text, the same badge or plain text as any due row; its planned age is the cell's tooltip, and VoiceOver reads it after the due text; no new strings, rows stay one line high, and the widest such row fits there in English and Russian (owner, 2026-11-25, PR #70 round 2: the due date is the stronger fact). An anchor chip's full title is its tooltip, and VoiceOver reads the full title with the done state as its value (owner, 2026-11-24, S4-3c-1). `.tableStyle(.inset)`, `alternatesRowBackgrounds: false`. Rail: `.inspector(isPresented:)` + `.inspectorColumnWidth(300)`. Header text: `.navigationTitle` / `.navigationSubtitle`.

## Acceptance

- [ ] The list scrolls; at 1440×900 the Reminders strip (when present), the Anchors strip, Top 3 and the first line section are visible without scrolling.
- [ ] Only the 2 deadlines show amber (both demo due dates today carry the `deadline` tag, so the count is the same under either deadline rule).
- [ ] "From earlier" rows show the planned age and no urgency colour.
- [ ] Italian is listed as quiet; Piano (maintenance) is not; Calligraphy appears only under "Paused on purpose".
- [ ] Rhythm and progress are separate columns in the rail.
- [ ] Light and dark both match the artboards.
- [ ] Anchors strip shows only `anchor`-tagged tasks; Top 3 shows at most 3 open flagged tasks and they are not duplicated below.
- [ ] Every task completed today is in Done today, after Life ops, the 3 most recent visible and the rest behind `N more`; none is in a line section, Top 3 or From earlier; a done anchor in the strip is not repeated there.
- [ ] `From earlier (N)` shows its count and collapses and expands with ←/→ and a click; "Show all" leaves its rows as they are.
- [ ] At launch ↑↓ move the selection without a click; after a click in the sidebar, a click on a row brings ↑↓ back to the table; Tab moves between sidebar and table.
- [ ] ⌥⌘F toggles "Show all" from anywhere in the list; the View menu shows it.
- [ ] At the narrowest window the task title keeps about 15 characters.
- [ ] Foundation sections come first.
- [ ] Checked in Russian at 1440×900 and 1100×700.

## Calendar (draft-3)

Artboards: `Today-CalB` (chosen), `Today-CalB-RU`, `Today-CalB-Mixed`, `Today-CalConnect`; `Today-CalA` is the variant that was not chosen, kept for reference (+ `-Dark` for all). Events are read-only and never amber or red (`settings-calendars.md`).

**Decided (owner, 2 Oct 2026): the day rail.** Events live in a **Day** section at the top of the right rail, together with the tasks that have a time in OmniFocus. The task list stays a list; there is no "Fixed today" section in it.

**The rail's layout: the compressed timeline** (direction 1 of `design/screens/day-rail-dense.md`, for every day; owner, 2026-11-17; built in S4-3b-3, decisions of 2026-11-21 below). It replaced the proportional rail of S4-3b and S4-3b-2. What carries over and what does not:

- **Kept from S4-3b (#62):** the Day section, its header and footer facts; the three kinds of item (event, task with a planned time, task with a due time today); all-day rows; pinned rows above and below the window; `Wed 23:00` for a start on an earlier day; the read-only checkbox and the click that selects the row in the list; done and past items; amber only on a deadline; the When column; the planned and free-time rules; one accessibility container in time order.
- **Superseded from S4-3b (#62):** 26 pt per hour, the tick label every 2 hours, and the 55 / 45 split of a task over an event.
- **Kept from S4-3b-2 (#64):** the now label in the gutter, `now` over the time; the time never truncates, the title does; a deadline reads `deadline` in VoiceOver; every row has an opaque base. The now label has no plate (owner, 2026-11-24, S4-3c-1): its white box showed on the grey inspector; nothing draws under it, since the gutter's times give way to it and the duration line runs to its right; if anything ever shows through, the rail's own background colour, never white.
- **Superseded from S4-3b-2 (#64):** the column rule by drawn extent and its footprint; the collapse into `+N` blocks, their popover and its VO-Space action; `railReadableWidth`; the due label hanging below its time; the now rule behind the marks and the tick it hid; the accepted consequences of the column rule; and the open question whether the readable width carries over to phase 2's Plan lane, which is moot: both lanes share one compressed axis (`day-rail-dense.md` § Layout, "Two lanes (phase 2)").

**Toolbar subtitle** gains a second fact after a hairline: `… 23 open · 6 done · ≈ 11 h 15 min est. │ 4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00`. Both are plain secondary text. The app does not compare them, colour them or add a word about the difference.

**Day rail.** Header `Day` + `4 events · 4 h in calendar`. A compressed timeline over exactly the **day window** from Settings → Calendars (default 08:00–22:00, configurable), and two lines underneath: `1 h 15 min planned · ≈ 2 h 25 min free until 22:00` and `day window 08–22`. **The caption's edges** (owner, 2026-11-27, PR #74 round 1): whole hours stay `08–22`; when either edge has minutes both show `HH:MM`, `day window 07:30–22:00`, never a mixed `07:30–22`; the day's end is `24`, never `00`: `00–24`, `08–24`, `22:30–24:00`. The same 24-hour digits in every language; only the words come from the catalog. All-day events of Show-on calendars are one-line `all day` rows above the timeline (Q2.1, owner 2026-10-30). **Identical events** (owner, 2026-11-27, from the live check of #74; built in S4-3d-2): events with the same title, start, end and all-day flag are one row, whatever their calendar (an account that copies one meeting into a calendar three times), with a small tertiary `×3` after the title; its tooltip and VoiceOver read `3 copies of this event`. A hidden calendar's copies are left out before the collapse; busy and free are a union, so they do not change; `N events` counts the rows. Rail times are `HH:mm` on the 24-hour clock in every language (`design/i18n.md` rule 3, owner 2026-11-16). Three kinds of item, each a full-width row (`components.md` § Day rail):

| Item                      | Source                         | Looks like                                                                                                                                                | Height                               |
| ------------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| event (`DayRailRow`)      | calendar event                 | neutral fill + 3 pt calendar bar, the title; past = 50 %                                                                                                  | its duration at 30 pt/h, at least 22 |
| timed task (`DayRailRow`) | task with a **planned time**   | outline, no fill, small checkbox, `Allemande, bars 1–16 at ♩ = 60` + line emoji                                                                           | its estimate at 30 pt/h, at least 22 |
| `DueMark`                 | task with a **due time today** | a 3 pt bar, checkbox, `Due 18:00` (amber, semibold) + title for a deadline; `due 20:35` (tertiary) + title for any other due time; the gutter stays empty | 22                                   |

- **Rows, not columns** (`day-rail-dense.md` § Layout). Every item is one row in time order, and nothing sits side by side. A row's time is in a 40-pt gutter on its left, at both widths of the rail (owner, 2026-11-21). The window's start and end lines carry `08:00` and `22:00`.
- **Scale with breaks.** Each row starts after the previous one at 30 pt per hour, never closer than 2 pt below it. An empty stretch, time no item covers, of an hour or less stays to scale; a longer one is one 18-pt `RailGap` row with its range, `11:55–14:15`, 6 pt below the row above (its 2-pt spacing and 4) and 4 pt above the next. Exactly 60 minutes stays to scale; 61 collapses.
- **Spans.** An event or an estimated task is a span. A row that starts inside a span (before the latest end of it and of every span starting inside it) is inside it. A span with no row inside is a block of its duration (at least 22), with its end time in the gutter from 34 pt on. A span with rows inside is a one-line row plus a 2-pt duration line in the gutter down to that latest end, with the end time there unless the line ends at a gap or at the window's end. Only the outer span draws a line; a span inside it shows its own range in its row, `17:45–18:15` (owner, 2026-11-20). Rows inside a span stack 2 pt apart (owner, 2026-11-21).
- **Overlapping spans** (owner, 2026-11-21). The outer span's line runs to the latest end of every span that starts inside it, so a span that outlives its outer span keeps its extent: an event 14:00–15:00 with a task 14:30–16:00 draws one line to 16:00, and a row at 15:15 is inside it. At the same start the event comes first and is the outer span: an event 10:00–10:30 with a task 10:00–12:00 draws one line to 12:00.
- **A row from before the window** sits at the start line with its range in the row and no gutter time; so does a pinned row from an earlier day, `Wed 23:00–07:00` (owner, 2026-11-21). Other pinned rows are 22 pt with their time in the gutter.
- **Now** (owner, 2026-11-20). Its label is always in the gutter, `now` over the time:
  - in a gap, the gap grows to 40 pt and the line sits in its lower band by proportion;
  - inside an ongoing span, a dot on its duration line, or on the block's edge, by proportion, with no line across the rows; a block's end time gives way;
  - otherwise in a 24-pt slot after the last row that started at or before now, or under the start line before the first row, with a 1.5-pt accent line across the rows; after a row inside a span that has ended, the slot comes below that span's duration line and its end time (review round 1, 2026-11-22).
  - **A gutter time the label covers gives way** (owner, 2026-11-21): on the dense Monday at 14:40, `14:30` is left out. This holds for every gutter time: a row's start, a block's end, a duration line's end and the window's `08:00` and `22:00` (review round 1, 2026-11-22).
- **A selected task** in the list fills its rail rows with `selection` and a 1.5-pt accent ring. A task with both a planned and a due row today shows both as selected (owner, 2026-11-21).
- A task row is a task: its checkbox shows state and is **read-only in phase 1**, as in the list (a click on it opens the task in OmniFocus); a click on the row selects the row in the list, a double-click opens it in OmniFocus. An event row has no checkbox and no actions. "Show in Calendar" is not in phase 1: macOS documents no URL for a single event (owner, 2026-11-27, on the S4-3d plan; it moved from S4-5 to S4-3d on 2026-11-25). It waits for the usage period, and needs a Core field for the event's link and an ADR-0015 amendment. Built in S4-5: a click on a task mark's checkbox and a double-click on the mark open the task in OmniFocus; a single click selects its row.
- A done task keeps its place with a filled checkbox, done colour and strike-through. A task whose planned time has passed and that is still open **stays as it is** — no label, no colour, no move. Amber appears only on a `DueMark` for a deadline.
- Items outside the day window are not on the timeline. They are pinned as rows above (earlier) or below (later) it: `07:30 Mobility — hips & shoulders` above, `Due 23:59 Submit workshop abstract` below. Same for events (the 06:40 flight). An event that began on an earlier day labels its start with that day's short weekday, `Wed 23:00` (owner, 2026-11-16).
- In the list, the When column shows the planned time as plain secondary text (`20:30`); a deadline keeps the amber `Due 18:00` badge; any other due time is plain secondary text (`due 20:35`). If a task has both, the list shows the due badge and the rail shows both rows. A due date today without a time (OmniFocus' default due time) reads `Due 1 Oct` (Q2.2, owner 2026-10-30); a due date on another day shows its date without the time (`Due 29 Sep`).
- **A due row is one line in Today** (owner, 2026-11-21): the design wraps it only under 175 pt, and Today's rows are 228 pt wide, 213 with a visible scroller (300 − 2 × 16 padding − the 40-pt gutter; the artboards measure 212 and 197).
- Demo's Thursday at 16:20 is 395 pt from the start line to the end line; the dense Monday of `day-rail-dense.md` at 14:40 is 497 pt.
- **Planned tasks reduce free time** (decided 2 Oct 2026). A task with a planned time and an estimate occupies [planned, planned + estimate] inside the day window and is reported as a separate term: `1 h 15 min planned`. It is never added to `in calendar`. Overlaps count once: `planned` reports only planned-task time **not already covered by a calendar event** (the covered part is already in `in calendar`), and free = day window − the **union** of busy events and planned tasks. Example (invented, not the demo day): an event 13:00–14:00 and a task planned 13:45 with a 30-min estimate → `1 h in calendar · 15 min planned` (only 14:00–14:15 is new), and the window loses 1 h 15 min, not 1 h 30 min; a task planned 13:15 with a 30-min estimate inside that event → `0 min planned`, so the `planned` term is left out. Done or open makes no difference; no estimate → occupies nothing; a due time occupies nothing. Demo: 12:00 +10, 15:00 +20, 20:30 +45 = 1 h 15 min (07:30 Mobility is before the window).
- **Free time on Today is what remains of the day window** (owner decision, 3 Oct 2026): free = (window end − now) − busy after now − planned after now, overlaps once; an event or a planned task in progress counts only its remaining part. Before the window opens it is the whole window; after it closes the free term is left out. `in calendar` and `planned` stay whole-day totals; the free term names the window end (`free until 22:00`) so it is not read as their difference. Demo at 16:20: 16:20–22:00 = 5 h 40 min − Violin lesson 1 h − Parents' evening 1 h 30 min − Allemande 45 min = **2 h 25 min**. Week shows the whole day window for future days (`week.md` § Calendar).

**No access yet** (`Today-CalConnect`): the Day section still shows the rail with the tasks that have a time; no events, no `in calendar` and no free term. The `planned` term stays, since it comes from OmniFocus (owner, 2026-10-17): `1 h 15 min planned`. Under the rail: `Calendar is not connected. Events stay on this device.` + `Connect calendars…` + `Not now` (hides the line for 30 days). After a denial the line reads `Calendar access is off for MoonShine.` + `Open System Settings`. **Add Events Only and Restricted** (owner, 2026-11-27, PR #74 round 1): with Add Events Only, access is on but of the wrong kind, so the line reads the Settings caption's first sentence, `MoonShine can only read calendars with Full Access.` + `Open System Settings`; the off sentence is for a denial only. After a denial and with Add Events Only the row ends with `Then reopen MoonShine.` after the link: macOS shows a new grant to a reopened app (owner, 2026-11-27, the live check of #74; S4-3d-2). Restricted shows no line on Today: the Mac's owner cannot lift a device-management restriction, and Settings → Calendars explains it. With no calendar access and no timed task today the Day section is not shown at all.

**Variant A (not chosen).** A section "Fixed today" inside the list, `EventRow`s on the task grid. Kept on the canvas (`Today-CalA`) because `EventRow` is still used by Week, Month and the iPhone; it is not part of Today on the Mac.

**Data.** Events of today from calendars with Show on. Busy time = union of timed events from calendars that count as busy, clipped to the day window; overlaps count once; tentative, all-day and free events are not counted; declined, delegated and cancelled events are hidden (`settings-calendars.md` § Data). Free = the rest of the day window − busy − planned (rule above). Task times: **planned** date-time (OmniFocus planned date) → a timed task's `DayRailRow`; **due** date-time today → `DueMark`; a defer time is not shown. A date without a time does not put a task on the rail. "Date only" means a time equal to OmniFocus' default time for that date kind (`defaultTimes` in `docs/discovery/snapshot-contract.md`); a task deliberately set at exactly the default time is read as date only (known limit, same section). A missing key for a date kind means only 00:00 counts as date only for that kind. **A missing `defaultTimes` object** (owner, 2026-10-28) keeps the stored times and the import reports `defaultTimesNotRead`; only with nothing stored yet does 00:00 count as date only for every kind (`docs/discovery/snapshot-contract.md` § Default times). Demo: `demo-data.md` § Draft-3.

**SwiftUI.** A custom `DayRailView` in the inspector column: `DayTimeline.layout` (Core, `DayLoad.swift`) places the rows, gaps, duration lines and now; the view draws them in a `ZStack(alignment: .topLeading)` with `.offset(y:)`; `TimelineView(.everyMinute)` for now. Each task row is a `Button`, each event a plain accessibility element; the rail is one accessibility container read in time order. VoiceOver (`day-rail-dense.md` § VoiceOver; owner, 2026-11-21):

- the section: `Day, 15 items with a time, 1 before 08:00. Shortened: 08:30 to 10:05, 10:35 to 11:40, 11:55 to 14:15, 15:15 to 17:30. Now 14:40, during Draft the summary.`; `1 after 22:00` when rows are pinned below; `during` names the span still running at now, the outer one when several are;
- a task: `10:20, Call a supplier, task, no estimate, not completed, Life ops, selected`; whole hours read `estimate 1 hour`, other estimates `estimate 100 minutes`; a task whose line is not found has no line term;
- a span with rows inside: `17:30 to 18:30, Write the report, task, estimate 1 hour, not completed, Life ops. Contains Review the notes, 17:45 to 18:15 and Send an invoice.`;
- Russian: `10:20, Call a supplier, задача, без оценки, не выполнена, Быт и система, выбрана`; `не выполнена` / `выполнена` agree with `задача`, also on a deadline row;
- gaps and the now marker are not read on their own: the section names them.

**Acceptance.**

- [ ] No checkbox, estimate or trace chip on events; no amber or red on events.
- [ ] Tasks on the rail are visibly different from events (outline + checkbox vs fill + calendar bar) in light and dark.
- [ ] Amber only on a deadline `DueMark`; a due time that is not a deadline is a neutral mark; an open task past its planned time looks the same as before that time.
- [ ] Clicking a task checkbox on the rail opens the task in OmniFocus and changes nothing in MoonShine.
- [ ] Completing a planned task leaves `planned` and `free` unchanged; removing its estimate removes it from both; a task without an estimate never changes them.
- [ ] Changing the day window in Settings changes the rail span, the pinned rows, the totals clipped to the window (`in calendar`, `planned`) and the free-time fact; no event or task appears or disappears (owner, 2026-10-17).
- [ ] `4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00` for the demo day at 16:20; every number derives from `demo-data.md`.
- [ ] Without access the layout does not shift; the Day section shows timed tasks and one quiet line.
- [ ] Titles keep their script and direction (RU, IT, JA, HE in `Today-CalB-Mixed`); the rail is checked in Russian.

## Reminders (ADR-0017)

Drawn in draft-5 (`TodayReminders`, + `-Dark`). S4 builds the OmniFocus tag bridge; the whole bridge (the tag setting, the exclusion and the strip) is the first thing cut from S4 if the timebox is at risk (`docs/specs/phase-1-see.md` → S4).

- **Visual (draft-5):** one row, 36 pt, on the `band` fill with a hairline below: the `bell` symbol 12 and `Reminders` (12 semibold, secondary), then the reminders as chips (`ReminderChip`, `components.md`): `card` fill, 1 pt `cardBorder`, radius 6, 24 high, line emoji 12 + text 12.5, at most 240 wide. No checkbox, no count, no amber: a reminder is seen, not done. The strip reads apart from the Anchors strip below it (plain background, chips with checkboxes).
- **More than fit:** a reminder is never cut short to fit. The ones that do not fit whole go behind `+3 more` (accent text, a chip like the others); only a single reminder wider than 240 truncates at the tail (tooltip with the full text). `+3 more` is a chip like the others: ↵ or a click opens it, and the chips wrap into as many rows as needed with `Show less` as the last chip (↵ or a click closes). The open state is kept per window (`@SceneStorage`), like Life ops.
- **Keyboard:** the strip is in the Tab order before the table. ←/→ only move between chips (`+3 more` and `Show less` included) and never open or close anything; ↵ opens the focused reminder in OmniFocus, or opens or closes the overflow on `+3 more` / `Show less`. Space does nothing here, as on every disclosure (owner, 2026-10-26).

- **Position:** the first row of the main area, above the Anchors strip. Absent when no task carries the reminder tag (`settings.md` § Reminders).
- **Content:** OmniFocus tasks with the reminder tag that are not completed, not dropped and available now (defer date absent or ≤ now), in source order; a repeating task shows only its current copy; text and line emoji only. No checkbox, no estimate, no due styling and no urgent colour: a reminder is seen, never done or overdue.
- **States:** none (absent) · one or more (shown in full up to the strip's height, one row) · more than fit (the rest behind a `+N more` disclosure, 36 pt closed) · opened (all rows, `Show less`) · Demo mode (the three demo reminders of `demo-data.md` § Draft-5 once the fixtures have them; absent until then).
- **Behaviour:** read-only; ↵ or double-click opens the task in OmniFocus, as task rows do. Notifications stay with OmniFocus until the native Reminders slice.
- **Counts:** these tasks are in no count on Today (the subtitle's open, done and estimate, Touched today, quiet lines) and in no line section, Top 3, Anchors strip or From earlier; they are hidden from every other task list too (Line detail, Week, Month) and shown only here. ⌘K finds them labelled "reminder". The trace still shows them under their project.

**Acceptance** (unless the bridge is cut).

- [ ] A task with the reminder tag is in the strip and in no line section, total or rail count.
- [ ] A completed, dropped or deferred tagged task, or a completed copy of a repeating one, is not in the strip.
- [ ] Renaming the tag in Settings moves the set at the next refresh.
- [ ] No checkbox, no amber, no "missed" or "overdue" wording; checked in Russian.

## My take (draft-4)

Not drawn on Today. One rule changes here (owner decision, 3 Oct 2026): any take or note **resets the quiet count** from its date (the date the note was written or the take was set, never a future date). A line with a take or a note in the last 14 days is therefore **not** listed under "Quiet lines" in the right rail, even with no task done. The take on the Today rail is drawn in the 3b round.

## Time (draft-5)

Artboards: `Today-Time`, `Today-Time-RU` (+ `-Dark`). Today at **15:00** on Thu 1 Oct, the moment the brief asks for: work has taken most of the day so far, and the owner should see it now, not at 22:00. Built in the Timer (Mac) slice (phase 2, ADR-0016); nothing of it is in S4.

### Layout

- **Today so far** (`DayBalance`, `components.md`), the first card of the right rail, above Day:
  - `Today so far` · `since 06:40 · 8 h 20 min` (the day so far starts where the night's Sleep ended; owner, 2026-10-28).
  - The bar and its legend: `Work 5 h 24 min` · `Everything else 2 h 36 min` · `Not tracked 20 min`. Work is the lines chosen as work in Settings → Time (`settings.md` § Time).
  - **Day marks**, one row per line with a floor or a day portion today, paused lines excluded (a paused line is never shown as missing activity, vault contract § 1): `Core practice 50 min` over `floor 3 h/day · 2 h 10 min to the floor`; `Calisthenics 15 min` · `floor 1 h/day · 45 min to the floor`; `Math 15 min` · `floor 20 min/day · 5 min to the floor`; `Violin 0 min` · `day portion 1 h · 17:00 · 1 h to the portion`. Each row has a ▶ that starts that line.
  - **Other time today:** `🤖 AI/ML 3 h 25 min` · `🔬 Research 1 h 59 min` · `🧺 Life ops 1 h 31 min`.
  - **The next free stretch** from the calendar facts (`Free 15:20–17:00 · 1 h 40 min`) and **at most one suggested start**: among the lines whose mark is still open (paused lines never), foundation lines first, then the one with the most left to its floor or portion (`▶ 🧘 Core practice`). Absent when no mark is open or no stretch is free.
  - `Tracked 8 h 15 min · by the clock 8 h · in parallel 15 min`, since 06:40.
- **Day rail with two lanes:** `Plan` (events, timed tasks and due marks as before, now 118 wide) and `Tracked` (100 wide) on the same hours. Tracked blocks, clusters of short switches and the running block as in `time.md` § Day, on that axis. Tracked time before the day window is one pinned row (`00:00–08:00 · 😴 🪥 🧘 💪 🍽️ · 8 h`). The proportional 26 pt per hour of this drawing is superseded by the compressed timeline (§ Calendar; `design/screens/day-rail-dense.md` § Layout, "Two lanes (phase 2)", owner 2026-11-17 and 2026-11-20): both lanes share one compressed axis, and a gap collapses only where both are empty. The toolbar's calendar fact uses free time from now: `≈ 3 h 25 min free until 22:00` at 15:00.
- **Rows:** the running task shows the running pill (`● 0:22` on `Submit workshop abstract`); the selected row shows ▶ (`timer-mac.md` § Starting a timer).

### The 15:00 moment

What the owner sees, in rule 8's tone: facts, then one next step.

- A fact about the whole day: 5 h 24 min of 8 h 20 min since waking went to work. No "too much", no colour for work, no percentage.
- What is still open, as distances, never as shortfalls: `2 h 10 min to the floor`. A mark already reached reads `today’s 1 h is in`.
- When he has room for it: the next free stretch and one ▶. He can ignore it; nothing repeats it or counts it.

### Data

- Today's entries and running sessions (ADR-0016); floors (`floor_h_day`) and day portions (today's events in a line-mapped calendar, else `portion_h_day`); the calendar's free time from now (§ Calendar).
- "Since" = the end of today's Sleep interval; without one, the day window's start (owner, 2026-10-28). Tracked time before it is in the Time view, not in the bar.
- Work = lines checked as work in Settings → Time, asked once on the first open of the timer (owner, 2026-10-28; `timer-mac.md` § Work lines); with none checked the bar shows tracked against not tracked only, and the legend has no Work term.

### Acceptance

- [ ] Every number derives from `demo-data.md` § Draft-5 at 15:00 (`since 06:40 · 8 h 20 min`, `Work 5 h 24 min`, `Everything else 2 h 36 min`, `Not tracked 20 min`, `Tracked 8 h 15 min · by the clock 8 h · in parallel 15 min`).
- [ ] No red, no amber, no "behind" or "missed" anywhere in the card; a reached mark shows as reached and an open one as a distance.
- [ ] At most one suggested start: foundation lines first, then the line with the most left to its floor or portion; never a paused line; absent when no mark is open or no stretch is free.
- [ ] A paused line with `floor_h_day` has no day mark row.
- [ ] The Plan lane is unchanged apart from its width; the Tracked lane never covers an event.
- [ ] Checked in Russian at 1440 × 900 (`Today-Time-RU`).
