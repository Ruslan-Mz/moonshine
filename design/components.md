---
title: Components
status: draft-2
date: 2026-10-01
artboard: mockups/Components.dc.html
---

# Components (draft-2)

Each entry gives the anatomy, its states and a SwiftUI suggestion. Sizes are in points.

## TaskRow

One line, 28 high, in a 5-column layout:

| Col | Width (Today) | Content                                                                                           |
| --- | ------------- | ------------------------------------------------------------------------------------------------- |
| 1   | 34            | checkbox: 16 circle, 1.5 stroke `checkboxStroke`; done = filled accent + white check              |
| 2   | flex          | title 13.5, truncates at the tail; repeat glyph (`arrow.2.squarepath`, 11, tertiary) if repeating |
| 3   | 290           | `TraceChip`                                                                                       |
| 4   | 100           | estimate `≈ 45 min`, 12 secondary, monospaced digits                                              |
| 5   | 118           | `DueBadge`, or `planned 3 days ago` (11.5 tertiary), or empty                                     |

States: open · selected (`selection` background) · done (title `doneText` + strikethrough) · repeating · with due · from earlier. Hairline `rowSeparator` between rows.

SwiftUI: a `Table` row, or a `Grid`/`HStack` row reused in List-based screens (Line detail, Month day list). Implement once as `TaskRowView(task:, columns:)`.

## TraceChip

`Bach Partita No. 2 → 🎻 Violin → Spring recital 2027`. Text 11 `chipText` on `chipFill`, padding 1×7, radius 5, single line, truncates at the tail. Comes from the Trace service (project → line → artifact). If there is no artifact, end at the line. Life ops: `Household → 🧺 Life ops`.

SwiftUI: `Text` + `.background(.quaternary, in: .rect(cornerRadius: 5))`, `.lineLimit(1)`.

## LineGroupHeader

30 high, with a hairline below. Emoji 15 · name 14 semibold · artifact 12 tertiary · right-aligned summary `4 open · ≈ 1 h 35 min est.` 12 tertiary. Variant with an SF Symbol instead of emoji for "From earlier" (`arrow.uturn.backward`). Variant for Life ops: a disclosure chevron and 🧺, collapsed by default.

SwiftUI: `Section(header:)` content, or a `DisclosureGroup` label for Life ops.

## DueBadge

`clock` symbol 10 + `Due 18:00`, 11 semibold `dueText` on `dueFill`, radius 4, padding 1×6. **Only** for a **deadline** — a due date that counts under the deadline rule (`screens/settings.md` § Deadlines: all due dates by default, or only those whose task or project carries the deadline tag) — in the shown period, local time zone: **Week** — `effectiveDueDate` inside the displayed ISO week (Monday 00:00 ≤ due < next Monday 00:00), so a task due before that week gets no badge there; **Today** — `effectiveDueDate` before the start of tomorrow (earlier due dates included). An inherited project due date is a real due date (phase-1 spec S3) and follows the same deadline rule.

**Plain due text.** A due date in the shown period that is not a deadline: `due 20:35` / `due Fri 12:00`, 11.5 `secondary`, no symbol, no fill, in the same column. Never amber.

## Sparkline (rhythm / progress)

8 weekly pairs, 28 high, a baseline hairline. Each week: rhythm bar (5 wide, `rhythm`) and progress bar (5 wide, `progress`), 1 apart, 6 between weeks. Both series share one scale per line: max of either series = 24. Non-zero values get at least 3 high. The current week has a `track` backdrop, a dashed outline and opacity 0.6. A legend sits once per screen, never per row.

SwiftUI: Swift Charts `BarMark(x: week, y: value).position(by: series)` with axes hidden, `.chartYScale(domain: 0...max)`. Current week: `RectangleMark` behind it, opacity on the marks.

## MetricCard (Line detail)

Title (colour square + "Rhythm" + subtitle), big number (30 bold) + context ("this week so far · Mon–Thu"), a bar chart of 8 weeks with a dashed 4-week average rule labelled "avg 4.0", week labels W33…W40. The current bar is at 50 % opacity, has a dashed outline and the label "4 so far". Two separate cards for rhythm and progress.

## QuietLineCard

Card (radius 10, `card` + `cardBorder`, padding 14): emoji + name, and on the right a moon symbol + `quiet for 29 days` (secondary). Below: "Last: Lesson 14 review, 2 September", a divider, "Suggested next step" (11 tertiary), the action (13), then `≈ 10 min est.` and the link "Open in OmniFocus".

Rule: active lines with no completion for ≥ 14 days. Never maintenance, never paused.

## NoActivityCard

Dashed border, no fill: emoji + name + `no activity yet`; "First step: …".

## LineStateLabel

| State                  | Text                                                 | Style                                        |
| ---------------------- | ---------------------------------------------------- | -------------------------------------------- |
| active                 | `active`                                             | primary                                      |
| maintenance            | `maintenance`                                        | secondary                                    |
| paused                 | `paused on purpose` + pause symbol                   | whole row in `paused`, emoji at 50 % opacity |
| active, no completions | `active` + last activity `no activity yet`           | secondary                                    |
| active, quiet          | `active` + last activity: moon + `quiet for 29 days` | secondary                                    |

## StatusBar

28 high, sidebar-coloured background, hairline above. A "Demo data" capsule (stroke `badgeBorder`, dot + text), `Updated 3 min ago` (`Text(date, style: .relative)`), shortcut hints on the right. In Live mode the badge disappears; freshness stays.

## Segmented control, slider (forecast / board)

Native `Picker(.segmented)` and `Slider`. Drawn segmented: track `ctrl`, the selected segment raised.

## AnchorStrip (draft-2)

40 high. Label `Anchors` 12 semibold + `3 of 5 done` 12 tertiary, then up to 5 chips — the count covers all anchors, further anchors stay in their line sections (radius 6, `chipFill`, padding 3×8): checkbox 14 + title 12.5 (one line, ≤ 22 characters, tail truncation) + line emoji. Done = checked, title in `doneText`. Read-only in phase 1 (click opens in OmniFocus).

## QuarterFocusCard (draft-2)

Right-rail card (radius 10, `card`): title `Q4 focus` 13 semibold + `2 of 5 done` 12 tertiary; rows: status glyph (`circle` / `checkmark.circle`, neutral colours) · line emoji · artifact title 12.5 (2 lines max). Footer link `Open quarter note`; from R1 a second link `Open quarter review`. No progress bars, no percentages.

## FoundationRow / floor (draft-2)

Foundation lines carry `floor_h_day` instead of a weekly budget. Phase 1 shows `floor 3 h/day` as text; once hours exist (phase 2, Excel import) it shows `today 2.1 of 3 h` in plain text — never coloured, never a warning.

## Calendar components (draft-3)

Events are not tasks: no checkbox, no estimate, no trace chip, never amber or red. Artboard: `mockups/CalendarStates.dc.html` (states + components).

### CalendarDot

An 8 pt dot, or a 3 pt leading bar, in the calendar's colour — the only places a calendar colour may appear. Take `EKCalendar.color` and desaturate it toward the tokens (saturation ≤ 35 %, lightness 50–60 % in light mode, 65–75 % in dark). No filled coloured blocks. Demo values (light / dark): Work `#6C84AE` / `#8FA6CE` · Family `#6E9A80` / `#8FBDA0` · Music lessons `#9282B4` / `#B3A3D4` · Personal `#B0946A` / `#D0B78C`. A tentative event has a dashed, unfilled dot.

### EventRow

Same grid and height (28) as `TaskRow`: `CalendarDot` in the checkbox column · time range `09:30–10:00` (12.5, secondary, tabular digits) + title (13.5) · calendar name (11.5, tertiary; line emoji first when the calendar is mapped) · empty estimate column · When column: `in 40 min` (next event, semibold primary), `tentative`, `overlap`, or empty. Past = 50 % opacity. Private or empty title → `Busy`. Compact variant (Week columns): 3 pt bar, time above title, no calendar name; a tentative event gets a dashed, hatched outline. Touch variant: ≥ 44 pt.

### Day rail marks (Today on the Mac)

The rail spans the day window (Settings → Calendars), 26 pt per hour; marks sit in one lane to the right of the hour labels.

- **EventBlock** — neutral fill (`chipFill`) + 3 pt calendar bar; height = duration, minimum 12; label `17:00 Violin lesson 🎻` (10.5). Past = 50 % opacity. No checkbox.
- **TimedTaskBlock** — a task with a planned time. 1 pt outline (`badgeBorder`), no fill, 10 pt checkbox (read-only in phase 1), label `20:30 Allemande, bars 1–16 at ♩ = 60`, line emoji at the trailing edge; height = estimate, minimum 14 (also when there is no estimate). Done: filled checkbox, done colour, strike-through. Open after its time: unchanged.
- **DueMark** — a task with a due time today. One 13 pt line at the due time: checkbox · due time · title · line emoji. Deadline: 3 pt amber bar, `Due 18:00` (amber, semibold) — the only amber on the rail. Not a deadline: 3 pt `tertiary` bar, `due 20:35` (secondary, regular). The checkbox is read-only in phase 1 (a click opens the task in OmniFocus).
- **PinnedRow** — any of the three when it falls outside the day window: a 16 pt one-line row above or below the rail with the same leading mark and label.

### AllDayBar

20 pt (Week), 14 pt (Month), 28 pt (iPad): neutral fill, 3 pt calendar bar at the start, title, `all day · Family` in tertiary. Spans its days; in Month it continues across cells and shows the title once.

### FreeTimeFact

Plain text. Today: `4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00` — `in calendar` and `planned` are whole-day totals, the free term is what remains of the day window from now (`screens/today.md` § Calendar). A future day (Week, iPad drag): the whole window, `2 events · 2 h in calendar · ≈ 12 h free`. The `planned` term appears only when tasks with a planned time and an estimate fall inside the day window. Compact form (iPhone Today): `4 h in calendar · ≈ 2 h 25 min free until 22:00`. Secondary colour, placed next to the task fact after a hairline. Never a comparison, a colour or a judgement word. Per-day form: `2 h 30 min in calendar`. Drag form (iPad): `≈ 11 h 30 min free`.

### NextEventRow

iPhone Today and widgets: 3 pt calendar bar · `Next · 17:00–18:00` (13, tertiary) · title 17 semibold (+ line emoji) · `in 40 min` 15 semibold. Followed by `+ 1 more today`.

## Take components (draft-4)

The owner's weekly take is a judgement, not a measurement. It must never look like one: no bars, no axis, no number. Artboard: `mockups/TakeStates.dc.html` (components + states). Paths for the four marks are in the mockup sources (`TKP` in the script block, 16 × 16 box).

### TakeMark

| Direction | Shape                                                              | SF Symbol (closest)           |
| --------- | ------------------------------------------------------------------ | ----------------------------- |
| Leap      | four-point spark, drawn 1.3× the nominal size, primary text colour | `sparkle`                     |
| Rise      | triangle pointing in the reading direction                         | `arrowtriangle.forward.fill`  |
| Steady    | dot                                                                | `circle.fill`                 |
| Dip       | triangle pointing against the reading direction                    | `arrowtriangle.backward.fill` |
| note only | three small dots — a draft with a note and no direction            | `ellipsis`                    |
| blank     | nothing is drawn                                                   | —                             |

**Rise and Dip marks are interim.** They will be redrawn in the next design round as terrain shapes that are not arrows (a rising slope, a falling slope). Until then the specs and mockups keep the current triangles.

- **One ink.** Rise, Steady and Dip use `secondary`; Leap uses `text`. No colour per direction, no red, no amber, no green. No new colour token.
- **Set vs draft.** Set (confirmed) = filled. Draft = outline only, dashed (`2.3 1.7` on the 16 pt box, stroke 1.5). Below 12 pt the dashes merge into a thin outline; filled vs hollow still separates the two.
- **Sizes** (nominal; Leap is 1.3×): Mac sparklines 9 · quarter strip 8 · Mac control and journal 11–12 · Mac metric card 16 · iPad control 13–15 · iPhone strip 14, direction buttons 15.
- Take marks mirror with the layout direction (right-to-left layouts mirror them).
- Accessibility: a mark never stands alone for VoiceOver. Strips are one element with a text value (`My take: W35 Rise, W36 Leap, …`); controls and chips carry the word.

### TakeChip

18 pt high, radius 5, mark 9 + word 11: `▶ Rise`. Confirmed = `chipFill`, no border. Draft = dashed 1 pt border, no fill, the word `draft`: `▷ Rise · draft`. On a project row it includes the week: `✦ Leap · W36`. Inline text form: `my take: Leap`. iPhone: 24 pt high, text 13.

### TakeControl

Four segments (mark + word) + a one-line note + `Confirm`.

|         | Mac                                    | iPad                                                                       | iPhone (capture sheet)                                    |
| ------- | -------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------- |
| Segment | 72 × 24, text 12                       | 78 × 44, text 13 (portrait: icon-only 46 × 44; expanded 142 × 44, text 15) | 4 buttons in a row, 56 high, mark above the word, text 13 |
| Note    | 26 high, grows when focused, text 12.5 | 44 high, text 15                                                           | 56 high, text 17                                          |
| Confirm | 24 high, accent fill                   | 44 high pill                                                               | — (drafts only)                                           |

States: empty (nothing selected) · prefilled from drafts (selected segment has a dashed outline, `Confirm` visible) · confirmed (selected segment raised, `✓ set Sun 4 Oct`) · focused (accent ring on the note, selection tint on the row). Segments are equal width, sized to the longest word of the UI language. Keys on Mac: `1`–`4`, `↩`, `⌘↩`.

### TakeJournalRow

Grid 18 · 34 · flex: mark 12 · `W36` (11.5, tertiary, tabular) · direction (semibold) `— note` (wraps, never truncated), then a meta line (11, tertiary): `set Sun 6 Sep`, `set Tue 29 Sep · changed after the week ended`, or `draft · Mon 28 Sep`. Newest first.

### TakeDraftSheet

The capture sheet (`screens/iphone-quick-log.md` § My take): line chips (recent first) · one text field · four optional direction buttons · caption · `Save draft to <line>`. iPhone: bottom sheet ≈ 610 pt; iPad: popover 420 wide; Mac: the ⌘K command and `Add a note` in Line detail use a one-line field with `1`–`4`.
