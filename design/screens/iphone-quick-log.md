---
title: iPhone — Quick log, practice timer, Live Activity
status: draft-2
date: 2026-10-01
platform: iOS 26
artboards:
  [
    mockups/iPhoneLog.dc.html,
    mockups/iPhoneTimer.dc.html,
    mockups/iPhoneLock.dc.html,
    mockups/iPhoneIsland.dc.html,
    "+ -Dark variants",
  ]
related: ["[[platforms]]"]
---

# iPhone — Quick log and practice timer (draft-2)

The phone writes **time entries** (MoonShine-native data, `platforms.md`). It never writes to OmniFocus or the vault.

## Layout

**Quick log sheet** (from the Log tab or the "+" in Today; 700 pt, large detent, grabber):

- Nav row: Cancel · `Log time` · Save.
- `LINE · recent first`: horizontal capsule chips (44 high); the selected one is filled with the accent.
- `MINUTES`: chips 10 · 15 · 20 · 30 · 45 · 60 in a 3 × 2 grid (48 high) + a stepper row (±5 min).
- `When` (default now, rounded to 5 min) and an optional note.
- Primary button: `Save 20 min to 🎻 Violin` (full width, 54). Secondary: `Start practice timer`.

**Practice timer sheet**: line + current next action, elapsed `18:42` (76 pt, tabular digits), `started 17:58 · running`; Pause (76 circle) and Stop & save (76, accent). Caption: stopping saves an N-minute time entry; the timer continues on the Lock Screen and in the Dynamic Island.

**Live Activity**:

- Lock Screen: emoji badge, `Violin · practice`, the next action, elapsed time in the accent colour; Pause and Stop & save buttons (44).
- Dynamic Island: compact (emoji · `18:42`), minimal (emoji only), expanded (title, subtitle, time, Pause / Stop & save).

## Data

`TimeEntry { lineID, start, minutes, note, source: quickLog | timer }`. Recent lines = last 7 days of entries, then foundation lines, then the vault order. A timer entry is created on Stop; Pause accumulates.

## Behaviour

- One-hand: all controls in the lower two thirds; Save is reachable with the thumb.
- Starting a timer while one runs asks to stop the first (a single timer at a time).
- No streaks or goals in the log. The line's rhythm updates after save.

## SwiftUI

`.sheet` with `.presentationDetents([.large])`; chips as `Button`s in `ScrollView(.horizontal)` / `Grid`; `Stepper`. Timer: `TimelineView(.periodic)` or `Text(timerInterval:)`. Live Activity: ActivityKit `ActivityAttributes` + WidgetKit `ActivityConfiguration` with `DynamicIsland { expanded; compactLeading; compactTrailing; minimal }`, App Intents for Pause and Stop.

## Acceptance

- [ ] A log takes ≤ 3 taps for the common case (line from recents, chip, Save).
- [ ] The timer survives app termination (Activity + persisted start time).
- [ ] The Live Activity uses no red; times use tabular digits.
