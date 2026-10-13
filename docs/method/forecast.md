# Forecast — MoonShine itself

The owner's forecast of when each stage ends (2026-10-09). It is the first point of a drift chart for MoonShine itself: the "Actual" column is left empty and filled when each stage ends.

The durations below are forecasts at the measured pace, not timeboxes. A phase's timebox is re-baselined from this forecast when its spec is written, as phase 1's was on 2026-10-09 (owner, 2026-10-10); until then `docs/ROADMAP.md` keeps the old timebox.

## Size factor

**1.62** — the median of actual / estimated production lines over the last five merged code slices (owner, 2026-10-10; 1.75 until S3b-3a, whose row replaced P1-S3a-1 with its 2.45; unchanged by S3b-3b, whose 1.98 replaced P1-S3b-1 with its 1.75). `CLAUDE.md` rule 2, "Sizing a slice" and the `plan-critic` agent use this figure; the author updates it in each code slice's PR. Actual is the final head where the method log gives it.

**A move counts net** (owner, 2026-10-13, PR #19 round 1): code moved with no behaviour change counts as added lines minus the lines it removed, in the actual as in the estimate. The moved lines are still stated in the PR and in the method-log row.

| Slice (method log)  | Estimate                     | Actual                                                                                                                   | Factor |
| ------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------ |
| P1-S3b-3b (two PRs) | ~215                         | 426 (first head: 403 in the notes PR and 23 net in the helper PR, a move of 114 added and 91 removed; 467 after round 1) | 1.98   |
| P1-S3b-3a           | ~212                         | 343 (after round 1; 298 at the first head)                                                                               | 1.62   |
| P1-S3b-2b+2c        | ~225                         | 246 (final head)                                                                                                         | 1.09   |
| P1-S3b-guards       | ~55 (parts with an estimate) | 131 (first head; the guards part had no estimate)                                                                        | 2.4    |
| P1-S3b-2a           | ~140                         | 217 (final head)                                                                                                         | 1.55   |

## Basis

The owner's figures, read from the method log:

- **Pace:** 2026-10-05 to 2026-10-08, about 250 production lines and one merged PR a day (`docs/method/log.md`).
- **Factor:** 1.55, actual production lines against the plan's estimate (the figure of 2026-10-09; the size factor above replaces it for sizing).
- **Size by risk:** risky slices up to about 400 production lines after the factor, plain slices up to about 800 (`CLAUDE.md` rule 2).
- **Slow scenario:** 0.6 of the pace from January (less owner time).

## Stages

| Stage                                  | Base                        | Slow (0.6× from January) | Actual |
| -------------------------------------- | --------------------------- | ------------------------ | ------ |
| Phase 1 See                            | 2026-11-03 (10-30 to 11-12) | same                     |        |
| Usage period: R1, README, design, spec | 11-03 to 11-17              | same                     |        |
| Phase 2 Plan, Timer (Mac) last         | 11-17 to 12-15              | same                     |        |
| Hub (in phase 2's usage period)        | 12-15 to 12-22              | same                     |        |
| Phase 3 Board                          | 2027-01-05 to 01-18         | January to February      |        |
| Write                                  | 02-01 to 02-21              | March                    |        |
| 3b iPad and iPhone                     | 03-07 to end of April       | April to June            |        |
| Phase 4 Ask                            | mid-May to early June       | July                     |        |
| Phase 5 Act                            | mid-June to early July      | August to September      |        |
| Phase 6 Zoom out                       | August                      | autumn 2027              |        |
