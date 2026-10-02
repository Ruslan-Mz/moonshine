---
title: iPad — Week planning and weekly review
status: draft-2
date: 2026-10-01
platform: iPadOS 26
artboards:
  [
    mockups/iPadWeek.dc.html,
    mockups/iPadWeek-RU.dc.html,
    mockups/iPadWeekReview.dc.html,
    mockups/iPadWeekReviewPortrait.dc.html,
    "+ -Dark variants",
  ]
related: ["[[week]]", "[[platforms]]"]
---

# iPad — Week (draft-2)

The iPad's main job: **plan the week** and run the **Sunday weekly review**.

## Layout

**Primary target: iPad 11″** — landscape 1210 × 834 pt, portrait 834 × 1210 pt. A 13″ iPad gets the same layout with more room.

**Planning (11″ landscape)**, sidebar hidden to give the days room:

- Toolbar: sidebar button · `Week 40` + range · segmented **Plan | Weekly review** · ‹ Today › group.
- Line strip: one row of 10 compact cells (emoji, line, rhythm `4 (4.0)`, progress `1 (1.0)` — the number in brackets is the 4-week average). Plain numbers, no colour for up or down.
- Day grid: 7 columns (radius 16). Cards ≥ 56 pt: title (2 lines), line emoji, estimate, due badge if the real due date falls in this week. Past days dimmed. At most 3 cards on 11″ (4 on 13″), then `+ N more`.
- **No plan tray** (bottom card, 200): grab handle, emoji, title, estimate in 4 columns. Caption: `Drag a card onto a day · writes to OmniFocus in phase 6`.
- **Drag state** (drawn): the lifted card (scale 1.03, −2°, lift shadow) is over Friday; Friday gets an accent outline, a selection tint and the drop target `Drop to plan for Fri 2 Oct`; the source slot shows a dashed ghost.

**Weekly review (landscape)**: on 11″ the day grid **collapses to one row of day pills** (`Mon 28 · 5 done`) so the review gets the height. The tray is replaced by a 3-column panel of cards: Quiet lines + No next action | No plan · 12 | Real due dates next week + Notes. Each section has a "looked at" circle (44 pt hit area). No counter, no score.

**Weekly review (portrait, 834 × 1210)**: day pills on top; the three cards become a **horizontally swipeable** row (640 wide each, the next card peeks, page dots). Caption: `Swipe for more · facts only, nothing is scored`.

## Data

Week model as on Mac (placement: effective planned ?? defer ?? due). Review: quiet lines, projects without a next action, No plan, next week's real due dates, month and quarter notes.

## Behaviour

- Drag & drop from the tray (or between days) shows the full interaction now. Until writes exist (phase 6), dropping shows a toast `Planning writes to OmniFocus in phase 6` and the card returns.
- Pencil drag = finger drag. Pointer: cards lift on hover.
- ⇧⌘R toggles review mode; the mode persists per scene.
- Russian UI (iPadWeek-RU): labels from the catalog; user data untranslated.

## SwiftUI

Day grid: `Grid` or `HStack` of 7 `ScrollView` columns with `.dropDestination(for: TaskTransfer.self)`; cards `.draggable(TaskTransfer)` with a custom drag preview. Tray: `LazyVGrid(columns: 4)`. Portrait review: `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` and a page indicator. Mode: `Picker(.segmented)` in the toolbar.

## Acceptance

- [ ] All cards and tray items ≥ 44 pt high; drop targets ≥ 44 pt.
- [ ] The drag works with finger, Pencil and pointer; VoiceOver offers "Plan for…" as an accessibility action instead of drag.
- [ ] No writes in phase 1–5 (drop is a preview only).
- [ ] RU at 1376 and at Split View ½ without clipped labels.
