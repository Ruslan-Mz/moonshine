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
- The trial covers three slices, starting with S3b-3. The critic becomes a permanent step in "Plans" when two of the three pass.
- The critic's text is frozen during the trial. Any change restarts the count.
- The S3b-2 calibration case stays as a regression check only. It is no longer tuned against.

## Results

| Slice | Reference set | Found (recall) | True, outside the set | Wrong (of all findings) | Result |
| ----- | ------------- | -------------- | --------------------- | ----------------------- | ------ |
| S3b-3 |               |                |                       |                         |        |
|       |               |                |                       |                         |        |
|       |               |                |                       |                         |        |
