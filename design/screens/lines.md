---
title: Lines
status: draft-2
date: 2026-10-01
slice: S4
artboards: [mockups/Lines.dc.html, mockups/Lines-Dark.dc.html]
---

# Lines (draft-2)

## Layout

Toolbar: `Lines`, subtitle `11 lines · 2 foundation · 7 active · 1 maintenance · 1 paused`.

Legend row: rhythm swatch "Rhythm — repeated sessions per week", progress swatch "Progress — one-off tasks done per week", "current week, partial", and "Weeks 33–40" on the right.

Table columns (widths as drawn): Line 230 · State 170 · Budget 92 · Last 8 weeks 190 · Last activity 170 · Next actions 104 · Estimated this week (flex). Rows 46. **Draft-2:** a `Block` label (11, tertiary) under the line name replaces block sections; the Budget column shows the floor for foundation lines (`floor 3 h/day`).

~~Block sections~~ (draft-1). **Draft-2: tier sections** in this order: **Foundation · Active this season · Maintenance · Paused on purpose** (see `principles.md`). Header: tier name 13 bold + `2 lines · 9 h / week` (foundation: `floor 4 h/day`). Inside a tier, vault order. The paused section is titled `Not in focus — on purpose` and is collapsed by default (count visible).

Cells:

- Line: emoji 17 + name 14 semibold.
- State: `LineStateLabel`.
- Budget: `6 h / week` from the vault, `—` when unset.
- Sparkline: see `components.md`.
- Last activity: `today` / `yesterday` / `29 days ago` (maintenance: neutral) / moon + `quiet for 29 days` / `no activity yet` / `paused since 14 July`.
- Next actions: count of available next actions.
- Estimated this week: `≈ 6 h 40 min est.` (sum of task estimates planned this week); `—` if none.

The selected row has the `selection` fill and a chevron: ↵ opens Line detail.

## SwiftUI

`Table` with `Section`s per tier; the sparkline column hosts a small Swift Charts `Chart`. Navigation to detail via `NavigationStack` (`.navigationDestination(for: Line.ID.self)`).

## Acceptance

- [ ] Ordering: tier order (foundation → active → maintenance → paused), then vault order.
- [ ] Foundation lines are never shown as quiet; below-floor is a plain fact.
- [ ] Checked in Russian at 1440×900 and 1100×700 (no clipped labels).
- [ ] Current week visibly partial in every sparkline.
- [ ] Rhythm and progress never summed; both visible even when one is zero (baseline only).
- [ ] The word "hours" or "h" appears only in the Budget column, tier summaries and estimates labelled `est.`.
