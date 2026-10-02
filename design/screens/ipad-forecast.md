---
title: iPad — Project forecast (future)
status: draft-2
phase: future (2–3)
date: 2026-10-01
artboards: [mockups/iPadForecast.dc.html, mockups/iPadForecast-Dark.dc.html]
related:
  ["[[forecast]]", "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"]
---

# iPad — Project forecast (draft-2, future)

The forecast becomes a **direct-manipulation** tool: move the effort and watch the dates move.

## Layout (11″ landscape, sidebar hidden)

**Primary target: iPad 11″** — landscape 1210 × 834 pt, portrait 834 × 1210 pt. A 13″ iPad gets the same layout with more room. The screen **scrolls** on 11″: headline + plan fit the first screen, drift is below (artboard drawn at full scroll height 1180).

1. Toolbar: title `Bach Partita No. 2 — Allemande`, subtitle trace, mode segmented **Actual pace | Scenario | Target date** (Scenario drawn), `Future · phase 2–3` badge.
2. **Headline card**: `Likely finish · p50`, date 40 pt, range (p10–p90), the one-line sentence (`At 2.1 h/week the remaining 18 h take ~9 weeks.`), provenance. Right half: **effort level** segmented `min · 1.2 h | normal · 2.1 h | max · 3.5 h` (44 pt), the current value in 28 pt, and a **large slider** (track 8 pt, knob 40 pt, ticks 0.5 / 2.5 / 5 h). Hint: drag with a finger or Pencil; Pencil hover previews.
3. **Plan card** (label column 260, timeline ~820): steps on a Sep → Mar timeline (month gridlines, today rule in accent). Each step: number badge (✓ when done), name, criterion line, p10–p90 bar + p50 tick + date. Goal row outlined.
4. **Drift card**: weekly snapshots of p50 with the p10–p90 area (history, not affected by the slider), two factual sentences.

## Data

Scenario mode: the slider sets the scenario's h/week for this project; the simulation (ADR-0006) re-runs. The mock uses a stand-in model (p50 = remaining 18 h ÷ value; p10 = 0.72 × p50, p90 = 1.55 × p50) so that the artboard is live in Play mode. The real engine supplies the numbers.

## Behaviour

- Dragging recomputes continuously (debounce ~100 ms, results animate). Releasing keeps the value as an **unsaved scenario** until "Save scenario".
- Level buttons snap the slider. Pencil double-tap returns to `normal`.
- Target date mode swaps the slider for a date picker and shows the required h/week.

## SwiftUI

`Slider(value:in:step:)` with a custom style, or a `DragGesture` on a custom track for the 40 pt knob. Charts: Swift Charts (`BarMark(xStart:xEnd:y:)`, `RuleMark`, `AreaMark`, `LineMark`). Simulation in a background actor, results published on the main actor.

## Acceptance

- [ ] Moving the slider from 2.1 to 3.5 h/week moves p50 earlier and never later (property test from ADR-0006).
- [ ] VoiceOver: slider adjustable in 0.1 h steps and announces "3.5 hours per week, likely finish 6 November".
- [ ] The drift chart never changes while scrubbing (it is history).
