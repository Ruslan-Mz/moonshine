---
title: iPad — Split View, compact width and 11″ portrait
status: draft-2
date: 2026-10-01
artboards:
  [
    mockups/iPadSplitHalf.dc.html,
    mockups/iPadSplitThird.dc.html,
    mockups/iPadSplitThirdForecast.dc.html,
    mockups/iPad11Today.dc.html,
    mockups/iPad11Week.dc.html,
    "+ -Dark variants",
  ]
---

# iPad — Split View and smaller layouts (draft-2)

The owner plans with OmniFocus open beside MoonShine. This spec says which screens must work at each width.

## Layout

| Width              | Size class | Navigation                                 | What works                                                                                                                | Artboard                               |
| ------------------ | ---------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| Full (1210 on 11″) | regular    | sidebar + content (+ inspector)            | everything                                                                                                                | iPad*                                  |
| ½ (≈ 600)          | compact    | bottom tab bar Today · Week · Lines · Plan | Today, **Week as a vertical day list**, Lines, Forecast summary                                                           | iPadSplitHalf                          |
| ⅓ (≈ 390)          | compact    | tab bar                                    | **Today list**, Week day list, **Forecast summary**                                                                       | iPadSplitThird, iPadSplitThirdForecast |
| 11″ portrait (834) | regular    | sidebar hidden by default                  | Today with the rail as a **horizontal card strip**; Week as **day rows** with horizontal cards; No plan as a bottom sheet | iPad11Today, iPad11Week                |

Compact Week: past days collapsed into one row (`Mon 28 – Wed 30 · 14 done · 2 still open`), then one section per day from today. Compact Forecast: p50, range, mini band, the sentence, level segmented; steps, drift and the fine slider ask for more width (`Open full width`). Planning board and the review's three-column panel are regular-width only; in compact they show a one-line explanation, never a broken layout.

## Behaviour

Width changes live (Split View / Stage Manager resize). Selection and scroll position survive the change. The OmniFocus pane in the mock is a placeholder.

## SwiftUI

`@Environment(\.horizontalSizeClass)`; `NavigationSplitView` collapses to a stack automatically; a `TabView` drives compact navigation (`.tabViewStyle(.sidebarAdaptable)` gives tab bar ↔ sidebar for free on iPadOS 26). Week compact: `List` with `Section` per day. 11″ Week: `ScrollView` of rows, each row `ScrollView(.horizontal)`.

## Acceptance

- [ ] At ⅓ width, Today and the forecast summary have no clipped text in EN and RU.
- [ ] Resizing between ⅓, ½ and full never loses the selection.
- [ ] No screen renders a squeezed regular layout in compact width.
