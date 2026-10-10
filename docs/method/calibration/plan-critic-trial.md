# Shadow trial of `plan-critic`

> Owner, 2026-10-10. Pre-registered before any S3b-3 run, so the bar is not moved after seeing results.

The S3b-2 calibration did not pass ([plan-critic-s3b-2-key.md](plan-critic-s3b-2-key.md), runs 4–6). The critic therefore runs on real plans as a trial: its report is printed next to the plan, and nothing depends on it until the trial is scored. The procedure for the author is in `CLAUDE.md` → "Plans".

## Procedure

- The author prints the plan and then the critic's report in chat. The owner sends the architect the plan first, and the report only after the architect's review.
- After round 1 of the PR review, the architect lists the confirmed Medium and High findings that were **plan-detectable**: the plan said, or left out, the thing that caused them. The architect's own plan findings are added to that set. This is the reference set.

## Scoring

- **Recall:** the share of the reference set that the critic's report found.
- **True, outside the set:** the critic's findings that are true but not in the reference set. Credited and listed.
- **Wrong:** the critic's findings that are refuted by the code or by a dated decision.
- Answers to the plan's own open questions are not counted as findings.

## Pass rule

- A slice passes if recall is at least 50 % and at most a third of the critic's findings are wrong.
- A slice counts only if its reference set has at least 3 items (owner, 2026-10-10). With fewer, recall says too little; the slice is listed in the results as not counted.
- The trial covers three slices, starting with S3b-3: the next three on which the critic runs and whose reference set reaches 3. A slice without a critic run (docs-only or exempt) uses none of them. The critic becomes a permanent step in "Plans" when two of the three pass.
- Frozen during the trial is `.claude/agents/plan-critic.md` only; any change to it restarts the count. The lens files and the size factor may change as usual, so each results row records the commit the run was made on.
- The S3b-2 calibration case stays as a regression check only. It is no longer tuned against.

## Results

| Slice | Run on commit | Reference set | Found (recall) | True, outside the set | Wrong (of all findings) | Result |
| ----- | ------------- | ------------- | -------------- | --------------------- | ----------------------- | ------ |
| S3b-3 |               |               |                |                       |                         |        |
|       |               |               |                |                       |                         |        |
|       |               |               |                |                       |                         |        |
