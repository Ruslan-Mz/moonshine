# S3b-2 plan — what a critic should find

> Answer key for the calibration case in [plan-critic-s3b-2-plan.md](plan-critic-s3b-2-plan.md). Never give this file to the critic.
> Sources: the architect's review of the plan (2026-10-07) and the round-1 review of PR #12.

## Must find (4)

| #   | Defect in the plan                                                                                                                                                                                                                                                                                  | Class               | Where it surfaced     |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | --------------------- |
| M1  | Open question 4 proposes to decide in S4 whether a missing or broken budget note empties the lines. That is not deferrable: "could not read the lines" and "there are no lines" must be different results by type in this slice, or S4 inherits "empty" as the default and soft-deletes every line. | failed is not empty | plan review           |
| M2  | "A required key missing or invalid: the line is skipped." A skipped item is not a deleted line, but the next import would soft-delete it. Deleting a line needs a clean read.                                                                                                                       | failed is not empty | plan review           |
| M3  | "An optional key invalid: the value is dropped and the line is kept." Nothing says the drop is reported. A budget typed with a decimal comma would vanish silently.                                                                                                                                 | silent path         | plan review           |
| M4  | The budget note is "first by path wins". If the real note is rejected, or a copy sorts first, another marked note becomes the budget note and its list counts as a clean read.                                                                                                                      | who wins            | PR #12 review, Medium |

## Should find (8)

| #   | Defect in the plan                                                                                                                                         | Class                             | Where it surfaced  |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ------------------ |
| S1  | Numbers are matched with `\d`, which in Swift matches non-ASCII digits.                                                                                    | text check against the real thing | plan review        |
| S2  | No length caps on `name`, `block`, `emoji` or the `omnifocus` lists, all untrusted text.                                                                   | untrusted input                   | plan review        |
| S3  | Nothing states or tests that the `vault` subcommand writes nothing.                                                                                        | stated or enforced                | plan review        |
| S4  | The plan's own caveat: a rejected budget note shows as "missing". The output gives no sign of it.                                                          | silent path                       | plan review        |
| S5  | The contract rule "two lines claim the same tag" is not placed: reader or importer, and which test.                                                        | scope                             | plan review        |
| S6  | The slice changes `Package.swift`; under the review skill's rule reviewers then do not run the tests, unless the PR says only a target dependency changes. | later cost                        | plan review        |
| S7  | The display order of lines after a partial read is not defined.                                                                                            | scope                             | PR #12 review, Low |
| S8  | `parent` is absent from the validation list: stored as written, or resolved?                                                                               | scope                             | plan review        |

## Not expected

These could not be known from the plan and the repository: four real notes rejected by the anchor rule; the `%TAG` memory amplification; the actual size (1.49× the estimate).

## Not findings

- The split into 2a / 2b / 2c follows the size rule.
- Issue shape (a) or (b) is a real owner question; recommending (a) is fine.

## Pass bar

At least 3 of 4 "must find", at least 4 of 8 "should find", and at most 3 reported findings without a failure scenario. Record found and missed items, noise, tokens and minutes in the method log.

## Runs

Each run: Opus, the agent text of its date, one run, graded by the author session and confirmed by the owner.

- **Run 1 (2026-10-09, first agent text): below the bar.** Must find 2 of 4 (M1, M4; M3 missed: the critic assumed a report the plan does not state). Should find 4 of 8 (S1, S2, S4, S8). 3 findings without a scenario. 158,794 tokens, 4.7 min.
- **Run 2 (2026-10-09, agent text with "Drops and skips"): passes, at the bar.** Must find 4 of 4. Should find 4 of 8 (S1, S4, S6, S8; S2 partial, graded missed: caps asked only for `emoji` and `parent`). 3 findings without a scenario. 155,801 tokens, 5.2 min. Not independent evidence: the agent text was changed after the misses of run 1. The run reported that it had no Grep or Glob tool.
