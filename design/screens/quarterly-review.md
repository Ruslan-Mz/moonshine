---
title: Quarterly review
status: draft-2
date: 2026-10-01
slice: R1 — own slice, scheduled to land before the Q4 review (by 2026-12-28); read-only
artboards: [mockups/QuarterReview.dc.html, mockups/QuarterReview-Dark.dc.html]
related: ["[[week]]"]
---

# Quarterly review (draft-2)

The owner's end-of-quarter ritual: look back at the quarter's artifacts and lines, then set up the next quarter. **Read-only.** The app shows facts and questions. Decisions are written in the quarter note in Obsidian (writes come in the Act phase).

Opened from: ⌘K ("Quarterly review"), a second footer link `Open quarter review` that R1 adds to the Quarter focus card (next to phase 1's `Open quarter note`, `components.md`) and, during the first 14 days of a quarter, a link in the Today rail. No sidebar item for now.

## Reviewed quarter

A selector `‹ Q3 2026 ›` in the toolbar (⌘← / ⌘→ step quarters, same as Month) picks the **reviewed quarter**. Default: the current quarter if it ends within 21 days, otherwise the previous one (on 2026-12-28 → Q4 2026, set-up for Q1 2027; on 2026-10-02 → Q3 2026). Everything derives from the reviewed quarter: the quarter note looked back on, the next quarter's note for the setup, and the statistics range (its ISO weeks; edge weeks that cross the quarter boundary are drawn partial). The text below uses Q3 2026 as the example.

## Layout (artboard drawn at full scroll height, 1440 × 1280)

Toolbar: quarter selector `‹ Q3 2026 ›` + `review`, subtitle `July – September · 14 ISO weeks · read-only — decisions go into the quarter note`, button `Open Квартал_2026-Q4`.

1. **Q3 focus — what happened.** One row per artifact in the previous quarter note: status glyph · line emoji · artifact · outcome · evidence · `Open in Obsidian`.
   - Outcomes: `done` (check), `carried to Q4` (arrow), `to decide` (dashed circle). Neutral colours only. `to decide` is in primary text so it stands out without colour.
   - Evidence is one plain fact (`learned by 18 Sep`, `line quiet since 2 Sep · exam date not booked`).
2. **Lines over the quarter.** Columns: Line · Tier · quarter sparkline (one rhythm/progress pair per ISO week that intersects the quarter, 4 pt bars; boundary weeks drawn partial) · `Sessions · avg / week` · Tasks done · Facts (dip and return, quiet since, paused since, no activity yet). Ordered by tier. Caption: hours per line arrive with the hours-tracker import (phase 2).
3. **Q4 setup.**
   - Left: chips by tier for the next quarter (Foundation with floor, Active this season, Maintenance, Not in focus). When there are more than 5 active lines, a neutral fact row: `7 active lines — the plan says 3–5. Move one or two to maintenance or not in focus?`
   - Right: the Q4 focus artifacts (from the next quarter note), then **Questions for this review**, each with a link to where it is answered (Obsidian note, budget note, OmniFocus).

Right inspector 340: the previous quarter note, read-only (frontmatter + body), "Open in Obsidian".

## Data and contract

- Previous and next quarter notes: `scale: quarter`, `quarter: YYYY-Qn`, `artifacts:` list (see README "Contract changes").
- **Artifact outcome (resolved).** Artifacts are **list items** in the quarter note's `artifacts:` frontmatter (vault contract §artifacts), not separate notes, so the outcome lives on the list item, reusing the existing `status` field plus two optional keys:

  ```yaml
  artifacts:
    - id: q3-recital-programme
      title: Recital programme chosen
      line: violin
      status: done # planned | in_progress | done | dropped (unchanged contract)
      done: 2026-09-18 # optional, date the artifact was finished
      carried_to: 2026-Q4 # optional, set during the review
  ```

  Outcome shown: `status: done` → **done**; `carried_to` present → **carried to Q4**; `status: dropped` → **dropped on purpose**; anything else → **to decide**. No new enum; the owner sets `carried_to` / `status` in Obsidian during the review. A linked completed project never overrides what the note says (the note is the truth, ADR-0004).

- **"The plan says 3–5"** is data, not a constant: budget note frontmatter `active_lines: {min: 3, max: 5}` (owner's rule from the strategy notes). Absent → the row is not shown.
- **Week buckets are derived from the quarter's date range**: every ISO week that intersects it (Q3 2026 = 1 Jul–30 Sep = W27–W40, 14 buckets). A boundary week shared with the next or previous quarter counts only its days inside the quarter and is drawn partial. The mockups still draw 13 weeks; the spec wins.
- Line facts come from the Stats service over those weeks; "dip" means two or more consecutive weeks below 50 % of the line's quarter median.

## Tone

No scores, percentages, grades or streaks. "to decide", never "failed" or "missed". The "too many active lines" row is a question, not a warning.

## SwiftUI

`ScrollView` with three `GroupBox`-like cards + `.inspector`. Focus rows and lines: `Grid` (or `Table` for lines). Sparklines: the shared Swift Charts sparkline with one pair per quarter week (13 or 14). Chips: `FlowLayout` (custom `Layout`).

## Acceptance

- [ ] Every number is traceable to the store (sessions, tasks) or to a note (artifacts, tiers).
- [ ] No amber anywhere on this screen (no real due dates shown here).
- [ ] Works with no previous quarter note: section 1 shows "No quarter note for Q3", the rest still renders.
- [ ] Checked in Russian.
- [ ] With `active_lines` absent, no "too many active lines" row appears.

## My take (draft-4)

Artboards: `QuarterReview-Take`, `QuarterReview-Take-Dark` (1440 × 1560).

### Layout

- **Lines over the quarter**: each line's sparkline gets a strip of `TakeMark`s (8 pt, Leap 10 pt) under its weeks, one slot per ISO week of the quarter. Row height 46 (was 36). The legend gains `My take — set by you` and `dashed = draft`. A line with takes has a disclosure chevron at the end of the row; opened, its takes are listed below in week order: `W35 · Rise — Allemande bars 1–8 from memory`, `W36 · Leap — Vibrato finally works`, `W38 · Rise`, `W39 · Steady`. Drawn opened: 🎻 Violin.
- **Focus outcomes** ("Q3 focus — what happened"): under an artifact's title, the Leaps of its line in the quarter as supporting notes — `✦ W36 · my take: Leap — “Vibrato finally works”`. A draft Leap is shown with the dashed mark and `(draft)`. Other directions are not listed here.
- No column counts takes; no line is ranked by them.

### Data

Takes and drafts of every line for the quarter's ISO weeks. Artifact → line from the quarter note (`artifacts[].line`).

### Behaviour

Read-only, like the rest of the review: marks and notes are shown, not edited (the journal in Line detail is the place to change them). The chevron state is view state.

### SwiftUI

Same sparkline + mark strip as Lines, with 13 or 14 slots. Opened notes: a `DisclosureGroup` row content.

### Acceptance

- [ ] 🤖 AI/ML shows one spark (W37), one ▶ (W39) and a dashed ▷ (W40 draft) in an otherwise blank strip; the spark is found at a glance.
- [ ] 📐 Math shows a dashed spark in W38, and the artifact "Linear algebra, chapters 1–2" lists it as `(draft)`.
- [ ] No counts, sums or averages of takes; no amber.
