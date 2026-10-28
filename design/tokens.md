---
title: Design tokens
status: draft-1
date: 2026-10-01
---

# Tokens (draft-1)

The machine-readable source is `tokens.json`. This page explains the roles.

## Colour roles

| Token               | Light               | Dark                  | Use                                                                                                                                    | SwiftUI                    |
| ------------------- | ------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| text                | #1D1D1F             | #EDEDF0               | primary text                                                                                                                           | `.primary`                 |
| secondary           | #5F5F67             | #A6A6AD               | subtitles, metadata                                                                                                                    | `.secondary`               |
| tertiary            | #74747C             | #8D8D95               | captions, column headers, hints                                                                                                        | `.tertiary`                |
| accent              | #0A64D8             | #5A9DFF               | selection, today marker, links                                                                                                         | `Color.accentColor`        |
| selection           | accent 8 %          | accent 16 %           | selected row background                                                                                                                | `.listRowBackground`       |
| dueText / dueFill   | #8A4B00 on #FFEFD6  | #FFC266 on amber 15 % | **real due dates only**; exception (owner, 2026-10-27; ADR-0020): a strong quota's time state and short period                         | asset `DueText`, `DueFill` |
| rhythm              | #2F68C8             | #5E92EE               | repeated sessions series                                                                                                               | asset `Rhythm`             |
| progress            | #14917A             | #3FA690               | one-off tasks done series                                                                                                              | asset `Progress`           |
| paused              | #8E8E95             | #7E7E86               | paused line text                                                                                                                       | `.secondary` is acceptable |
| doneText            | #9A9AA2             | #7E7E86               | completed task title (+ strikethrough)                                                                                                 | `.tertiary`                |
| forecastBand / Line | blue 16 % / #2F68C8 | blue 22 % / #5E92EE   | p10–p90 band, p50                                                                                                                      | asset                      |
| loadSegment / Alt   | #C9D3E6 / #B4C1DA   | #4A5468 / #596378     | stacked weekly load (one hue, two steps)                                                                                               | asset                      |
| workSegment         | #8C9FC2             | #8291AF               | tracked time on work lines (draft-5): the day balance, tracked blocks, the week table's Work row; with loadSegment for everything else | asset `WorkSegment`        |
| futureBadge         | #5B3FA8             | #B9A6F0               | "Future · phase 2–3" marker in mockups only                                                                                            | not shipped                |

`workSegment` (draft-5) is a third step of the load hue, not a new hue: against `loadSegment` it is 1.8:1 in light mode and 2.4:1 in dark, so work and everything else are never told apart by fill alone; the legend, the labels and the 1 pt gaps carry it. Label text on it meets 4.5:1 (`segText` in light, a dark ink in dark).

Rhythm and progress were checked with the dataviz palette validator: lightness band, chroma floor, separation under colour-blindness (ΔE ≥ 16) and contrast against the surface, in both modes. Don't swap them for grey: grey failed the chroma check.

Amber vs. red: amber was chosen so that urgency reads as "attention" rather than "failure". Always pair it with the clock symbol and the text "Due …".

## Type scale (SF Pro)

| Role          | Size / weight                 | Where                           |
| ------------- | ----------------------------- | ------------------------------- |
| windowTitle   | 19 bold                       | toolbar title                   |
| screenHeader  | 24 bold                       | Line detail name                |
| bigNumber     | 30–32 bold, monospaced digits | metric cards, forecast p50      |
| sectionHeader | 14 semibold                   | line group headers, card titles |
| taskTitle     | 13.5 regular                  | task rows                       |
| body          | 13                            | default                         |
| meta          | 12                            | estimates, summaries            |
| caption       | 11                            | column headers, legends, hints  |
| mono          | SF Mono 11.5                  | note frontmatter, file paths    |

Numbers in tables and metrics use `.monospacedDigit()`.

## Sizes

Sidebar 236 · toolbar 56 · status bar 28 · task row 28 · group header 30 · column header 26 · checkbox 16 (circle) · Lines row 46 · radii: chip 5, badge 4, card 10–12, sheet or palette 14.
