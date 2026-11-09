# Phase 0 — data report

Date: 2026-09-30 · Aggregates only: no task, project or note titles, no values from notes.

**Coverage: both halves done.** OmniFocus was read only through the MCP server's read-only tool (`omnifocus_read`; the `analyze`, `write` and `system` tools were never loaded). The first session had no MCP connection; the OmniFocus half ran in a second session the same evening. Counts come from `countOnly` queries (exact); field shares come from a sample of rows fetched without names (stated per number).

## Obsidian (`~/ObsidianV`, read-only)

### Size and frontmatter coverage

| Folder          | Notes | With frontmatter | Max folder depth |
| --------------- | ----: | ---------------: | ---------------: |
| `00_Стратегия/` |    34 |        31 (91 %) |                3 |
| `journal/`      |    31 |          2 (6 %) |                2 |
| `projects/`     |   274 |       188 (69 %) |                6 |

Vault total: 1 345 markdown files. YAML parse errors: 0.

### Keys in use (counts = notes carrying the key)

| Key                                                   | `00_Стратегия` | `journal` |          `projects` | Value type                               |
| ----------------------------------------------------- | -------------: | --------: | ------------------: | ---------------------------------------- |
| `type`                                                |             31 |         2 |                 164 | string (2 notes use a comma list)        |
| `title`                                               |             31 |         1 |                 177 | string                                   |
| `created`                                             |             31 |         2 |                 171 | date                                     |
| `updated`                                             |             27 |         — |                 148 | date                                     |
| `status`                                              |             28 |         — |                 168 | string                                   |
| `tags`                                                |             30 |         — |                 177 | list of strings                          |
| `related`                                             |             26 |         — |                 173 | list of wikilinks                        |
| `version`                                             |             25 |         1 |                 160 | string (6 notes: number)                 |
| `parent`                                              |             18 |         1 |                  35 | wikilink                                 |
| `next_review`                                         |             21 |         — |                 126 | date                                     |
| `review_cadence` / `review-cadence`                   |         16 / 6 |         — |               3 / 2 | string — **two spellings**               |
| `horizon`                                             |             13 |         — |                   5 | free-text string (not an enum)           |
| `period_start` / `period_end`                         |              7 |         — |                   9 | date (1 note `YYYY-MM`, 1 note int year) |
| `month`                                               |              3 |         — |                   — | `YYYY-MM`                                |
| `year`                                                |              1 |         1 |                   3 | int                                      |
| `quarter`                                             |              1 |         — |                   — | string                                   |
| `horizons`                                            |              1 |         — |                   — | list of int years                        |
| `sharing`, `last_actuality_check`, `scope`, `purpose` |              — |         — | 126 / 118 / 63 / 44 | project-doc metadata                     |

`projects/` has **~200 distinct keys**, most of them one-off `changelog_vN` keys on research documents. Consequence: the reader must ignore unknown keys (vault-contract §3).

Value vocabularies (counts):

- `type`: 40 distinct values; the top three (appendix, verification report, strategic) cover 55 %. Horizon types: `month_plan` 3, `quarter_focus` 2, `year_artifacts` 1, `horizon_corridor` 2, plus legacy `yearly-goals` 1 and `focus` 1 in `journal/`.
- `status`: 13 distinct values, incl. one Cyrillic value and both `proposed`/`proposal`.
- `review_cadence`: daily 1, weekly 9, monthly 3, quarterly 3, yearly 1, multiyear 1, once 1.

### Horizon and artifact notes — how they are identified

| Level      | `type`                | Count | Filename pattern                                       | Period keys                                                     | Parent chain                     |
| ---------- | --------------------- | ----: | ------------------------------------------------------ | --------------------------------------------------------------- | -------------------------------- |
| Month      | `month_plan`          |     3 | `Месяц_YYYY-MM`                                        | `month`, `period_start/end`                                     | → quarter note (3/3)             |
| Quarter    | `quarter_focus`       |     2 | `Qn_YYYY_focus` (past quarters in a `Done/` subfolder) | `period_start/end` (1 of 2 also `quarter`)                      | → year note (1/2), other → index |
| Year       | `year_artifacts`      |     1 | `Артефакты_YYYY`                                       | `year`                                                          | → index                          |
| Multi-year | `horizon_corridor`    |     2 | descriptive                                            | one `period_start..end` as int years; one `horizons: [3 years]` | → context note                   |
| Lifetime   | —                     |     0 | —                                                      | —                                                               | —                                |
| Week       | none (no frontmatter) |     4 | `YYYY-Www` in `journal/2. weekly/`                     | —                                                               | —                                |

Findings that shaped the contract:

1. **Artifacts are not notes.** The year note holds artifacts as numbered rows of one markdown table; quarter focuses are H3 headings in the quarter note; month notes point up with heading-anchor wikilinks and `#N` artifact numbers in headings. → contract adds an `artifacts:` frontmatter list instead of one note per artifact.
2. **`horizon` is already taken as prose** in 18 notes (strategic plans). → contract accepts only enum values (open question Q1: rename to `scale`).
3. **Parent chain exists but is incomplete** (month → quarter → year mostly present; year → corridor absent).
4. The **budget note** has no `lines:` block yet; its data is two markdown tables: **24 lines** (17 core + 7 additional) in **5 blocks**; 2 lines marked paused on purpose, 1 line with no weekly budget. Columns: `#`, line (emoji + name), block, plan h/week, last month actual, delta, status (emoji + text). → draft `lines:` block written to `data/mapping.local.yaml` (git-ignored).

### Hours tracker (Excel)

Not in the vault (0 `.xlsx/.xls/.csv/.numbers` files). Strategy notes refer to an xlsx tracker started in May 2026. **Owner: point to the file** for the sheet/column survey (structure only, no values).

## OmniFocus (read-only via MCP)

### Size and structure

|                               |                                Count | Notes                                                                                                                                                    |
| ----------------------------- | -----------------------------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Folders                       |                                   23 | 16 top-level (1 dropped archive folder with 6 subfolders); max depth 3                                                                                   |
| Projects                      |                                  149 | active 131 · done 14 · dropped 4 · on hold 0; 6 without a folder; ~60 "active" projects sit inside the dropped archive folder and hold 0 remaining tasks |
| Tags                          |                                  172 | depth ≤ 2; 6 meta groups (names in `mapping.yaml` in the data folder, not here) with 22 children; the other ~144 are flat                                |
| Remaining tasks               |                                1 079 | not completed, not dropped, project roots excluded; ~13 % of them live inside done/dropped projects (sample)                                             |
| Completed, 12 weeks (W28–W40) |                                1 010 | since 2026-07-06                                                                                                                                         |
| Inbox                         | 5 remaining · 24 completed in window |                                                                                                                                                          |

### Line tags vs meta tags

- Meta tags are **top-level groups with English leaf children** (time boxes, work type, context, energy, cycle, location) — not `Group : Value` strings.
- **Line tags are sparse.** Only a few lines have a dedicated tag with real use (12-week completions: one instrument 53, a second instrument 7, the AI/ML tag group 25, English 5, research 3; the doctoral-reading, sci-social and math tags: 0).
- **Lines follow folders and projects.** 15 used top-level folders; 6 of them hold several lines each (music, science/study, work, health, creative, languages), so the mapping must work at project level for those.
- Topic tags outnumber both: ~130 flat tags are one-project vocabularies (site migration, design, finance…).

### Completions per ISO week (all tasks)

| W28 | W29 | W30 | W31 | W32 | W33 | W34 | W35 | W36 | W37 | W38 | W39 | W40* |
| --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | ---: |
|  94 | 132 |  70 |  85 |  93 | 106 |  58 |  60 |  63 |  84 |  76 |  89 |    0 |

\*W40 = Mon–Wed at query time. Sum = 1 010 (checks against the window total).

### Completions per top-level folder, 12 weeks (generic labels)

| Folder (role)                    |                                                              Completed | Remaining |
| -------------------------------- | ---------------------------------------------------------------------: | --------: |
| System: anchors, reviews, habits |                                                                    362 |       134 |
| Professional practice (sessions) |                                                                    238 |        30 |
| Music (several instrument lines) |                                                                    111 |       174 |
| Home & errands                   |                                                                     53 |        33 |
| Kids' music school               |                                                                     50 |        59 |
| Work (several lines)             |                                                                     49 |       182 |
| Health (several lines)           |                                                                     48 |        21 |
| Languages (several lines)        |                                                                     31 |        29 |
| Science & study (several lines)  |                                                                     26 |       299 |
| Inbox                            |                                                                     24 |         5 |
| Second employer                  |                                                                     12 |         8 |
| Family                           |                                                                      7 |         5 |
| Research institute               |                                                                      6 |        22 |
| Creative (several lines)         |                                                                      2 |        82 |
| School (kids)                    |                                                                      1 |         0 |
| Archive (dropped)                |                                                                      0 |         0 |
| Someday/Maybe                    | not countable (`/` in the folder name breaks the server's path filter) |       ≈ 5 |

Per-folder counts sum to 1 020 / 1 083, a 1 % overlap with the totals (inbox vs. folder filters in the server); per-folder × per-week counts were not pulled (≈ 200 queries); the phase-1 bridge computes them locally.

**Main finding: 49 % of completions (494) carry the `anchor`/`routine` tags, and 86 % of completed tasks are repeat occurrences (sample of 625).** Raw "completions per line" is therefore mostly a habit counter; one-off completions are ~140 in 12 weeks. → decision O1: two separate per-line metrics, _rhythm_ (repeat occurrences = sessions) and _progress_ (one-off tasks); no weighting.

### Field availability (remaining tasks)

| Field                         |                    Share | Basis                                                 |
| ----------------------------- | -----------------------: | ----------------------------------------------------- |
| `estimatedMinutes`            | 23 % (10 % on completed) | sample 500 / 625                                      |
| `plannedDate`                 |               12 % (128) | count                                                 |
| `dueDate`                     |                 8 % (83) | count — the only urgent-colour candidates             |
| `deferDate`                   |                 4 % (44) | count                                                 |
| repetition rule               |                     14 % | sample 500                                            |
| note present                  |                      7 % | sample 500                                            |
| flagged                       |                      2 % | sample 500                                            |
| available / blocked / neither |       45 % / 42 % / 13 % | sample 500 ("neither" = inside done/dropped projects) |

### Active tasks mapping to no line (→ "Life ops")

With a folder/project mapping built from the budget lines, the folders that map to **no line** are system (134), home (33), inbox (5) and someday (≈ 5): **≈ 177 of 1 079 (16 %)**. Examples (rewritten generically): a monthly bill reminder, a weekly grocery run, an unfiled idea in the inbox. Tasks with no tags at all: 31 % (sample) — tags alone would leave far more unmapped than folders do.

### Repeating tasks

Completing a repeating task keeps the live task and creates a completed copy with id `<liveId>.<n>`, same rule, `added` ≈ completion time (85 % within 5 s). Repeating action groups clone their children the same way. Details and contract consequences: `snapshot-contract.md` §Findings V1.

### Latency

Through the MCP server (serial queue): counts over all tasks ~8 s each (date-range counts ~2 s); a page of rows ~8–9 s, capped by the server at 125 rows after halving; a full active + 12-week read would need ≥ 17 pages ≈ 2.5 min. Not representative of the phase-1 bridge (one Omni Automation call), but a full scan costing ~8 s puts the < 5 s target at risk (contract V2).

## What was produced

- `docs/discovery/vault-contract.md`, `docs/discovery/snapshot-contract.md` (v0.1; snapshot contract updated with live findings V1, V3, V4).
- `fixtures/omnifocus.snapshot.json`: synthetic, the dataset of `design/demo-data.md`, written by `scripts/demo-snapshot.mjs` since S4-DD (2026-10-29), which lists the contract cases it keeps; `SnapshotTests` and `DemoDataGoldenTests` pin its counts and numbers. Until S4-DD it was a hand-made set of 169 tasks for 8 lines.
- `fixtures/vault/`: budget note with `lines:`, 2026 artifacts, Q4 focus, October month plan, corridor, long horizons (all synthetic).
- `data/mapping.local.yaml` (git-ignored): draft `lines:` with 24 lines; 22 have OmniFocus tags/folders/projects drafted from live data, 2 have no OmniFocus home.
