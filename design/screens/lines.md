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

## My take (draft-4)

Artboards: `Lines-Take`, `Lines-Take-RU` (+ `-Dark`).

### Layout

- **Third track in the sparkline.** Under the baseline of each row's eight-week bars, a 12 pt track of `TakeMark`s (9 pt, Leap 12 pt), one slot per week, centred under that week's pair of bars. Blank weeks stay blank, including the week in progress. Row height 54 (was 48).
- **This week's chip.** In the Last activity cell, under the text: `TakeChip` — `▶ Rise`, or with a dashed border `▷ Rise · draft`. Absent when the week has no take.
- **Only sign of life.** When a line has a take this week and no completion that would make it "active" (it would otherwise read `quiet for N days`), the cell reads `my take:` + the chip instead of the moon and the quiet text.
- Legend row gains `✦ ▶ ● ◀ My take — set by you` and `▷ dashed = draft`.

### Data

Takes and draft notes per line for the visible weeks (`week.md` § My take · Data). A week with drafts shows a draft mark with the latest direction given; a draft with a note and no direction shows the note-only mark (`⋯`).

### Behaviour

Hovering a mark shows a tooltip `W36 · Leap — Vibrato finally works`. Clicking the chip opens the `TakeControl` popover for this week. Nothing is sorted or filtered by take.

### SwiftUI

The sparkline cell becomes `VStack(spacing: 2) { Chart; HStack { ForEach(weeks) { TakeMarkView } } }` with the same x positions as the chart's week bands (shared `GeometryReader` or fixed slot width).

### Acceptance

- [ ] Marks line up with their weeks; the track never changes the bar scale.
- [ ] Demo: 🎻 `▶ ✦ · ▶ ● ▷` in W35–W40, 📐 a dashed spark in W38, 🇮🇹 no marks and `quiet for 29 days` unchanged.
- [ ] A Leap can be found in a row without colour (shape and size).
- [ ] Checked in Russian (`Подъём · черновик`).

## Draft-5 — S4-2 columns, a floor next to a budget, practice lines, quotas

Artboards: `Lines-Periods`, `Lines-Periods-RU` (+ `-Dark`). It also restores 📐 Math to the `Science` block (`design/README.md` § Pending design rounds, Before 3b, item 1); `Lines.dc.html` itself is a generated file and stays as it is.

### What S4-2 builds

- **Tiers and order** as above. **Columns:** Line 214 · State 112 · Budget 124 · Last 8 weeks 176 · Last activity 150 · Next actions 76 · Estimated this week (the rest). The `This period` column (196) of the artboard is phase 2 and absent in S4-2; its width goes to Estimated this week.
- **Budget cell:**

  | Line has                               | Cell                                                         |
  | -------------------------------------- | ------------------------------------------------------------ |
  | `budget_h_week` only                   | `6 h / week`                                                 |
  | `floor_h_day` on a foundation line     | `floor 3 h/day`                                              |
  | both, on a line that is not foundation | `4 h / week` and under it `floor 20 min/day` (11, secondary) |
  | neither                                | `—`                                                          |

  This is the exact form the vault contract (`docs/discovery/vault-contract.md` § 1) and the phase-1 spec (S4) leave to the design round: the weekly budget stays the line's main number; the floor is a daily minimum under it. A floor under 1 h is written in minutes (`20 min/day`, from `floor_h_day: 0.33`, rounded to 5 min); from 1 h in hours with the locale's decimal (`1.5 h/day`, `1,5 ч/день`). The tier header sums floors of foundation lines only (`floor 4 h/day`).

- **Last activity:** `today` · `yesterday` · `2 days ago` · moon + `quiet for 29 days` (active lines) · `no activity yet` · `29 days ago` (maintenance, neutral) · `paused since 14 July`.
- **Next actions:** the count of available next actions (the rule of `components.md` § QuietLineCard). **Estimated this week:** `≈ 6 h 40 min est.` or `—`.
- No ▶ in S4-2: the start affordance on a Lines row (`timer-mac.md`) comes with the Timer slice.

### Practice lines (phase 2, Practice lines slice; ADR-0019)

- A nested line is a row **directly under its parent**, whatever tier the parent is in, indented with a tree tick: name 13 semibold over `within 🧘 Core practice` (11, tertiary). A line with `measure: entries` and no `within` is an ordinary top-level row with the same cells.
- **State:** its own state label. **Budget:** `by entries` (tertiary): it has no hours and no budget (ADR-0019).
- **Last 8 weeks:** entries per week, one neutral series (`chipText` at 55 %), with a dashed rule at the weekly target; the current week partial as in every sparkline. Neither rhythm nor progress colour: entries are a third thing.
- **Last activity:** `last entry today`. **Next actions:** `—`. **Estimated this week:** `—`.
- **This period:** one line per target, `diary 4 of 5 · this week`, `report 0 of 1 · October` (the kind is the owner's word from the vault, shown as written), then the streak of periods that met their target, `4 weeks in a row`, tertiary, shown from 2. The running period never counts against it (ADR-0019).
- **Read state:** partly read → `at least 4 of 5 · this week`; unavailable → the last known counts with their date, `4 of 5 · as of Tue`. Never 0 for a read that failed.
- **Subtitle:** `13 lines · 2 foundation · 7 active · 2 practice · 1 maintenance · 1 paused`. Lines with `measure: entries` count once, as practice, not again under their state.

### Quota chip (phase 2, Quotas slice; ADR-0020)

- In `This period`, for a line with quota tasks: the **most pressing** one, its title (11, tertiary) over its chip (`QuotaChip`). Order: a strong `time` state, a strong short last period, a neutral `time`, open, met. `+1` after the chip when the line has more; the tooltip lists them.
- Chips (ADR-0020 § Showing it): met `2 of 2 ✓` (chip fill, secondary) · open `0 of 1 · this week` · time `time · 1 of 4 · by Sun` (secondary; **amber** text on the amber fill when the quota is strong) · a period that ended short `last week: 1 of 2` (neutral: on the first day of the new period only; strong: amber until the period is met) · carried `2 of 2 ✓ (carried)`. Partly read: `at least 1 of 4`.
- Amber here is ADR-0020's exception to rule 8: a commitment the owner chose to make loud. No red, no "missed".

### Acceptance (draft-5)

- [ ] S4-2: 📐 Math shows `4 h / week` over `floor 20 min/day` when the demo vault gives it `floor_h_day`; a foundation line shows only its floor; no other cell changes.
- [ ] S4-2: Math is in the `Science` block; the `This period` column is absent.
- [ ] Phase 2: 📓 Reflection sits under 🧘 Core practice and 🎼 Practice journal under 🎻 Violin, with `by entries`, a dashed target rule and no hours anywhere in their rows.
- [ ] Phase 2: the 📐 Math chip `time · 1 of 4 · by Sun` is amber (strong); 💪 `2 of 2 ✓` and 👨‍👩‍👧 `0 of 1 · this week` are neutral.
- [ ] Checked in Russian (`Lines-Periods-RU`): `4 ч / нед` over `пол 20 мин/день`, `diary 4 из 5 · эта неделя`, `пора · 1 из 4 · до вс`.
