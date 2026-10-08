---
title: Design principles
status: draft-2
date: 2026-10-01
---

# Design principles (draft-2)

## Direction: "calm density"

- One line per task. A day of ~25 tasks fits on a 1440×900 window without scrolling.
- Calm through typography and spacing, not through hiding data: section headers 14 pt semibold, rows 13.5 pt, metadata 11–12 pt in secondary or tertiary.
- Few containers. Lists are separated by hairlines. Cards appear only in the right rail and for quiet lines.
- No drop shadows on content. Shadows appear only on overlays (⌘K, sheets).
- Emoji identify lines; that is product data, not decoration. Every other glyph is an SF Symbol.

## Platform

- macOS 26, SwiftUI. Use `NavigationSplitView`, a toolbar with title and subtitle, `.inspector` for right rails and a bottom status bar via `.safeAreaInset(edge: .bottom)`.
- SF Pro and SF Mono only. No custom fonts.
- Light and dark from semantic colours. Custom tokens: `tokens.md`.
- Keyboard first: ⌘1–⌘4 switch views, ⌘K opens the palette, ⌘R refreshes, ↵ opens the selection, ⌘↵ opens it in OmniFocus or Obsidian.

## Window layout (as drawn)

| Region     | Size                                               | Notes                                                                             |
| ---------- | -------------------------------------------------- | --------------------------------------------------------------------------------- |
| Window     | 1440 × 900 (mock size)                             | Must also work at 1100 × 700: the rail collapses, columns truncate                |
| Sidebar    | 236                                                | Views (⌘1–⌘4), then the line list (emoji + name + state tag)                      |
| Toolbar    | 56                                                 | Title 19 bold + subtitle 12 secondary; search field (⌘K) and refresh on the right |
| Status bar | 28                                                 | "Demo data" badge, "Updated N min ago", shortcut hints                            |
| Right rail | 300 (Today) · 380 (Month note) · 360 (Line detail) | `.inspector`, can be hidden                                                       |

## Tone rules as UI constraints (hard)

1. **No red anywhere** for intentions, lines, drift or overload. The system red appears only in the window's close button.
2. **Amber is the only urgent colour.** It appears only on a task with a real external due date (`effectiveDueDate`), as a badge with a clock symbol and text. Never as a colour without text.
3. Never use "overdue", "failed", "behind", "late" or "missed". See `copy.md`.
4. Quiet lines are a fact plus a next step: "quiet for 29 days" + a suggested action.
5. Maintenance lines are never flagged as quiet. Paused lines are greyed and labelled "paused on purpose".
6. "Hours" / "h" appears only next to real time data or the vault values `budget_h_week` and `floor_h_day` (CLAUDE.md rule 8, ADR-0006): a weekly budget (`h/week`), a daily floor on any line (`floor 3 h/day`; on a line that is not a foundation line, a daily minimum next to its weekly budget), real time entries (phase 2+), or an estimate explicitly labelled as one (`≈ 1 h 30 min est.`; task estimates under an hour are `≈ 45 min est.`).
7. Rhythm (repeated sessions) and progress (one-off tasks) are always two separate numbers or series, never summed into a score.
8. Up and down are not coloured. Week-over-week comparisons are plain numbers with "avg".

## Charts

- Thin marks: 5 pt bars in sparklines, 2 pt lines, rounded data ends.
- One y-axis per chart. Two measures → two charts (e.g. drift date vs practice hours).
- A legend whenever there are two or more series. Text stays in text colours, never in series colours.
- A current, unfinished period is drawn at reduced opacity with a dashed outline and labelled "so far" or "partial".
- Uncertainty is a band (p10–p90) with a p50 tick. Never a single date without its range.

## The owner's model of a life, in the UI (draft-2)

The app mirrors how the owner already plans (Obsidian strategy notes). Every screen respects this structure:

| Tier                   | Meaning                                                                                                   | UI treatment                                                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Foundation**         | The spine: never negotiable, cut last (core practice, body). Has a **floor** (e.g. 3 h/day), not a budget | Always first; compact; floor shown next to it. Never "quiet" — a foundation line below its floor shows the fact, no warning colour |
| **Active this season** | 3–5 lines the current quarter is about                                                                    | Main area; quiet-line rules apply                                                                                                  |
| **Maintenance**        | Kept alive, not pushed                                                                                    | Neutral, never flagged                                                                                                             |
| **Paused on purpose**  | "Not in focus" — permission not to move                                                                   | Greyed, listed separately; the list itself is a feature, not a shame list                                                          |
| **Life ops**           | Household, inbox, system                                                                                  | Collapsed bucket, never a line                                                                                                     |

Domain blocks (Profession, Creative, Languages, …) become a secondary label, not the primary grouping.

Daily ritual the UI supports: **3 priorities + 5 anchors** (the owner's daily review). Anchors are tasks tagged `anchor` in OmniFocus; priorities are flagged tasks.

## Languages

English (base) and Russian in phase 1; see `i18n.md`. No string literals in views; plurals and dates through the String Catalog and `FormatStyle`; tone rules apply in every language; every acceptance check is also done in Russian.
