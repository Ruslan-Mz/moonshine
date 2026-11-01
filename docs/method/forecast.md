# Forecast — MoonShine itself

The owner's forecast of when each stage ends (2026-10-09). It is the first point of a drift chart for MoonShine itself: the "Actual" column is left empty and filled when each stage ends.

The durations below are forecasts at the measured pace, not timeboxes. A phase's timebox is re-baselined from this forecast when its spec is written, as phase 1's was on 2026-10-09 (owner, 2026-10-10); until then `docs/ROADMAP.md` keeps the old timebox.

## Size factor

**1.49** — the median of actual / estimated production lines over the last five merged code slices (owner, 2026-10-10; unchanged by H1b, whose 1.20 at the final head (160 / 133, the owner-applied hook patch counted; 1.14 at the first) replaced P1-S4-1b-1 with its 1.43: the last five are 1.20, 1.46, 2.48, 1.49 and 1.51, so the median is 1.49; 1.49 since H1a, whose 1.46 at the final head (1.32 at the first) replaced P1-S4-1a with its 1.91: the last five are 1.46, 2.48, 1.49, 1.51 and 1.43, so the median is 1.49; 1.51 until then, unchanged by S4-DD, whose 2.48 at the final head, the generator script counted (owner, 2026-10-29, PR #36 round 1), replaced P1-S3c with its 1.63: the last five are 2.48, 1.49, 1.51, 1.43 and 1.91, so the median is 1.51; also unchanged by S4-3a, whose 1.49 at the first head replaced P1-S3b-3c with its 1.28: the last five are 1.49, 1.51, 1.43, 1.91 and 1.63, so the median is 1.51; 1.51 since S4-1b-2, whose 1.51 at the final head (1.47 at the first, the factor of the timebox review of 2026-10-28) replaced P1-S3b-3b with its 2.17: the last five are 1.51, 1.43, 1.91, 1.63 and 1.28, so the median is 1.51; 1.63 until then, unchanged by S4-1b-1, whose 1.43 at the final head (1.17 at the first) replaced P1-S3b-3a with its 1.62: the last five are 1.43, 1.91, 1.63, 1.28 and 2.17, so the median is 1.63; 1.63 since S4-1a, whose 1.91 at the final head replaced P1-S3b-2b+2c with its 1.09: the last five are 1.91, 1.63, 1.28, 2.17 and 1.62, so the median is 1.63; S4-1a's first head was 1.18, and without the 235 script lines the owner added in round 1 its final head is 1.37; unchanged by S3c, whose 1.63 at the final heads replaced P1-S3b-guards with its 2.4: the last five are 1.63, 1.28, 2.17, 1.62 and 1.09, so the median is 1.62; 1.36 at S3c's first heads; 1.75 until S3b-3a, whose row replaced P1-S3a-1 with its 2.45; unchanged by S3b-3b, whose 2.17 replaced P1-S3b-1 with its 1.75, and by S3b-3c, whose 1.28 at the final heads replaced P1-S3b-2a with its 1.55: the last five are 1.28, 2.17, 1.62, 1.09 and 2.4, so the median is 1.62). `CLAUDE.md` rule 2, "Sizing a slice" and the `plan-critic` agent use this figure; the author updates it in each code slice's PR. Actual is the final head where the method log gives it.

**The String Catalog does not count** (owner, 2026-10-20, S4-1a): `Localizable.xcstrings` is left out of the estimate and the actual, like tests, fixtures and generated files; its line count is stated separately in the PR and the method-log row.

**A move counts net** (owner, 2026-10-13, PR #19 round 1): code moved with no behaviour change counts as added lines minus the lines it removed, in the actual as in the estimate. The actual is the final head (owner, 2026-10-14). The moved lines are still stated in the PR and in the method-log row.

| Slice (method log) | Estimate | Actual                                                                                                                                                                                                                                                                                | Factor |
| ------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| P1-H1b             | ~133     | 160 net (final head: guard scripts +187 −80, the allowlist included, installer +74 −29, template +17 −13, CI and `.gitignore` +3 −2, the owner-applied hook +5 −2; first head 152: guard scripts +172 −78, installer +72 −28, template +17 −7, CI and `.gitignore` +3 −2, hook +5 −2) | 1.20   |
| P1-H1a             | ~185     | 270 net (final head: project check +239 −26, CI +19 −10, template +51 −1, settings +1 −4, store +4 −3; 245 at the first head)                                                                                                                                                         | 1.46   |
| P1-S4-DD           | ~190     | 472 net (final head: Swift +148 −45 (Core +28 −1, `DemoVault` and `DemoDay` +58 −40, app +62 −4), CI +3, the generator `scripts/demo-snapshot.mjs` +366; 470 at the first head; String Catalog +32, not counted)                                                                      | 2.48   |
| P1-S4-3a           | ~70      | 104 net (first head: Core +55 −10, adapters +62 −3, app comments +2 −2)                                                                                                                                                                                                               | 1.49   |
| P1-S4-1b-2         | ~240     | 363 net (final head: 353 at the first head, Core +72 −18 and app +299, + 10 net in round 1; String Catalog +344, not counted)                                                                                                                                                         | 1.51   |

## Basis

The owner's figures, read from the method log:

- **Pace:** 2026-10-05 to 2026-10-08, about 250 production lines and one merged PR a day (`docs/method/log.md`).
- **Factor:** 1.55, actual production lines against the plan's estimate (the figure of 2026-10-09; the size factor above replaces it for sizing).
- **Size by risk:** risky slices up to about 400 production lines after the factor, plain slices up to about 800 (`CLAUDE.md` rule 2).
- **Slow scenario:** 0.6 of the pace from January (less owner time).
- **Memos and practice lines (2026-10-19, ADR-0018, ADR-0019):** P1 ~400 and Practice lines ~350 production lines estimated, ~750 × 1.62 ≈ 1,215, at about 250 a day ≈ 5 days; phase 2 and every stage after it move 5 days later. The slow column keeps its months: 5 days do not change them.
- **Timebox review after S4-1b (owner, 2026-10-28):** factor 1.47; phase 1 ends ~2026-11-20 (was 2026-11-03, 10-30 to 11-12), with live data first and the Month view and the README moved to the usage period after it (`docs/specs/phase-1-see.md`); the stages after phase 1 are not re-forecast here.
- **Quotas and the Library module (2026-10-26, ADR-0020, ADR-0021):** production lines estimated × 1.63: Quotas ~300 ≈ 489, Library L1 ~350 ≈ 571, Library L2 ~250 ≈ 408, ≈ 1,467 in all, at about 250 a day ≈ 6 days (Quotas ≈ 2 in phase 2, Library ≈ 4 after Hub; the two risky slices are above about 400, so their plans split them); phase 2 ends 2 days later, Hub moves 2 days, every stage after Library 6 days. The slow column keeps its months.

## Stages

| Stage                                  | Base                        | Slow (0.6× from January) | Actual |
| -------------------------------------- | --------------------------- | ------------------------ | ------ |
| Phase 1 See                            | ~2026-11-20; was 2026-11-03 | same                     |        |
| Usage period: R1, README, design, spec | 11-03 to 11-17              | same                     |        |
| Phase 2 Plan, Timer (Mac) last         | 11-17 to 12-22              | same                     |        |
| Hub (in phase 2's usage period)        | 12-22 to 12-29              | same                     |        |
| Library L1 and L2 (after Hub)          | 12-29 to 2027-01-02         | same                     |        |
| Phase 3 Board                          | 2027-01-16 to 01-29         | January to February      |        |
| Write                                  | 02-12 to 03-04              | March                    |        |
| 3b iPad and iPhone                     | 03-18 to early May          | April to June            |        |
| Phase 4 Ask                            | about 05-26 to 06-16        | July                     |        |
| Phase 5 Act                            | about 06-26 to 07-16        | August to September      |        |
| Phase 6 Zoom out                       | August to early September   | autumn 2027              |        |
