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
- Day grid: 7 columns (radius 16). Cards ≥ 56 pt: title (2 lines), line emoji, estimate, due badge if the task is a deadline due in this week (deadline rule, `settings.md` § Deadlines); other due dates in this week as plain text. Past days dimmed. At most 3 cards on 11″ (4 on 13″), then `+ N more`.
- **No plan tray** (bottom card, 200): grab handle, emoji, title, estimate in 4 columns. Caption: `Drag a card onto a day · writes to OmniFocus in the Act phase`.
- **Drag state** (drawn): the lifted card (scale 1.03, −2°, lift shadow) is over Friday; Friday gets an accent outline, a selection tint and the drop target `Drop to plan for Fri 2 Oct`; the source slot shows a dashed ghost.

**Weekly review (landscape)**: on 11″ the day grid **collapses to one row of day pills** (`Mon 28 · 5 done`) so the review gets the height. The tray is replaced by a 3-column panel of cards: Quiet lines + No next action | No plan · 12 | Real due dates next week + Notes. Each section has a "looked at" circle (44 pt hit area). No counter, no score.

**Weekly review (portrait, 834 × 1210)**: day pills on top; the three cards become a **horizontally swipeable** row (640 wide each, the next card peeks, page dots). Caption: `Swipe for more · facts only, nothing is scored`.

## Data

Week model as on Mac (placement: effective planned ?? defer ?? due). Review: quiet lines, projects without a next action, No plan, next week's real due dates, month and quarter notes.

## Behaviour

- Drag & drop from the tray (or between days) shows the full interaction now. Until writes exist (the Act phase), dropping shows a toast `Planning writes to OmniFocus in the Act phase` and the card returns.
- Pencil drag = finger drag. Pointer: cards lift on hover.
- ⇧⌘R toggles review mode; the mode persists per scene.
- Russian UI (iPadWeek-RU): labels from the catalog; user data untranslated.

## SwiftUI

Day grid: `Grid` or `HStack` of 7 `ScrollView` columns with `.dropDestination(for: TaskTransfer.self)`; cards `.draggable(TaskTransfer)` with a custom drag preview. Tray: `LazyVGrid(columns: 4)`. Portrait review: `ScrollView(.horizontal)` with `.scrollTargetBehavior(.paging)` and a page indicator. Mode: `Picker(.segmented)` in the toolbar.

## Acceptance

- [ ] All cards and tray items ≥ 44 pt high; drop targets ≥ 44 pt.
- [ ] The drag works with finger, Pencil and pointer; VoiceOver offers "Plan for…" as an accessibility action instead of drag.
- [ ] No writes before the Act phase (drop is a preview only).
- [ ] RU at 1376 and at Split View ½ without clipped labels.

## Calendar (draft-3)

Artboards: `iPadWeek-Cal`, `iPadWeek-Cal-Dark` (drag state), `iPadSplitHalf-Cal` (+ `-Dark`).

- Same event layer as Mac Week, sized for touch: event rows ≥ 44 pt (3 pt bar, time, title), `AllDayBar` 28 pt across its columns, per-day caption `2 h 30 min in calendar`.
- **While a task card is dragged**, every day from today on shows its free time as part of the drop target: the target day's label reads `Drop to plan for Fri 2 Oct · ≈ 11 h 30 min free`; the other days show a dashed pill, e.g. Thursday (today) `≈ 2 h 25 min free until 22:00` at 16:20 — today counts from now, future days use the whole day window (calendar and planned tasks with an estimate both reduce it, see `today.md` § Calendar). Days covered by an all-day event show `all day · Weekend in Sigulda` instead of hours.
- **Compact width** (Split View ½ and ⅓): events appear inside each day section, before the tasks, as rows with a dot, title, `time · calendar`; the section summary adds `· 4 h in calendar`.
- Events are not draggable and have no context-menu actions beyond `Open in Calendar`.

**Acceptance.**

- [ ] Free time appears only during a drag; it uses the same rule as the Today fact.
- [ ] Event rows meet 44 pt.

## My take (draft-4)

Artboards: `iPadWeekTake`, `iPadWeekTake-RU` (11″ landscape), `iPadWeekTakePortrait` (+ `-Dark`). Same model and rules as `week.md` § My take.

### Layout

- **Landscape**: the review panel gets the same two steps, `1 · Facts | 2 · My take` (36 pt segments). Step 2 is one card: `How did each line go?`, the legend, then one row per line (Foundation, Active this season). Row ≥ 52: emoji + name (+ floor) with the measured facts under the name · `TakeControl` with 78 × 44 segments (mark + word) · note field 44 high · `Confirm` pill 44 high. Rows with drafts show the dated drafts above the control line and `prefilled from 2 drafts →` in front of it. Maintenance lines follow under `More` at the end of the list (scroll).
- **Portrait**: the section is the **last swipeable card** (640 wide; the previous card peeks on the left; page dots). Collapsed rows are 60 pt: name + facts on the left, four icon-only segments (46 × 44, each with its word as the accessibility label) on the right, so a direction is still one tap. The legend with the words sits at the top of the card. The row being edited is expanded on the selection tint: drafts, the control with words (142 × 44 segments), the note field and `Confirm`.
- **Capture sheet**: `Note for my take` opens the same sheet as on the iPhone (`iphone-quick-log.md` § My take) as a popover, from Line detail and from a row's context menu in the review.

### Behaviour

Tap a segment to set the direction; tap the row (portrait) to expand it. Pencil and pointer behave like a finger; a hardware keyboard gets the Mac keys (`↑↓`, `1`–`4`, `↩`, `⌘↩`).

### SwiftUI

Landscape: `Grid` rows. Portrait: the card joins the paging `ScrollView`; rows are `DisclosureGroup`-like with a custom label holding the compact control.

### Acceptance

- [ ] Every segment, the note field and `Confirm` are ≥ 44 pt.
- [ ] One tap sets a direction in both orientations.
- [ ] Checked in Russian at 1210 pt (`Подтвердить`, `из 2 черновиков →`).

Not drawn: Split View ½ and ⅓. Rule: below 700 pt the portrait card layout is used.
