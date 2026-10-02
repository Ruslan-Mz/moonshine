---
title: iPad — Planning board (future)
status: draft-2
phase: future (2–3)
date: 2026-10-01
artboards: [mockups/iPadBoard.dc.html, mockups/iPadBoard-Dark.dc.html]
related: ["[[planning-board]]"]
---

# iPad — Planning board (draft-2, future)

## Layout (11″ landscape, 1210 × 834)

**Primary target: iPad 11″** — landscape 1210 × 834 pt, portrait 834 × 1210 pt. A 13″ iPad gets the same layout with more room.

- Toolbar: `Planning board`, `Scenario A · 6 projects · next 12 months`, segmented `Scenario A | Scenario B`, future badge.
- **Weekly load card**: stacked bar 0–30 h/week (one neutral hue in two steps, 2 pt gaps, labels `🎻 4.5`). Capacity rule `capacity 22 h/week`; overflow hatched. Fact row: **`Doesn't fit by 4 h/week — Italian and Math would move.`** + `Lower a level, or accept the later dates.` + button `Find a fit…` (assistant suggestion, later).
- **Board**: rows 68 pt, columns 200 · 176 · 170 · timeline 410 · finish: emoji + project + line · compact segmented `min | normal | max` (36 pt control, 44 pt hit area) · short slider (84, knob 28) + value · timeline Oct 2026 → Sep 2027 with p10–p90 band, p50 tick, dashed ghost when capacity pushes a project later · finish + note.
- Floating HUD over the timeline: `Pinch to zoom · 12 months`. Footer: legend + `Pinch the timeline: 12 → 6 → 3 months · two-finger drag to pan`.

## Behaviour

- Pinch on the timeline zooms the shared x-scale (12 / 6 / 3 months, smooth in between); two-finger drag pans. All rows share the scale.
- Level and slider changes recompute the whole board (load, bands, the fit sentence) live.
- Projects that would move show their ghost and `would move +N weeks`; nothing is marked red or "late".

## SwiftUI

One `Chart` with y = project for the timelines (shared scale), `.chartXScale(domain:)` bound to a zoom state driven by `MagnifyGesture`; rows in a `Grid` aligned to the chart. Load bar: `Chart` with stacked `BarMark` + `RuleMark`.

## Acceptance

- [ ] Zoom keeps the bands aligned across rows.
- [ ] The overload sentence names the projects that actually move.
- [ ] Every control ≥ 44 pt hit area (segmented 40 pt + padding).
