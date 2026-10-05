---
title: iPhone — Widgets
status: draft-2
date: 2026-10-01
platform: iOS 26
artboards: [mockups/iPhoneWidgets.dc.html, mockups/iPhoneWidgets-Dark.dc.html]
---

# iPhone — Widgets (draft-2)

## Layout

- **Small** (Home): `Anchors`, `3 of 5` (34 pt), five dots (3 filled), `Next: 👨‍👩‍👧 Evening reading`.
- **Medium** (Home): `Top 3 today` with three rows (check circle + emoji + title), then a hairline and the **next real due** (`Due 18:00 · Send recital repertoire list`, amber badge). No due today → the line is omitted, never "no deadlines!".
- **Lock Screen circular**: a ring of **5 segments** (3 filled) with `3/5` as text in the centre. No percentage and no progress-ring semantics beyond the segment count.
- **Lock Screen rectangular**: `Anchors 3/5` · `Next: Evening reading`.

## Data

Anchors and Top 3 from the replicated store; refreshed by timeline at the top of each hour and when the app saves a log or the store syncs.

## Behaviour

Tap opens Today (deep link to the anchor or task). Interactive check-off arrives with writes (the Act phase; App Intents).

## SwiftUI

WidgetKit `StaticConfiguration`, families `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular`; the segmented ring as five `Circle().trim` arcs; `.containerBackground(.fill.tertiary, for: .widget)`; vibrant rendering on the Lock Screen.

## Acceptance

- [ ] Every widget reads correctly in tinted/vibrant modes (no colour-only meaning).
- [ ] VoiceOver: "Anchors, 3 of 5 done".

## Calendar (draft-3)

Artboards: `iPhoneWidgets-Cal`, `iPhoneWidgets-Cal-Dark`.

- **Small**: `Next` · `17:00` · `● Violin lesson 🎻` · `in 40 min`, then a hairline and `Anchor: 👨‍👩‍👧 Evening reading`.
- **Medium**: left half = next event and the one after (`● 18:30 Parents' evening`); right half = `Anchors 3 of 5`, dots, `Next: Evening reading`.
- **Lock Screen rectangular**: `17:00 Violin lesson` / `Anchor: Evening reading`.
- `in 40 min` uses `Text(date, style: .relative)` so it stays current without a timeline reload. Without calendar access the widgets fall back to the draft-2 layouts.
