---
title: Day rail — dense day (exploration)
status: exploration, not decided
date: 2026-11-17
artboards: [mockups/Rail-Compare.dc.html, mockups/Rail1-Compressed.dc.html, mockups/Rail1-Compressed-RU.dc.html, mockups/Rail2-Agenda.dc.html, mockups/Rail2-Agenda-RU.dc.html, mockups/Rail3-Hybrid.dc.html, mockups/Rail3-Hybrid-RU.dc.html, "+ -Dark variants"]
related: ["[[today]]", "[[components]]"]
---

# Day rail — dense day (exploration)

Canvas page "Day rail · dense day". Three directions for Today's **Day** section, each drawn for the sparse demo Thursday (now 16:20, calendar connected) and an invented dense Tuesday (now 14:57, no calendar access), in English at 300 pt and Russian at 213 pt with a visible scroller, light and dark. `today.md` § Calendar stays the spec until the owner picks a direction.

**Recommendation: direction 1 (compressed timeline), on every day.**

## The problem (today's build)

Proportional at 26 pt/h: marks closer than ~30 min share columns; a run that does not fit collapses into `18:00 Article draft +2`. The emulation on `Rail-Compare` keeps 7–9 letters of title in the column pairs at 300 pt (the real build reports 3–5) and hides two tasks behind `+2`. Empty afternoons take height; many half-width chips look busy.

## Direction 1 — compressed timeline (recommended)

- **Rows, not columns.** Every item is a full-width `DayRailRow` (min 22 pt) in time order; titles always get the whole width.
- **Scale with breaks.** Between rows, up to 60 min is drawn to scale at 30 pt/h; a longer empty stretch becomes one `RailGap` row (18 pt) with its range, `12:15–17:00`. Rows never overlap: a row that would start inside the previous one is pushed down.
- **Time gutter.** `HH:mm` of every row in a gutter (40 pt at 300, 36 at 213), 11 secondary, tabular; under a block ≥ 34 pt high its end time in 10 tertiary. Due rows leave the gutter empty: their label keeps `Due 18:00`. `08:00` and `22:00` mark the window's ends.
- **Durations.** A span (event or task with an estimate) with no other row inside it is a block of its duration (min 22). A span that contains other rows (Article draft 18:00–18:45 holds Call the bank and Pay the rent) is a one-line row plus a 2 pt `DurationLine` in the gutter edge down to its end time. Nothing sits side by side.
- **Now.** An accent line with `now 14:57`; inside a gap row the gap grows to 34 pt, its range sits on top and the line is placed in the lower band by proportion.
- **Narrow width.** At 213 pt a due row takes two lines (`Срок 18:00`, then the title), so the label does not push the title out.
- Heights: Thursday 385 pt (proportional: 364), Tuesday 442 pt.
- Measured on the artboards: at 300 pt only a due row truncates on Tuesday (17 of 19 characters stay); at 213 pt in Russian every title keeps 12–19 characters.

**VoiceOver.** Section: "Day, 14 items with a time, 1 before 08:00. Shortened: 08:50 to 11:00, 12:15 to 17:00." Selected task: "18:00, Call the bank, task, no estimate, not completed, Life ops, selected." Span: "18:00 to 18:45, Article draft, task, estimate 45 minutes. Contains Call the bank, Pay the rent." RU: «18:00, Call the bank, задача, без оценки, не выполнена, Быт и система, выбрана».

**Selected.** A click selects the task's row in Today's list; the rail row takes `selection` fill and a 1.5 pt accent ring.

## Direction 2 — agenda with a mini scale

A 10 pt day bar (08 → 22 over the list's height: event bars in calendar colour, a tick per task, an amber tick only for a deadline, the now marker) beside an agenda of 22 pt rows with a 34 pt time column; events show their end (`–18:00`); the now line is a row; a pause over 60 min adds 6 pt. Hover (and VoiceOver focus) fills the row and turns its tick accent and wider. The bar is hidden from VoiceOver. At 300 pt it reads well; at 213 pt the bar and the time column leave 3–9 characters of title. It is close to variant A, the agenda the owner turned down on 2 Oct, and the bar does not line up with the rows.

## Direction 3 — hybrid

Proportional (today's build) while the day fits; direction 1 above the threshold, with a `compact` tag and the caption `A busy day: quiet stretches are shortened.` / `Плотный день: пустые промежутки сокращены.`

**Threshold:** switch when any two marks would overlap at 26 pt/h — two starts closer than the earlier mark's drawn height (14 pt ≈ 32 min; 13 pt for a due mark) — or when the column rule would need a second column. Decided per day from the items, re-evaluated when data changes, never mid-scroll. Thursday stays proportional (closest pair: the 18:00 due mark and the 18:30 event, exactly 13 pt); Tuesday switches at 08:35 / 08:50. Hover on the proportional rail shows a `MarkPopover` with the full title, time, estimate and line.

## Why direction 1

| | 1 · compressed | 2 · agenda + bar | 3 · hybrid |
| --- | --- | --- | --- |
| Dense day, 300 pt | full titles | full titles | = 1 |
| 213 pt, Russian | 12–19 characters | 3–9 characters | = 1 (dense), proportional labels otherwise |
| Shape of the day | in place (scale + labelled gaps) | separate bar, needs hover | in place |
| Same look every day | yes | yes | no: flips when one task is added |
| Build and test cost | one layout pass in Core | list + bar | two layouts + threshold |

Cost of direction 1: a pure layout function in Core (items → rows, gaps, duration lines), testable without UI; absolute position is exact only within a stretch, and the gap label carries the range across a break.

## Components and tokens

No new colours. Mockup-only tokens: `canvas`, `scroller`, `scrollTrack`.

| Name | Direction | New / changed | Spec |
| --- | --- | --- | --- |
| `DayRailRow` | 1, 3 | new (replaces the label layout of `EventBlock`, `TimedTaskBlock`, `DueMark` in the compressed layout) | full width, min 22; event: `chipFill` + 3 pt calendar bar, past 50 %; task: 1 pt `badgeBorder` outline, 10 pt checkbox, emoji at the trailing edge, done = `doneText` + strike; due: 3 pt bar `dueText` (deadline) or `checkboxStroke` (other), `Due 18:00` semibold amber or `due 18:00` tertiary; title 11.5 (was 10.5) |
| `RailTimeGutter` | 1, 3 | new | 40 pt (300) / 36 pt (213); start 11 `secondary`, end 10 `tertiary` |
| `RailGap` | 1, 3 | new | 18 pt, dotted 1.5 `badgeBorder` stub, range 10.5 `tertiary`; 34 pt with the now line |
| `DurationLine` | 1, 3 | new | 2 pt, calendar colour (event) or `secondary` (task), 70 % |
| `MiniDayScale` | 2 | new | track 10 × list height, radius 5, `track`; event bar 6; task tick 8 × 1.5 `secondary`; task span 2; deadline tick `dueText` 2.5; now 1.5 accent + 5 pt triangle; hour labels 9 pt |
| `AgendaRow` | 2 | new | 22 pt, time column 34, event end time 10.5 `tertiary`; hover `navSel` |
| `RailModeTag` | 3 | new | `compact` / `сжато`, 11 `tertiary`, 1 pt `badgeBorder`, radius 4 |
| `MarkPopover` | 3 | new | 206 wide, `card` + `shadow`, title 12.5 semibold, meta 11.5 `secondary` |
| Sizes | 1, 3 | changed | scale 30 pt/h between rows (was 26), row min 22 (was 14), max ungapped stretch 60 min |
| Strings | all | new | gap range `HH:mm–HH:mm`; `compact` / `сжато`; the caption above; VoiceOver strings above |

## Notes on the data

- Footers follow `today.md`: Thursday `1 h 15 min planned · ≈ 2 h 25 min free until 22:00` / `day window 08–22`; Tuesday (no access) `2 h 30 min planned` / `day window 08–22` and the quiet connect line. The prompt's `3 h 50 min planned` matches neither day.
- Tuesday: `Juggling, 3 balls, 5 min` is read as a title with no estimate; no task is marked done (none was given); 🎹 Piano, 📖 and 📝 stand for lines not in the demo set.
