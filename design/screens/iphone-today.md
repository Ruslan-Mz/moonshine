---
title: iPhone — Today
status: draft-2
date: 2026-10-01
platform: iOS 26
artboards:
  [
    mockups/iPhoneToday.dc.html,
    mockups/iPhoneToday-RU.dc.html,
    mockups/iPhoneToday-XXL.dc.html,
    "+ -Dark variants",
  ]
related: ["[[platforms]]", "[[today]]"]
---

# iPhone — Today (draft-2)

The iPhone is **capture & glance**: what matters today, one hand, between things.

## Layout (6.3″, 402 × 874 pt)

- Large title `Today` + `Thursday, 1 October · 23 open`; search button (44).
- **Anchors**: `Anchors · 3 of 5 done`, capsule chips (44 high) that wrap: check + title + line emoji. Done chips are checked and dimmed, not hidden. Up to 5 chips; the count covers all anchors (`3 of 6 done`); further anchors stay in their line sections (rule in `today.md`).
- **Top 3 today**: inset-grouped card, `5 flagged — 3 shown`.
- **Line sections**, foundation first: card per line, rows 56 pt: check 24 · title 17 (one line) · meta 13 (`🎻 Bach Partita No. 2 · ≈ 45 min`) · due badge (amber, real due only).
- From earlier and Life ops follow below the fold (same as iPad).
- **Tab bar** (floating, iOS 26): Today · Week · Lines · Log.

## Data

Same Overview service; the phone shows the trace as line emoji + project (the full trace chip is in the detail sheet).

## Behaviour

- Tap a row: detail sheet (trace, estimate, notes, "Open in OmniFocus"). Swipe actions arrive with writes (the Act phase).
- Pull to refresh pulls the replicated store; no import runs on the phone.
- **Dynamic Type XXL** (artboard drawn with the type scale ×1.35): titles **wrap** instead of truncating, chips wrap to several lines, the tab bar keeps its size (labels shown through the Large Content Viewer).
- Russian UI: `Сегодня`, `открыто 23`, `Якоря · 3 из 5`, tab labels from the catalog.

## SwiftUI

`TabView` with `Tab`s; `NavigationStack` + `List(.insetGrouped)`; anchors in a custom flow `Layout`; `@ScaledMetric` for check size and row height; `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` tested.

## Acceptance

- [ ] At XXL nothing is clipped; at AX sizes rows grow, nothing overlaps the tab bar.
- [ ] One-hand reach: primary actions in the bottom half (tab bar, Log).
- [ ] VoiceOver order: anchors, Top 3, lines.

## Calendar (draft-3)

Artboards: `iPhoneToday-Cal`, `iPhoneToday-Cal-Dark`.

A **Next event** card at the top (`NextEventRow`): 3 pt calendar bar · `Next · 17:00–18:00` · `Violin lesson 🎻` · `in 40 min`. Below it one 44 pt row: `+ 1 more today` on the left, `4 h in calendar · ≈ 2 h 25 min free until 22:00` on the right (compact form: the `planned` term is left out, the free time already includes it); tapping expands the rest of the day's events. No events left today → the card is absent (no "nothing more today" message). No access → nothing is shown here; the quiet connect row lives in Settings on the phone.

**Acceptance.**

- [ ] The card never uses amber; `in 40 min` is semibold text.
- [ ] At Dynamic Type XXL the title wraps and the time stays on one line.
