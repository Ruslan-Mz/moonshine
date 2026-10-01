---
title: iPhone — Line glance
status: draft-2
date: 2026-10-01
platform: iOS 26
artboards: [mockups/iPhoneLine.dc.html, mockups/iPhoneLine-Dark.dc.html]
---

# iPhone — Line glance (draft-2)

## Layout

Back `Lines`; large title `🎻 Violin`; `Active this season · Creative · 6 h / week`. Two **separate** metric cards: **Rhythm** (8 weeks, blue, dashed 4-week average, current week partial, `4 so far · avg 5.5`) and **Progress** (teal, `1 so far · avg 1.3`). A card with Last activity (`today · Scales (session)`) and **Suggested next step** (`Allemande, bars 1–16 at ♩ = 60 · ≈ 45 min est. · flagged`). Button `Open in OmniFocus`. Tab bar with Lines selected.

Quiet line variant: `quiet for 29 days` with the moon symbol under the title; foundation lines show `floor 3 h/day` instead of the budget.

## Data

Line detail model (8 weeks + averages, last completion, the line's flagged or first available next action).

## SwiftUI

`NavigationStack` push from Lines; two `Chart`s (`BarMark` + dashed `RuleMark`), `.accessibilityChartDescriptor` for VoiceOver values.

## Acceptance

- [ ] Rhythm and progress never combined into one number or chart.
- [ ] VoiceOver reads the eight weekly values as text.
