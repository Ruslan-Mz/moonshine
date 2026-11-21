---
title: Day rail — dense day
status: decided
date: 2026-11-20
decision: "direction 1, the compressed timeline, for every day (owner, 2026-11-17)"
artboards:
  [
    mockups/Rail-Compare.dc.html,
    mockups/Rail1-Compressed.dc.html,
    mockups/Rail1-Compressed-RU.dc.html,
    mockups/Rail2-Agenda.dc.html,
    mockups/Rail2-Agenda-RU.dc.html,
    mockups/Rail3-Hybrid.dc.html,
    mockups/Rail3-Hybrid-RU.dc.html,
    "+ -Dark variants",
  ]
related: ["[[today]]", "[[components]]"]
---

# Day rail — dense day

**Decided: direction 1, the compressed timeline, for every day (owner, 2026-11-17).** Directions 2 and 3 stay on the canvas as the alternatives that were not chosen.

Canvas page "Day rail · dense day". Each direction is drawn for the sparse demo Thursday (now 16:20, calendar connected) and an invented dense Monday (now 14:40, no calendar access), light and dark. English at Today's 300-pt rail without a visible scroller; Russian at the same 300-pt rail with a visible legacy scroller, where the app's proportional lane is 213 pt (`Apps/Mac/Tests/DayRailTests.swift`: lanes 228 and 213).

## The problem (today's build)

Proportional at 26 pt/h: marks closer than ~30 min share columns; a run that does not fit collapses into a block with `+N`. On `Rail-Compare` the emulated build keeps 7–9 letters of title in the column pairs at 300 pt (the real build reports 3–5) and hides the 10:20 deadline and three tasks behind two `+2` blocks. Empty afternoons take height; many half-width chips look busy.

## Direction 1 — compressed timeline (decided)

### Layout

- **Rows, not columns.** Every item is a full-width `DayRailRow` (min 22 pt) in time order; titles always get the whole width. Nothing sits side by side.
- **Scale with breaks.** Between rows, up to 60 min is drawn to scale at 30 pt/h; a longer empty stretch becomes one `RailGap` row (18 pt) with its range, `11:55–14:15`. Rows never overlap: a row that would start inside the previous one is pushed down.
- **Time gutter.** `HH:mm` of every row in a 40-pt gutter, 11 secondary, tabular; under a block ≥ 34 pt its end time in 10 tertiary. A due row leaves the gutter empty: its label keeps `Due 10:20`. `08:00` and `22:00` mark the window's ends.
- **Durations.** A span (an event or a task with an estimate) with no other row inside it is a block of its duration (min 22). A span that contains other rows is a one-line row plus a 2-pt `DurationLine` in the gutter edge down to its end time (`Read a paper` 10:05–10:35 holds `Submit the form` and `Call a supplier`). The end time is left out where the line ends at a gap, whose range already says it.
- **Nested spans** (owner, 2026-11-20): only the outer span draws a duration line. The span nested in it shows its own range in its row as secondary text: `Review the notes … 17:45–18:15` inside `Write the report` 17:30–18:30.
- **Overlapping spans** (owner, 2026-11-21): the outer span's line runs to the latest end of every span that starts inside it, and a row that starts before that end is inside it. An event 14:00–15:00 with a task 14:30–16:00 draws one line to 16:00; at the same start the event comes first and is the outer span (an event 10:00–10:30 with a task 10:00–12:00 draws one line to 12:00).
- **Rows inside a span stack 2 pt apart** (owner, 2026-11-21), as `Read a paper`, `Due 10:20` and `Call a supplier` do.
- **A row from before the window** sits at the start line with its range in the row and no gutter time; a pinned row from an earlier day does the same, `Wed 23:00–07:00` (owner, 2026-11-21).
- **The now line** (owner, 2026-11-20); its label is always in the gutter, `now` over the time, so it never covers a title:
  - **in a gap:** by proportion; the gap row grows to 40 pt, its range on top, the line in the lower band (Thursday 16:20 in `15:20–17:00`);
  - **between rows:** in a 24-pt slot at the boundary after the last row that started at or before now, never across a row; a 1.5-pt accent line across the rows;
  - **inside an ongoing span** (an event or an estimated task running now): a dot on its duration line at now's place, no line across the rows (Monday 14:40 inside `Draft the summary` 14:15–15:15, after `Reply to two emails`). For a block with no rows inside, the dot sits on the block's gutter edge by proportion and the end time gives way to the label.
  - **before the first row** (owner, 2026-11-20): in a 24-pt slot under the 08:00 line, above the first row, with the label in the gutter (Monday 08:05, first row 08:10).
  - **inside a nested span** (owner, 2026-11-20): the dot goes on the outer span's duration line, the only line drawn (Monday 17:50 inside `Review the notes`, on the line of `Write the report`).
  - **the gutter time it covers gives way** (owner, 2026-11-21), as a block's end time does: Monday at 14:40, the label covers `14:30` of `Reply to two emails`, which is left out.
  - **`during`** (owner, 2026-11-21) names the span still running at now, the outer one when several are: Monday 17:50 is `during Write the report`; with an event 14:00–15:00 and a task 14:30–16:00, 15:30 is during the task.
  - Drawn on `Rail1-Compressed` (column "Now") with generic tasks for each case.
- **Two lanes (phase 2)** (owner, 2026-11-20): when the rail has Plan and Tracked lanes, both share one compressed axis. A gap collapses only where both lanes are empty, and rows stay aligned across the lanes. Phase 2 inherits this rule; its drawing waits for phase 2's design round.
- **Due rows on one line.** A due row takes two lines (label, then title) only when its row is narrower than 175 pt. That never happens in Today: direction 1's rows are 212 pt (no scroller) and 197 pt (visible scroller). Confirmed (owner, 2026-11-21): the gutter is 40 pt at both widths, a due row is one line in Today, and pinned rows are 22 pt with the gutter.

### Measured (on the artboards, 300-pt rail)

|          | English, no scroller (rows 212 pt)                                                                                         | Russian, visible scroller (rows 197 pt)                                           |
| -------- | -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Monday   | every title whole except the nested span with its range: `Review the notes` 15 of 16 characters                            | `Submit the form` (due row) 12 of 15; `Review the notes` 13 of 16; the rest whole |
| Thursday | 17–28 characters on the four long titles (`Submit workshop abstract` 17 of 24 … `Allemande, bars 1–16 at ♩ = 60` 28 of 30) | 13–26 characters                                                                  |
| Gutter   | 40 pt holds `HH:mm` at 11 and the two-line `now` label                                                                     | the same; `сейчас` fits                                                           |

Height from the 08:00 line to the 22:00 line: Thursday 395 pt (the proportional rail: 364 pt), Monday 497 pt (owner, 2026-11-21). The Monday column of `Rail1-Compressed` measures 525 pt because it still draws a 24-pt now slot after `Reply to two emails`, from before the decision of 2026-11-20 that now inside an ongoing span is a dot; the decided rule gives 497.

### VoiceOver

Section: "Day, 15 items with a time, 1 before 08:00. Shortened: 08:30 to 10:05, 10:35 to 11:40, 11:55 to 14:15, 15:15 to 17:30. Now 14:40, during Draft the summary." Selected task: "10:20, Call a supplier, task, no estimate, not completed, Life ops, selected." Span: "17:30 to 18:30, Write the report, task, estimate 1 hour. Contains Review the notes, 17:45 to 18:15, and Send an invoice." RU: «10:20, Call a supplier, задача, без оценки, не выполнена, Быт и система, выбрана».

As built (owner, 2026-11-21): the section adds `1 after 22:00` when rows are pinned below; whole hours read `estimate 1 hour`, other estimates `estimate 100 minutes`; a span's reading keeps its status and line terms before `Contains`, and the list follows the language's list format (`… 17:45 to 18:15 and Send an invoice` in British English); RU `не выполнена` / `выполнена` agree with `задача`, also on a deadline row; both rows of a task with a planned and a due time today say `selected`.

### Selected

A click on a task selects its row in Today's list; the rail row takes the `selection` fill and a 1.5-pt accent ring. A task with both a planned and a due row today shows both as selected: it is one task (owner, 2026-11-21).

## Not chosen

**Direction 2 — agenda with a mini scale.** A 10-pt day bar (08 → 22 over the list's height: event bars in calendar colour, a tick per task, an amber tick only for a deadline, the now marker) beside an agenda of 22-pt rows with a 34-pt time column; events show their end (`–18:00`); the now line is a row; a pause over 60 min adds 6 pt. Hover and VoiceOver focus fill the row and turn its tick accent and wider; the bar is hidden from VoiceOver. Its rows are 186 pt at 300 pt and 171 pt with a scroller, so there a due row takes two lines. Measured at 300 pt: English keeps 11–24 characters on the long titles; Russian with a scroller keeps every Monday title whole and 20–23 characters on Thursday's. The bar and the rows do not line up, so the day's shape needs a hover; it is close to the agenda the owner turned down on 2 Oct (variant A).

**Direction 3 — hybrid.** Proportional (today's build) while the day fits; direction 1 above the threshold, with a `compact` tag and the caption `A busy day: quiet stretches are shortened.` / `Плотный день: пустые промежутки сокращены.` Threshold: switch when any two marks would overlap at 26 pt/h — two starts closer than the earlier mark's drawn height (14 pt ≈ 32 min; 13 pt for a due mark) — or when the column rule would need a second column; decided per day, never mid-scroll. Thursday stays proportional (closest pair: the 18:00 due mark and the 18:30 event, exactly 13 pt); Monday switches at 08:10 / 08:30. Hover on the proportional rail shows a `MarkPopover`. Cost: two layouts, a threshold to test and a rail that looks different from day to day.

## Components and tokens

No new colours. Mockup-only tokens: `canvas`, `scroller`, `scrollTrack`.

| Name                         | New / changed                                                     | Spec                                                                                                                                                                                                                                |
| ---------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DayRailRow`                 | new (the compressed layout's row for events, tasks and due marks) | full width, min 22; event: `chipFill` + 3-pt calendar bar, past 50 %; task: 1-pt `badgeBorder` outline, 10-pt checkbox, emoji at the trailing edge, done = `doneText` + strike; title 11.5 (was 10.5)                               |
| `DueMark`                    | changed                                                           | a 22-pt row (was a 13-pt line): 3-pt bar `dueText` for a deadline or `checkboxStroke` otherwise · checkbox · `Due 10:20` 11.5 semibold `dueText`, or `due 10:20` 11.5 `tertiary` · title · emoji; two lines only under a 175-pt row |
| `PinnedRow`                  | changed                                                           | 22 pt (was 16), with the same gutter as the rows                                                                                                                                                                                    |
| `RailTimeGutter`             | new                                                               | 40 pt; start 11 `secondary`, end 10 `tertiary`                                                                                                                                                                                      |
| `RailGap`                    | new                                                               | 18 pt, dotted 1.5 `badgeBorder` stub, range 10.5 `tertiary`; 40 pt with the now line inside                                                                                                                                         |
| `DurationLine`               | new                                                               | 2 pt, calendar colour (event) or `secondary` (task), 70 %; outer span only                                                                                                                                                          |
| Nested span range            | new                                                               | `17:45–18:15`, 10.5 `secondary`, before the emoji                                                                                                                                                                                   |
| `NowMarker`                  | changed                                                           | 7-pt accent dot; 1.5-pt accent line only in a gap or between rows; label `now` 9.5 over `14:40` 10.5 semibold, accent, in the gutter; 24-pt slot between rows                                                                       |
| Sizes                        | changed                                                           | 30 pt/h between rows (was 26); row min 22 (was 14); longest stretch drawn to scale 60 min                                                                                                                                           |
| `MiniDayScale`, `AgendaRow`  | direction 2 only                                                  | see the artboard notes                                                                                                                                                                                                              |
| `RailModeTag`, `MarkPopover` | direction 3 only                                                  | see the artboard notes                                                                                                                                                                                                              |
| Strings                      | new                                                               | gap range `HH:mm–HH:mm`; `now` / `сейчас` in the gutter; VoiceOver strings above                                                                                                                                                    |

## Notes on the data

- The dense day is invented: generic titles, times that belong to no real day, and only lines of the demo set (🎻 🎹 📐 🧺 🔬 🤖, and 💪 in the generic "Now" cases on `Rail1-Compressed`; 🎹 Piano is the demo's maintenance line). It keeps the shape the review asked for: 14 timed items in the window plus one before 08:00, clusters of two or three within 10–30 min (08:10/08:30, 10:05/10:20/10:20, 11:40/11:50, 14:15/14:30, 17:30/17:45/18:00), seven tasks with no estimate, the deadline `Due 10:20` at the same minute as `Call a supplier`, one long evening task (`Evening practice` 19:50–21:30), no events.
- Footers follow `today.md`: Thursday `1 h 15 min planned · ≈ 2 h 25 min free until 22:00` / `day window 08–22`; Monday (no access) `4 h 15 min planned` (owner, 2026-11-21; it read 4 h 25 min until then): the union of the estimated tasks in the window, 30 + 5 + 60 + 60 + 100 minutes, since `Review the notes` lies inside `Write the report` / `day window 08–22` and the quiet connect line.
- The invented Monday, in order (estimates in minutes; — is none): `Warm-up routine` 06:45, 15 (before the window); `Review flash cards` 08:10, —; `Check the mailbox` 08:30, —; `Read a paper` 10:05, 30; `Submit the form` due 10:20, a deadline; `Call a supplier` 10:20, —; `Run the test suite` 11:40, —; `Order office supplies` 11:50, 5; `Draft the summary` 14:15, 60; `Reply to two emails` 14:30, —; `Write the report` 17:30, 60; `Review the notes` 17:45, 30; `Send an invoice` 18:00, —; `Plan tomorrow` 19:10, —; `Evening practice` 19:50, 100. In the window, seven tasks have no estimate and six have one.
