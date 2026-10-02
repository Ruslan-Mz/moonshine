---
title: iPad — shell and Today
status: draft-2
date: 2026-10-01
platform: iPadOS 26
artboards:
  [
    mockups/iPadToday.dc.html,
    mockups/iPadToday-Dark.dc.html,
    mockups/iPadToday-Mixed.dc.html,
    mockups/iPadToday-Mixed-Dark.dc.html,
  ]
related: ["[[platforms]]", "[[today]]"]
---

# iPad — shell and Today (draft-2)

The iPad is the **planning studio** (`platforms.md`). Today exists there so the shell is complete. Its content is the Mac Today re-laid out for touch.

## Layout (11″ landscape, 1210 × 834 pt)

**Primary target: iPad 11″** — landscape 1210 × 834 pt, portrait 834 × 1210 pt. A 13″ iPad gets the same layout with more room.

- **Sidebar** (floating, 300 wide, radius 22, `sidebar` token, inset 10): hide/show button + app name, search field (`⌘K` hint), views **Today · Week · Month · Lines · Plan** (44 pt rows, selected = accent fill), then lines **grouped by tier** (Foundation · Active this season · Maintenance · Not in focus — collapsed with count), 36 pt rows.
- **Toolbar**: large title 34 bold + subtitle (date · counts · estimate). Trailing glass group: search, refresh. When the sidebar is hidden, a leading sidebar button appears (see Week, Forecast).
- **Main column** (inset-grouped cards, radius 14, 56 pt rows):
  1. Anchors: label + `3 of 5 done`, then capsule chips (48 high): check 22 + title + line emoji. Up to 5 chips; the count covers all anchors (`3 of 6 done`); further anchors stay in their line sections (rule in `today.md`).
  2. Top 3 today (flagged), caption `5 flagged — 3 shown`.
  3. One card per line, foundation first; header = emoji + line + summary (`foundation · floor 1 h/day · 1 open · ≈ 40 min est.`).
  4. From earlier, with `· planned 3 days ago` in the meta line.
  5. Life ops: one collapsed row.
- **Inspector** (340, `.inspector`, **closed by default on 11″**, toggled from the toolbar; artboard `iPadToday-Mixed` shows it open with the sidebar hidden): Quarter focus card · Touched today (Rhythm | Progress columns) · Quiet lines card (Italian, quiet + next step; Japanese, no activity yet) · Not in focus line.

Task row: check 24 · title 17 · meta 13 (trace chip + estimate) · due badge (amber, real due only).

## Data

Same Overview service and demo data as Mac Today (`demo-data.md`, draft-2 additions). The iPad reads the replicated store (`platforms.md`, ADR-0010; sync is opt-in).

## Behaviour

- Tap a row: detail popover (trace, estimate, notes) with "Open in OmniFocus". Long-press: context menu (`ipad-interactions.md`).
- Check circles are read-only until writes exist; tapping opens OmniFocus.
- Sidebar and inspector are never both open by default on 11″ (the main column would drop below ~500 pt). Hardware keyboard: ⌘1–⌘5 views, ⌥⌘I inspector (Plan = ⌘5), ⌘K, ⌘R, arrow keys move the selection, ↵ opens.
- Sidebar hides with the button or a swipe. Its state persists per scene.

## SwiftUI

`NavigationSplitView(columnVisibility:)` with `.navigationSplitViewStyle(.balanced)`. Sidebar `List(selection:)` with `Section`s per tier and `DisclosureGroup` for Not in focus. Detail: `ScrollView` + `LazyVStack` of `GroupBox`-styled sections (or `List` with `.listStyle(.insetGrouped)`) and a trailing column through `.inspector` (regular width only). Anchors: `ScrollView(.horizontal)` of capsule buttons. Keyboard: `.keyboardShortcut` on `Commands`/buttons.

## Acceptance

- [ ] Every target ≥ 44 pt (chips, rows, toolbar buttons, sidebar rows).
- [ ] Amber only on the two real due dates; no red anywhere.
- [ ] Mixed-language titles (Today-Mixed): Hebrew titles render right-to-left inside an LTR row; CJK uses the right glyphs (`languageIdentifier`); truncation by grapheme.
- [ ] Light/dark; Dynamic Type up to XXL without clipped labels (the right column moves below the main column at XXL).
- [ ] VoiceOver: chips read "Anchor, Morning session, done".
