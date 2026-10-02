# Excel hours tracker — import contract (draft)

> Structure only, generalised from a structure analysis: no labels, values, names, sheet dates or exact counts from the real workbook. The workbook lives in `data/` (git-ignored); fixtures are invented. Phase 2 builds the import.

## Workbook shape

- One sheet per month, named `YYYY-MM`. Summary sheets are formulas only — ignore them.
- **Wide grid:** rows = activities, columns = days, values = **minutes** (int).
- Row 1 = day-of-month number (int, or a formula with a cached int — read cached values). Row 2 = weekday abbreviation, or a total marker for a weekly-total column.
- Column A = label, column B = monthly sum (formula). Skip all formula cells and total columns.
- **Two layouts, detected by structure** (never by sheet name or date):
  - **Layout A:** one column per calendar day, no weekly totals.
  - **Layout B:** a Monday-first grid of whole weeks with a total column after each week; cells outside the month have an empty day number → skip them.

## Row kinds (detect by label, not by position — positions shift between sheets)

| Kind               | How to detect (example markers)                                     | Import as                                                                                         |
| ------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Totals             | label starts with a totals marker (e.g. `ИТОГО`)                    | skip                                                                                              |
| Context            | label starts with a context marker (e.g. `📝`)                      | **calendar context**: free text per day (place / trip / note) → capacity exceptions (ADR-0006)    |
| Section            | non-indented, all caps after an emoji, no values (layout B sheets)  | hierarchy level 1                                                                                 |
| Group              | non-indented label with an emoji                                    | hierarchy level 2                                                                                 |
| Item               | label indented with spaces                                          | **TimeEntry**(date, minutes, itemLabel, groupLabel, sectionLabel)                                 |
| Indicators         | known labels at the bottom (e.g. wake time, bedtime, steps, travel) | **Measurement**: times as `time`; counts as int, normalised when a sheet stores them in thousands |
| Derived indicators | formula rows (daily sums, "unknown = 24 h − logged")                | skip                                                                                              |

The markers above are examples. The importer reads markers, weekday abbreviations and indicator labels from the mapping file, never from code. Text cells inside the minute grid (e.g. `-`) are "no data", not zero.

## Taxonomy drift (the main difficulty)

- Item labels change between sheets: renames, new and disappearing items, regrouping into sections.
- Therefore **mapping item label → MoonShine line is data, not code.** A mapping table (`data/excel-mapping.local.yaml`, git-ignored) holds the markers and the label mappings, versioned by the first sheet each applies to; unmapped labels are reported, never guessed silently.
- The assistant (phase 4) can propose mappings for new labels; until then the importer lists unmapped labels for manual mapping.

## Volume and quality

- Orders of magnitude: ~100 item rows and a few hundred non-empty minute cells per sheet, thousands of time entries in total. Trivial for the store.
- Coverage is high: most days of a month are logged.
- An activity may be logged both as minutes (item) and as times (indicators) → minutes feed the budget, times feed rhythm.

## Import semantics

- Idempotent by (sheet, row label, date): re-importing a sheet replaces that sheet's entries for that source.
- The workbook stays the source of truth for hours until MoonShine has its own quick log; the import is one-way.
- Context rows feed `Capacity` exceptions; indicator rows feed `Measurement`.
