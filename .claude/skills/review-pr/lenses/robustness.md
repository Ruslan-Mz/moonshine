# Lens: robustness — processes, concurrency, time, failure paths

Look for what happens when something is slow, absent, concurrent, cancelled or wrong.

## Questions

1. **Child processes**: is the timeout hard (terminate, bounded grace, then kill)? Can a full pipe deadlock (waiting for exit before reading output)? What if the executable is missing, the other app is not running, or permission is denied?
2. **Concurrency**: any read → compute → write sequence that crosses an `await` or two calls? Actor re-entrancy. Two triggers at once (timer and ⌘R). Is the work single-flight, and are requests during a run coalesced into exactly one follow-up?
3. **Transactions**: is each import one atomic write? Can a reader see a half-merged state? Is a stale write rejected (versioned commit)?
4. **Swallowed errors**: `try?`, empty `catch`, ignored results. Which failure becomes silence, and what wrong state follows?
5. **Files**: "does not exist" versus other errors; leftovers from a previous run; atomic writes; paths with spaces.
6. **Time**: time zones, daylight saving, ISO weeks versus calendar quarters, start and end of day, date-only versus date-time, "now" captured once or many times.
7. **Boundaries of a period**: inclusive or exclusive ends; items before the period; items exactly on the boundary.
8. **Cost**: work repeated per item that could be done once; anything proportional to the whole database on a hot path; memory proportional to input.
9. **Cancellation and shutdown**: a task cancelled mid-import; the app quitting; what state is left.
10. **Retention**: can an import delete or hide something it must keep (completed tasks, soft-deleted items that return)?

## Seen in this repository

- Identity-map read → workspace build → commit was not atomic; overlapping imports created duplicates and wrong soft-deletes. Fixed with a single-flight actor and a versioned commit.
- The timeout sent only SIGTERM and then waited without bound.
- `try? removeItem` ignored every error, so a measurement could start from a stale store.
- The date regex was rebuilt for each of about 10,000 dates: decode went from 0.04 s to 0.71 s.
- A due badge used "≤ end of the shown period" and also matched dates before the period.
- Q3 2026 covers 14 ISO weeks, not 13.
- A test for an append-only table passed against a stub because the table did not exist.
