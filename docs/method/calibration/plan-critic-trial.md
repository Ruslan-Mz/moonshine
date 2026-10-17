# Shadow trial of `plan-critic`

> Owner, 2026-10-10. Pre-registered before any S3b-3 run, so the bar is not moved after seeing results.

The S3b-2 calibration did not pass ([plan-critic-s3b-2-key.md](plan-critic-s3b-2-key.md), runs 4–6). The critic therefore runs on real plans as a trial: its report is printed next to the plan, and nothing depends on it until the trial is scored. The procedure for the author is in `CLAUDE.md` → "Plans".

## Procedure

- The author prints the plan and then the critic's report in chat. The owner sends the architect the plan first, and the report only after the architect's review.
- After round 1 of the PR review, the architect lists the confirmed Medium and High findings that were **plan-detectable**: the plan said, or left out, the thing that caused them. The architect's own plan findings are added to that set. This is the reference set. This was the rule for S3b-3; the remaining slices use the symmetric reference set below (owner, 2026-10-16).

## Scoring

- **Recall:** the share of the reference set that the critic's report found.
- **True, outside the set:** the critic's findings that are true but not in the reference set. Credited and listed.
- **Wrong:** the critic's findings that are refuted by the code or by a dated decision.
- Answers to the plan's own open questions are not counted as findings.

## Pass rule

- A slice passes if recall is at least 50 % and at most a third of the critic's findings are wrong.
- A slice counts only if its reference set has at least 3 items (owner, 2026-10-10). With fewer, recall says too little; the slice is listed in the results as not counted.
- The trial covers three slices, starting with S3b-3: the next three on which the critic runs and whose reference set reaches 3. A slice without a critic run (docs-only or exempt) uses none of them. The critic becomes a permanent step in "Plans" when two of the three pass.
- **S3b-3 counts as one trial slice** (owner, 2026-10-12): the critic ran once, on revision 1 of the S3b-3 plan, before the slice was split into S3b-3a, S3b-3b and S3b-3c. The later PRs of S3b-3 get no new critic run, whatever their class, and the slice is scored once, after round 1 of S3b-3c.
- Frozen during the trial is `.claude/agents/plan-critic.md` only; any change to it restarts the count. The lens files and the size factor may change as usual, so each results row records the commit the run was made on.
- The S3b-2 calibration case stays as a regression check only. It is no longer tuned against.

## Rule for the remaining trial slices

Owner, 2026-10-16, decided after S3b-3 and before any later slice is scored. The pre-registered reference set was asymmetric: the architect's items entered it by definition, the critic's own true findings did not.

- **Reference set:** the union of the architect's true items, the critic's true items and the plan-detectable confirmed Medium and High review items, with overlaps counted once.
- **Pass:** recall of at least 50 % on that set, and at most a third of the critic's findings wrong. The other rules above (at least 3 items, three slices, the frozen agent file) stay.
- **Status:** 2 of 2 passed (S3b-3 by owner decision, S3c by the rule). The critic becomes a permanent step in "Plans" (2 of 3 required; owner, 2026-10-17).

## Closed

Owner, 2026-10-17. The trial ended after two slices, both passed; the third slice was not needed. The chore PR `CHORE-FEWER-PROMPTS` made the critic a permanent step in `CLAUDE.md` → "Plans": the owner sees the plan and the critic's "For the owner" list, and the architect no longer reviews every plan. A risky plan waits only for the owner's decisions; a plain plan with verdict `ready` and no owner question starts at once. `.claude/agents/plan-critic.md` is no longer frozen; a change to it is reviewed like any other.

## Results

| Slice | Run on commit                                                                    | Reference set                                                                                                                              | Found (recall)                                             | True, outside the set                            | Wrong (of all findings) | Result                                                                                                                                                                                                                                                                                         |
| ----- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- | ------------------------------------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S3b-3 | `9dfdd3b` (`main` when S3b-3a began; revision 1 of the plan)                     | Pre-registered: 12 (architect 7, plan-detectable review items 5). Symmetric: 17 (architect 7, critic's own 9, review 5, less 4 overlaps)   | Pre-registered: 5 of 12 = 42 %. Symmetric: 14 of 17 = 82 % | Pre-registered: 9. Symmetric: 0 (all in the set) | 0                       | **PASS** by owner decision (2026-10-16): the pre-registered rule fails (42 %), the symmetric rule passes (82 %, 0 wrong); counted as a pass because the pre-registered rule was asymmetric. Source: the architect's review, `Claude outputs/s3b-3/architect-review.md` (not in the repository) |
|       |                                                                                  |                                                                                                                                            |                                                            |                                                  |                         |                                                                                                                                                                                                                                                                                                |
|       |                                                                                  |                                                                                                                                            |                                                            |                                                  |                         |                                                                                                                                                                                                                                                                                                |
| S3c   | `87a8fb9` (`main` when S3c began; revision 0 of the plan, the critic's only run) | Symmetric: 25 (architect 10, critic's own true items, plan-detectable confirmed Medium review items of #25 and #26; overlaps counted once) | 19 of 25 = 76 % (the architect: 10 of 25 = 40 %)           | 0 (all in the set)                               | 0                       | **PASS** by the symmetric rule. Source: the architect's review, `Claude outputs/s3c/architect-review.md` (not in the repository)                                                                                                                                                               |
