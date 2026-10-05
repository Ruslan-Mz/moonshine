---
title: Planning board (future)
status: draft-1
phase: future (2–3) — design direction only, do not build in phase 1
date: 2026-10-01
related: ["[[0006-plan-model-steps-effort-levels-simulated-forecast]]"]
artboards: [mockups/Board.dc.html, mockups/Board-Dark.dc.html]
---

# Planning board — FUTURE (draft-1)

## Layout

Toolbar: `Planning board`, subtitle `Scenario A · 6 projects · next 12 months`, scenario switch `Scenario A | Scenario B`.

1. **Weekly load card**: a stacked bar (0–30 h/week scale). One segment per project, one neutral hue in two alternating steps, 2-pt gaps, direct labels (`🎻 4.5`). A capacity rule at 22 with the label `capacity 22 h/week`. The part beyond capacity is hatched. Message row (band background, arrow symbol): **`Doesn't fit by 4 h/week — Italian and Math would move.`** + `Lower a level, or accept the later dates.` + button "Find a fit…" (assistant suggestion, later).
2. **Board**: header Project · Level · Effort · timeline Oct 2026 → Sep 2027 · Finish (p50). Rows (60): emoji + project + line; `Picker(.segmented)` min / normal / max; slider + value (`4.5 h/week`, or `3 sessions/week` for a session-based plan); timeline band p10–p90 with p50 tick; finish date + note (`would move +10 weeks`, `paced by recovery, not time`). Projects pushed by capacity show a dashed ghost band where they would land if they fitted, joined to the actual band by a thin line.
3. Legend + footer: `Changes recompute live · scenarios are saved, never applied automatically`.

## Example data

| Project                               | Level  | Effort          | p50                                        |
| ------------------------------------- | ------ | --------------- | ------------------------------------------ |
| 🎻 Bach Partita No. 2 — Allemande     | max    | 4.5 h/week      | 20 Nov                                     |
| 🇮🇹 Italian B1 course                  | normal | 2.5 h/week      | 10 Aug (would be early Jun)                |
| 📐 Linear algebra textbook            | normal | 4.5 h/week      | 5 May (would be early Mar)                 |
| 🤖 Eval toolkit v1                    | max    | 8 h/week        | 20 Jan                                     |
| 🔬 Practice-drift paper — first draft | normal | 3.5 h/week      | 15 Feb                                     |
| 💪 20 strict pull-ups                 | normal | 3 sessions/week | 10 Apr — max = normal because of `maxRate` |

Total 26 vs capacity 22.

## SwiftUI

`Grid` rows; one `Chart` for all timelines (y = project) so the x-scale is shared; `Slider(step: 0.5)` debounced 150 ms; simulation on a background actor with a fixed seed per scenario.

## Calendar (draft-3, future — direction only)

Artboards: `Board-Cal`, `Board-Cal-Dark`.

- The weekly load card names calendar time as a **separate neutral segment** on the same scale, never stacked into planned effort: `capacity 22 h/week · 15 h in calendar this week`.
- A multi-day trip is a neutral hatched band across the timeline, labelled with its title (`Conference trip · 3–9 Nov`). A forecast that moves because of it says so in plain words: `moves +1 week (trip 3–9 Nov)`, with the usual dashed ghost.
- Open: whether calendar time reduces capacity automatically (see README, draft-3 open questions).
