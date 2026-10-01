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

`clock` symbol 10 + `Due 18:00`, 11 semibold `dueText` on `dueFill`, radius 4, padding 1×6. **Only** when `effectiveDueDate` ≤ end of the shown period (today for Today, this week for Week). An inherited project due date is a real due date (phase-1 spec S3).

## Sparkline (rhythm / progress)

8 weekly pairs, 28 high, a baseline hairline. Each week: rhythm bar (5 wide, `rhythm`) and progress bar (5 wide, `progress`), 1 apart, 6 between weeks. Both series share one scale per line: max of either series = 24. Non-zero values get at least 3 high. The current week has a `track` backdrop, a dashed outline and opacity 0.6. A legend sits once per screen, never per row.

SwiftUI: Swift Charts `BarMark(x: week, y: value).position(by: series)` with axes hidden, `.chartYScale(domain: 0...max)`. Current week: `RectangleMark` behind it, opacity on the marks.

## MetricCard (Line detail)

Title (colour square + "Rhythm" + subtitle), big number (30 bold) + context ("this week so far · Mon–Thu"), a bar chart of 8 weeks with a dashed 4-week average rule labelled "avg 5.5", week labels W33…W40. The current bar is at 50 % opacity, has a dashed outline and the label "4 so far". Two separate cards for rhythm and progress.

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

40 high. Label `Anchors` 12 semibold + `3 of 5 done` 12 tertiary, then up to 5 chips (radius 6, `chipFill`, padding 3×8): checkbox 14 + title 12.5 (one line, ≤ 22 characters, tail truncation) + line emoji. Done = checked, title in `doneText`. Read-only in phase 1 (click opens in OmniFocus).

## QuarterFocusCard (draft-2)

Right-rail card (radius 10, `card`): title `Q4 focus` 13 semibold + `2 of 5 done` 12 tertiary; rows: status glyph (`circle` / `checkmark.circle`, neutral colours) · line emoji · artifact title 12.5 (2 lines max). Footer link `Open quarter note`. No progress bars, no percentages.

## FoundationRow / floor (draft-2)

Foundation lines carry `floor_h_day` instead of a weekly budget. Phase 1 shows `floor 3 h/day` as text; once hours exist (phase 2, Excel import) it shows `today 2.1 of 3 h` in plain text — never coloured, never a warning.
