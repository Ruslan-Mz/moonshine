---
title: iPad — Quarterly review
status: draft-2
date: 2026-10-01
artboards:
  [
    mockups/iPadQuarter.dc.html,
    mockups/iPadQuarterPortrait.dc.html,
    "+ -Dark variants",
  ]
related: ["[[quarterly-review]]"]
---

# iPad — Quarterly review (draft-2)

Same content as the Mac screen (`quarterly-review.md`): Q3 focus outcomes · Lines over the quarter · Q4 setup, including the reviewed-quarter selector `‹ Q3 2026 ›` in the toolbar (same default rule: the current quarter if it ends within 21 days, otherwise the previous one; swipe or ⌘← / ⌘→ steps quarters, same as Month). Note lookups and the statistics range derive from the reviewed quarter; edge ISO weeks are drawn partial. The iPad is where the owner does this review.

## Layout

**Primary target: iPad 11″** — landscape 1210 × 834 pt, portrait 834 × 1210 pt. A 13″ iPad gets the same layout with more room.

- **Landscape (11″)**: sidebar hidden; toolbar with `Quarter note` and `Open Квартал_2026-Q4`; full-width scrolling main column (artboard at full scroll height 1240). The previous quarter note opens as a **sheet** from the toolbar — a permanent side panel would squeeze the lines table. On 13″ it may stay as a side panel (360).
- **Portrait** (834 × 1210): main column full width with narrower columns (Line 132 · Tier 92 · 13 weeks 180 · Sessions 112 · Tasks 56 · Facts wrap); the quarter note is a **sheet** (medium detent, grabber, `Open in Obsidian`), dismissible and draggable to large.

## Data / Behaviour

As on the Mac. Read-only; links open Obsidian or OmniFocus. Rows that link get a 44 pt hit area even where the text row is 36 pt.

## SwiftUI

Landscape: `HStack { ScrollView; NoteView }` or `.inspector` (it becomes a sheet automatically in compact/portrait). Portrait: `.sheet(isPresented:)` with `.presentationDetents([.medium, .large])` and `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`.

## Acceptance

- [ ] Rotating keeps the scroll position and shows/hides the note correctly.
- [ ] No percentages or scores; outcomes are glyph + text.
