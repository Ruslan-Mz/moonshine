---
title: MoonShine — design hand-off
status: draft-2
date: 2026-10-01
source: Claude Design canvas "MoonShine" (https://claude.ai/code/artifact/7460e302-ab39-4778-93bb-a7a04493b244)
related:
  - "[[VISION]]"
  - "[[phase-1-see]]"
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
---

# MoonShine — design hand-off (draft-2)

> **Status: draft-2** (specs refined against the owner's planning system — where a spec and a mockup differ, **the spec wins**). Draft-1: These are the first design specs for implementing the views. Expect changes. If a spec here conflicts with `docs/VISION.md`, `docs/specs/phase-1-see.md` or an ADR, **those documents win**. Flag the conflict; don't silently pick one.

## What is here

| File                              | Purpose                                                                                                                                                    |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `principles.md`                   | Visual direction, layout grid, tone rules as UI constraints                                                                                                |
| `tokens.md` / `tokens.json`       | Colours (light/dark), type scale, spacing, radii. JSON is machine-readable                                                                                 |
| `copy.md`                         | Wording rules and the canonical strings                                                                                                                    |
| `components.md`                   | Reusable views: task row, trace chip, line header, due badge, sparkline, quiet-line card, states, status bar                                               |
| `screens/*.md`                    | One spec per screen: layout, data, behaviour, SwiftUI mapping, acceptance checks                                                                           |
| `demo-data.md`                    | The invented dataset used in the mockups (a seed for `DemoVault` fixtures)                                                                                 |
| `i18n.md`                         | Languages: UI waves (EN+RU now, 13 later, RTL/CJK-ready), switching, plurals, and multilingual content (rendering, detection, search)                      |
| `platforms.md`                    | Mac = hub, iPad = planning studio, iPhone = capture & glance; design rules for touch; sync consequence                                                     |
| `prompts/claude-design-mobile.md` | Prompt for the iPad & iPhone design round (same Claude Design project, new page)                                                                           |
| `tone-glossary.md`                | Tone terms and banned words per language                                                                                                                   |
| `mockups/*.dc.html`               | Exact source of every artboard: values for paddings, sizes and colours. **Reference only.** Design Component format, so it won't render outside the canvas |

## Screens

| Screen                       | Spec                              | Phase                                                    | Artboards                             |
| ---------------------------- | --------------------------------- | -------------------------------------------------------- | ------------------------------------- |
| Today                        | `screens/today.md`                | 1 (S4)                                                   | `Today`, `Today-Dark`                 |
| Lines                        | `screens/lines.md`                | 1 (S4)                                                   | `Lines`, `Lines-Dark`                 |
| Line detail                  | `screens/line-detail.md`          | 1 (S4)                                                   | `LineDetail`, `LineDetail-Dark`       |
| Week                         | `screens/week.md`                 | 1 (S5)                                                   | `Week`, `Week-Dark`                   |
| Month                        | `screens/month.md`                | 1 (S5)                                                   | `Month`, `Month-Dark`                 |
| ⌘K palette                   | `screens/command-palette.md`      | 1 (S5)                                                   | `Palette`, `Palette-Dark`             |
| Settings + status bar        | `screens/settings.md`             | 1 (S4)                                                   | `Settings`, `Settings-Dark`           |
| Project forecast             | `screens/forecast.md`             | **future** (2–3)                                         | `Forecast`, `Forecast-Dark`           |
| Planning board               | `screens/planning-board.md`       | **future** (2–3)                                         | `Board`, `Board-Dark`                 |
| Weekly review (mode of Week) | `screens/week.md` § Weekly review | 1 (S5, first to cut)                                     | `WeekReview`, `WeekReview-Dark`       |
| Quarterly review             | `screens/quarterly-review.md`     | **R1** — own slice, before the Q4 review (by 2026-12-28) | `QuarterReview`, `QuarterReview-Dark` |

Each `*-Dark` artboard is a wrapper that renders the light one with `dark = true`. The real values are in the light file's `theme()` function.

## How to use this (for Claude Code)

1. Read `principles.md`, `copy.md` and `tokens.md` once. They apply to every view.
2. For a slice, read the matching `screens/*.md` and the `components.md` entries it references.
3. Use system semantic colours (`.primary`, `.secondary`, `.separator`, fills) wherever they exist. Custom tokens (due amber, rhythm, progress) live in an asset catalog with light/dark variants.
4. Build views against `DemoVault` first. `demo-data.md` lists the data the mockups assume.
5. Before closing a slice, run the screen's **Acceptance** checklist and the tone review in `copy.md`.

## Decisions taken in the design round

- Direction: **hybrid**. Dense, one-line rows with columns (from option B) inside calm typography and an airy right rail (from option A). Options A and B stay on the canvas page "Today directions" for history.
- Rhythm and progress are two series with two colours (blue / teal, checked for colour-blind separation) and are never summed.
- Month uses a fixed-order **dot strip per day** (one dot slot per line) plus a soft tint for total activity.
- A new line state appears in the data: an active line with no completions shows "no activity yet" (example: 🇯🇵 Japanese).
- Settings: the spec recommends a native `Settings` scene (⌘,). The canvas draws it as a sheet so it is visible next to the window.

## Resolved in draft-2

- Life ops expansion is **remembered** (`@SceneStorage`).
- Week shows **completed tasks on past days, dimmed**.
- Month **opens on the current month**; ⌘← / ⌘→ step months.
- Sidebar line list is **grouped by tier** (Foundation · Active · Maintenance · Paused), collapsible — same order as Lines.

## Draft-2 changes (from the owner's planning system)

1. **Tiers instead of domain blocks** as the primary grouping: Foundation (spine, has a daily floor) → Active this season → Maintenance → Paused on purpose ("Not in focus"). Domain block becomes a secondary label. → `principles.md`, `screens/lines.md`.
2. **Today supports the daily ritual "3 priorities + 5 anchors"**: an Anchors strip (`anchor`-tagged tasks) and a Top 3 section (flagged), foundation lines first. → `screens/today.md`, `components.md`.
3. **Quarter focus card** in the Today rail (current quarter's artifacts). → `screens/today.md`.
4. **Weekly review mode** inside Week (Sunday ritual), first to cut. → `screens/week.md`.
   4b. **Quarterly review** screen (R1, read-only; decisions stay in the quarter note in Obsidian). → `screens/quarterly-review.md`.
5. **Month context chips** slot reserved for the hours tracker's "where I was" rows (phase 2). → `screens/month.md`.
6. **Languages**: UI in waves (EN+RU in phase 1, then LV/IT/DE, up to 13 incl. RTL and CJK), in-app switch; **multilingual content** rendered, detected and searched correctly in any script. → `i18n.md`, `tone-glossary.md`, `copy.md`, `screens/settings.md`, ADR-0009.

## Contract changes these need (vault contract v0.2, `docs/discovery/vault-contract.md`)

- Budget note `lines:` gains optional `foundation: true` and `floor_h_day: <number>` (foundation lines have a floor instead of `budget_h_week`).
- OmniFocus: the meta tag `anchor` (under the work-type group) marks anchors; flagged = priority. Both already exist in the snapshot (tags by id, `flagged`).
- Quarter note with `scale: quarter` and an `artifacts:` list (same shape as the year note) feeds the Quarter focus card.
- Optional `language: <BCP-47>` on a line (language lines) — parsed in S3b; a detection hint and, later, per-language exposure.
- Quarter note `artifacts:` items: optional `done: <date>` and `carried_to: <YYYY-Qn>` (quarterly review outcome) — **parsed from R1**; fixtures may contain them earlier.
- Budget note: optional `active_lines: {min, max}` — the owner's "3–5 active lines" rule as data — **parsed from R1**.

## Follow-up for Claude Design (to bring the mockups to draft-2)

Paste into the same Claude Design project:

```
Update the MoonShine artboards to design draft-2 (read design/README.md "Draft-2 changes", principles.md, i18n.md, screens/today.md, screens/lines.md):
1. Today: add the Anchors strip and the "Top 3 today" section above the line sections; foundation lines (🧘 Core practice, 💪 Calisthenics) first; Quarter focus card at the top of the right rail. Use design/demo-data.md "Draft-2 additions".
2. Lines: group by tier (Foundation · Active this season · Maintenance · Not in focus — on purpose, collapsed); domain block as a small label under the name; foundation rows show "floor 3 h/day" in the Budget column.
3. Sidebar: lines grouped by the same tiers.
4. Settings: add General → Language (System · English · Русский).
5. Add Russian variants of Today and Lines (artboards Today-RU, Lines-RU) using the RU strings in copy.md, to check text length and plurals.
6. Add one artboard Today-Mixed where task titles are in several languages and scripts (Russian, Italian, German, Chinese, Hebrew) to check glyphs, bidi and truncation, and one Today-RTL in a Hebrew UI to check mirroring.
Keep all tone rules. Light and dark.
```

## iPad & iPhone (draft-2)

**Primary iPad: 11″** (landscape 1210 × 834 pt, portrait 834 × 1210 pt); 13″ gets the same layouts with more room. Roles from `platforms.md`: **iPad = planning studio**, **iPhone = capture & glance**, Mac = hub. Same tokens, tone rules, copy and demo data. Every artboard exists in light and dark (`*-Dark`). Canvas pages: "iPad · planning studio" and "iPhone · capture & glance".

| Screen                                 | Spec                               | Artboards                                                                                |
| -------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------- |
| iPad shell + Today                     | `screens/ipad-shell-today.md`      | `iPadToday`, `iPadToday-Mixed` (RU, IT, DE, ZH, HE, LV titles)                           |
| iPad Week — planning + drag            | `screens/ipad-week.md`             | `iPadWeek`, `iPadWeek-RU`                                                                |
| iPad Weekly review                     | `screens/ipad-week.md`             | `iPadWeekReview` (landscape), `iPadWeekReviewPortrait` (swipeable cards)                 |
| iPad Project forecast (future)         | `screens/ipad-forecast.md`         | `iPadForecast` — the effort slider is live in Play mode                                  |
| iPad Planning board (future)           | `screens/ipad-planning-board.md`   | `iPadBoard`                                                                              |
| iPad Quarterly review                  | `screens/ipad-quarterly-review.md` | `iPadQuarter`, `iPadQuarterPortrait` (note as sheet)                                     |
| iPad Split View / compact / 11″        | `screens/ipad-split-view.md`       | `iPadSplitHalf`, `iPadSplitThird`, `iPadSplitThirdForecast`, `iPad11Today`, `iPad11Week` |
| iPad Pencil & pointer                  | `screens/ipad-interactions.md`     | `iPadInteractions`                                                                       |
| iPhone Today                           | `screens/iphone-today.md`          | `iPhoneToday`, `iPhoneToday-RU`, `iPhoneToday-XXL`                                       |
| iPhone Quick log, timer, Live Activity | `screens/iphone-quick-log.md`      | `iPhoneLog`, `iPhoneTimer`, `iPhoneLock`, `iPhoneIsland`                                 |
| iPhone Widgets                         | `screens/iphone-widgets.md`        | `iPhoneWidgets`                                                                          |
| iPhone Line glance                     | `screens/iphone-line-glance.md`    | `iPhoneLine`                                                                             |

Mock conventions: no status bar is drawn (the system draws it). The iPhone XXL artboard approximates Dynamic Type by scaling the content ×1.35 with wrapping on; the real build uses Dynamic Type. The forecast slider uses a stand-in model (p50 = remaining 18 h ÷ h/week), not the engine.

### Open questions (iPad & iPhone)

1. ~~**Sync ADR**~~ **Resolved: ADR-0010** — CloudKit private database via `CKSyncEngine`, the Mac is the only importer, native data multi-writer; sync is opt-in, off by default, with explicit consent in Settings.
2. **Time entries vs the hours tracker** (Excel import, phase 2). **Answer:** keep both entries per (line, day); totals use the larger of the two. Details decided in the phase-2 spec.
3. **Drag before phase 6.** **Open** — decided in the 3b spec. Preferred: the iPad writes a _planning intent_ (native data), and the Mac applies it to OmniFocus with confirm + undo once writes exist; needs its own ADR.
4. **Plan tab / sidebar item** on iPad. **Answer:** shortcut ⌘5; its landing screen is designed in 3b.
5. **Compact width** for Planning board and the review panel. **Answer:** accepted — a one-line explanation, as specified.
6. **RTL on iPad/iPhone.** **Answer:** an iPhone RTL artboard comes with the HE/AR language wave.
7. **Widgets**: refresh budget, and whether interactive check-off (App Intents) waits for phase 6.
