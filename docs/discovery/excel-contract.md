# Excel hours tracker — import contract (draft, from structure analysis)

> Structure only. No real row labels, values or names belong in the repo. The real workbook lives in `data/` (git-ignored); fixtures are synthetic.

## Workbook shape

- One sheet per month, named `YYYY-MM` (5 so far: 2026-05 … 2026-09). Summary sheets (`Сводка …`) are formulas only — ignore.
- **Wide grid:** rows = activities, columns = days, values = **minutes** (int).
- Row 1 = day-of-month number (int, or a formula with a cached int — read cached values). Row 2 = weekday abbreviation (`Пн`…`Вс`) or `T` for a weekly-total column.
- **Layout changed over time:**
  - 2026-05: one column per calendar day (31), no weekly totals.
  - From 2026-06: 6-week Monday-first grid (42 day columns) with a `T` total column after each week; cells outside the month have an empty day number → skip them.
- Column A = label, column B = monthly sum (formula). Skip all formula cells and `T` columns.

## Row kinds (detect by label, not by position — positions shift every month)

| Kind                   | How to detect                                                        | Import as                                                                                                                               |
| ---------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Totals                 | label starts with `ИТОГО`                                            | skip                                                                                                                                    |
| Context                | label starts with `📝`                                               | **calendar context**: free text per day (place / trip / note) → capacity exceptions (ADR-0006)                                          |
| Section (from 2026-07) | non-indented, ALL-CAPS after emoji, no values                        | hierarchy level 1                                                                                                                       |
| Group                  | non-indented label with emoji                                        | hierarchy level 2                                                                                                                       |
| Item                   | label indented with spaces                                           | **TimeEntry**(date, minutes, itemLabel, groupLabel, sectionLabel)                                                                       |
| Indicators             | known labels at the bottom (wake time, bedtime, steps, travel hours) | **Measurement**: wake/bed = `time` values; steps = int, but later months store **thousands as float** (6.5) → normalise; travel = hours |
| Derived indicators     | formula rows (daily sums, "unknown = 24h − logged")                  | skip                                                                                                                                    |

Text cells inside the minute grid (e.g. `-`) are "no data", not zero.

## Taxonomy drift (the main difficulty)

- ~90–100 item rows per month; vs. May, later months have **~45 new and ~35 disappeared item labels** (renames, regrouping into sections in July).
- Therefore: **mapping item label → MoonShine line is data, not code.** Keep a mapping table (`data/excel-mapping.local.yaml`, git-ignored), versioned by first month it applies to; unmapped labels are reported, never guessed silently.
- The assistant (phase 4) can propose mappings for new labels; until then the importer lists unmapped labels for manual mapping.

## Volume and quality

- ~150 logged days, ~700–900 non-empty minute cells per month → ~4k time entries for 5 months. Trivial for the store.
- Coverage is high (27–31 logged days per month).
- Sleep is logged both as minutes (item) and as wake/bed times (indicators) → use minutes for budget, times for rhythm.

## Import semantics

- Idempotent by (sheet, row label, date): re-importing a month replaces that month's entries for that source.
- Source of truth for hours stays the workbook until MoonShine has its own quick log; import is one-way.
- Context rows feed `Capacity` exceptions; indicator rows feed `Measurement`.
