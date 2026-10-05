---
title: Project forecast (future)
status: draft-1
phase: future (2–3) — design direction only, do not build in phase 1
date: 2026-10-01
related: ["[[0006-plan-model-steps-effort-levels-simulated-forecast]]"]
artboards: [mockups/Forecast.dc.html, mockups/Forecast-Dark.dc.html]
---

# Project forecast — FUTURE (draft-1)

Example: **Bach Partita No. 2 — Allemande** (🎻 Violin → Spring recital 2027).

## Layout

1. **Headline card**: "Likely finish · p50" + `3 December` (32 bold) + `range 9 November – 15 January (p10–p90)`. Middle: the one-line explanation `At 2.1 h/week the remaining 18 h take ~9 weeks.` and the provenance line `1 000 simulated runs · your estimates run ×1.15 long on this line · 14 weeks of history` (or `based on estimates only`). Right: mode `Actual pace | Scenario | Target date`; level `min | normal | max`, dimmed unless the mode is Scenario.
2. **Plan card**: steps on a shared timeline (Sep–Feb, month gridlines, a "today" rule in accent). Each step: number badge (✓ when done), name, criterion line (`effort · 12 h est. · done`, `sessions · 6 of 10 · ≤ 5 per week`, `metric · 60 → 80 bpm · ≥ 2 weeks adaptation`, `checkpoint · teacher sign-off`) and a p10–p90 bar with a p50 tick and a date label. Goal row: an outlined band with p10, p50 (bold) and p90 labels.
3. **Drift card**: the projected p50 per week (W29–W40) as a line with points, the p10–p90 area, date axis with later dates lower, labels `8 Jan` (peak) and `3 Dec · now`. Below it, a **separate** bar chart "Practice on this project" (h/week) with a dashed "normal · 2.4 h/week" rule; the current week is partial. Two facts as text: `W35–W37: practice at about 35 % of normal — the date moved 6 weeks later.` · `Back to normal since W38 — the date returned to 3 December.`

## Model mapping (ADR-0006)

Step kinds → criterion line; three-point estimate × calibrated bias; `maxRate` / `minDuration` shown in the criterion line; snapshots → drift chart; modes → the segmented control.

## SwiftUI

Swift Charts. Plan: `BarMark(xStart:xEnd:y:)` + `RuleMark(x:)` for p50 and today. Drift: `AreaMark(x:, yStart:, yEnd:)` + `LineMark` + `PointMark`, `.chartYScale(domain: .automatic(reversed: true))`. Practice: its own `Chart`.

## My take (draft-4)

Artboards: `Forecast-Take`, `Forecast-Take-Dark` (1440 × 1040). Future (phase 2–3), direction only.

### Layout

- Toolbar button `Add my take` (opens `TakeControl` for this project and the current week).
- **Take marks on the drift chart's week axis.** Under the drift chart, on the same x positions as W29–W40, a two-row strip labelled `my take`: `this project` (W36 ✦) and `🎻 Violin line` (W35 ▶, W36 ✦, W38 ▶, W39 ●, W40 ▷ draft). It is a strip of marks, not a third series: no y-axis, no line through the marks. The practice chart stays below it, separate.
- A third fact line under the two existing ones: `W36: 0.6 h on this project · my take: Leap — “Vibrato finally works”.` Facts and the take are joined by `·` only.
- **Re-estimate row** between the headline card and the plan: `✦ W36 · my take: Leap — “Vibrato finally works” │ Re-estimate what is left? · Open estimates · Nothing changes by itself · Not now`. One quiet row on the band fill.

### Data

Project-level takes (optional, independent of the line's takes) and the line's takes for the charted weeks. A take never enters the forecast model: no weight, no bias, no feature.

### Behaviour

The re-estimate row appears when a Leap is set on the project and stays until the owner opens the estimates or chooses `Not now`. `Open estimates` goes to the plan's three-point estimates; the owner changes the numbers; the forecast is recomputed from them as usual. A Leap on the line alone does not show the row here; it shows the row in Line detail, listing the line's projects that have plans (`line-detail.md` § My take). `Add my take` saves a draft (only the weekly review confirms).

### SwiftUI

The strip is a plain `HStack`/`Canvas` aligned with the chart's plot area (`chartPlotStyle` / `ChartProxy.position(forX:)`), not a `Chart` mark.

### Acceptance

- [ ] The forecast (p10, p50, p90) is identical with and without takes.
- [ ] Marks sit on the weeks of the axis above them; the strip has its own label and no scale.
- [ ] The row asks a question and offers a link; it never proposes numbers.
