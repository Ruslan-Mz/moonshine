---
title: "0023 — Routine template: blocks in a vault note now, a native entity later; adherence and progression by rules"
status: proposed
date: 2026-11-01
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[0019-practice-lines-nested-lines-measured-by-entries]]"
  - "[[0022-proactive-day-checkpoints]]"
  - "[[0024-evidence-base]]"
---

# 0023 — Routine template: blocks in a vault note now, a native entity later; adherence and progression by rules

## Context and Problem Statement

The owner keeps a weekly routine: a template (эталон) of time blocks. It says when he wakes, when he practises, which hours are kept for deep work and when he goes to bed. Today nothing tells him whether he follows it. The template lives apart from what actually happens, so the two drift into two realities: a schedule nobody checks, and a day nobody compares with it.

He also wants to move towards a template he cannot keep yet, step by step: for example waking at 6:30, then 6:15, 6:00 and 5:45 over several weeks. He wants to be told, by rules, when a step is held well enough to take the next one, or when to step back.

MoonShine will have the facts in phase 2:

- timer intervals and dictated entries with clock times (ADR-0016; Log by text);
- the workbook's minutes per day, which have no clock times;
- sleep and workouts from the Health bridge.

The sources `dictation` and `health`, and wake and bed as day boundaries, are ADR-0016 amendments that land with the phase-2 spec's PR, together with this ADR.

**How is the template written down, how is each block compared with the facts, how does the template change over time, and how does it feed the plan without becoming a second reality?**

## Decision Drivers

- **One reality.** The template shapes the plan; the facts correct the template. Neither silently overrides the other.
- **Facts, not grades** (CLAUDE.md rule 8). A block is held, shifted by N minutes, shortened, or not tracked; it is never "missed", "failed", "behind" or "skipped". No red.
- **Failed is not empty.** A day without data is "no data", never "not held". A note that cannot be read keeps the last template.
- **Deterministic rules, no model,** for adherence and for the progression suggestions. The assistant explains and helps build ladders later (phase 4).
- **The owner edits where he already writes:** the vault today, a native editor later, never two sources at once.
- **Nothing from the vault is executed** (ADR-0015, ADR-0021). Metrics and rules come from a fixed catalogue in code, with parameters in the note.
- **History survives edits.** A past week is judged against the template that was in force then.

## Considered Options

1. **A vault note `moonshine: routine` now; a one-time import into a native entity later, after which the note is no longer read.**
2. **A native entity from the start**, edited in the app.
3. **The vault note for good**, with Obsidian as the only editor.
4. **Two-way sync** between the note and a native entity.
5. **The calendar as the template**: recurring events as blocks.

## Decision Outcome

**Proposed: option 1.** The owner can write his routine today without an editor, MoonShine can start comparing it with the facts in phase 2, and the switch to a native entity is one explicit step instead of a permanent sync.

**This ADR amends:**

- the vault contract (§5 reserves `routine`; §6.4 is new);
- ADR-0006 (the Board's capacity, from the template, § The template shapes the plan);
- ADR-0013 (the capacity-exception commands for "away" become native `auto` commands);
- `docs/ARCHITECTURE.md` (the `Routine`, `RoutineVersion` and capacity-exception records).

**Naming.** In the repository the slices are P2-R1 (reader), P2-R2 (adherence), P2-RV (views), P2-RC (charts) and P2-R3 (phase 4). The bare "R1" remains the Quarterly review (`docs/ROADMAP.md:11`).

### The routine note (the source until the import)

- **One note** with `moonshine: routine` at the top of its frontmatter is the routine. It is found the way the budget note is: by parsed frontmatter, and lexically in a note that was rejected (`docs/discovery/vault-contract.md` §1).
  - **A note rejected before its frontmatter could be extracted** (too large, never closed, not UTF-8) is searched in its head bytes too, so it is never silently absent.
  - **No note** means no routine, but only on a read that saw every note. If anything was left unread, the routine is unavailable, not missing.
  - **More than one marked note** is ambiguous, and none wins.
- **Only the frontmatter is read**, under the 64 KiB cap of vault contract §3. The §6 scanner's 8 KiB cap does not apply to `routine` (an exception in §6.4; spec question 25). The body is never read.
- **Times are written `HH:MM` and read from the scalar's own text.** The reader keeps scalars as raw strings, so `6:30` and `06:30` are told apart, and only the second is valid.
- **Unknown keys are problems.** A misspelt key must never fall back to a default silently.
- **Its format** is fixed in P2-R1's plan and becomes vault contract §6.4. In short:
  - `tolerances`: defaults are an anchor's start ± 15 minutes, and a duration at 80 % or more;
  - `variants`: each with an `id`, a rule `applies` (weekdays; a date range; `away`), and `blocks`;
  - blocks: each with an `id`, which is the stable key of its history (the same key in two variants must have the same kind and subject), a `kind`, a subject, and its times. The subject is a line by its key, a Life ops category, or the day boundary `wake` or `bed`;
  - `metrics`: weekly counts from a fixed catalogue, such as "days with bed by 23:00, target 5";
  - `ladders`: the progression, below.

### Block kinds

| Kind          | Means                                                                                     | Held when                                                                                            | Shifted when                                                                                 |
| ------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **anchor**    | It happens at a set time: wake 6:30, violin at 7:00 for 30 minutes, bed 23:00             | its start is within the start tolerance, and its duration (if it has one) reaches the duration share | the start is outside the tolerance; N is the signed minutes                                  |
| **flexible**  | A duration of a line somewhere inside a window: violin 45 minutes between 17:00 and 21:00 | the line's minutes inside the window reach the duration share                                        | the share is reached only with minutes outside the window; N is the distance from the window |
| **protected** | A span kept for one line: deep work 9:00–12:00                                            | the line's minutes inside the span reach the duration share of the span                              | the share is reached only with minutes outside the span                                      |

- **A line's clock minutes are claimed by one block only** (spec question 32): anchors first, then protected spans, then flexible windows. "Shifted" uses only minutes no block claimed, so one 45-minute session never serves two blocks.

### Which variant applies on a day

Exactly one variant, or none. The levels are tried in order, and the first level that matches decides:

1. **away:** a variant with `applies: away`, on a day the owner marked away. The mark is a capacity exception of kind `away`, the record ADR-0006's capacity already has for trips (spec question 26). A day marked away with no away variant is not judged.
2. **dated:** a variant whose date range contains the day (a season), and whose weekdays, if given, contain it.
3. **weekdays:** a variant whose weekdays contain the day (weekday, weekend).

- **Two variants at the deciding level** make the day ambiguous: it has no template that day, and nothing is judged (`routineVariantAmbiguous`).
- **A day that no variant covers** has no template.
- **A version with a skipped variant judges no day**, because the skipped variant's range is unknown.

### Versions

- Versions form a sequence. A new version is appended when the template's canonical hash or its partial flag differs from the latest version, or when the latest has ended. An A → B → A edit therefore appends A again.
- Versions are never deleted.
- **A day is judged against the version in force at its start.** The first version also judges the day it appeared. An edit today takes effect tomorrow, so the owner cannot re-grade a day by editing the note.
- **"First seen" is when an import sees the edit.** If the app does not run for days, the old version judges those days.
- **Failed is not empty:**
  - a routine note that is rejected, ambiguous, unextractable or unread keeps the last version in force, shown with its date;
  - a version read with skipped items is **partial**: the skipped parts are not judged, and no ladder suggests anything while the version in force is partial;
  - a template with no valid variant is not a version at all; the read is unavailable;
  - only a read that saw every note and found no routine note ends the last version, and the end takes effect at the next local day's start. History stays.

### Adherence (computed, never stored)

Each block on each day is in one of these states:

- **held**;
- **shifted** by N minutes;
- **shortened** to N of M minutes;
- **not tracked**: nothing for the block that day; the word is the tone glossary's "not tracked / не учтено", `design/tone-glossary.md:34`;
- **no data**;
- **not judged**: a paused line, an unknown line, a nested or entries line, or no template;
- **pending**: its time has not come.

How the states are decided:

- **Minutes.** A line's minutes on a day come from the class the hours ledger counts for that day. That is native or the workbook, never both added (ADR-0016 § Two sources). Running timer sessions count up to now.
- **Boundaries.** The day's wake and bed come from one rule:
  - Health first (measured), then dictation (stated), then a Sleep entry with clock times (ADR-0016 § Records);
  - a bed before 06:00 belongs to the day before;
  - the writer stores the day, and adherence reads it.
- **No data, not "not tracked"** (spec question 31). "Not tracked" needs evidence that the owner was tracking that day: an entry he recorded himself (timer, manual, dictation, a confirmed calendar entry, the workbook) whose subject is not Life ops. For anchors and protected blocks, the entry must have clock times. Health workouts and derived estimates are never evidence: a walk the watch saw on a day he tracked nothing leaves his blocks at "no data".
- **The workbook has no clock times.** On a day whose counted minutes for a line have no clock times, a flexible block is judged on minutes, with its position unknown. Anchors and protected blocks of that line have no data.
- **A paused line** (spec question 33) is not judged from today on; its past days keep their states until pause history exists.
- **A week shows:**
  - per block, the held days of the judged days;
  - per metric, the days that met it, of the days it could be judged, against its target.
  - The running week is never counted as short: as in ADR-0019, a period still running cannot be missed.

### Progression: ladders

- **What a ladder is.** It belongs to one block and one of its values: an anchor's time, a duration, or a protected span's start. It lists the **stages** from the block's own value (the first stage) to the **target** (the last), and names the **current** stage.
  - The block's effective value is the current stage, so `current` is the one place the number in force is written.
  - Every stage must satisfy the block's own rules.
- **Advance** is suggested when the current stage was held at or above a share in each of the last N complete ISO weeks. Each of those weeks must have at least four judged days of the variants the ladder covers, all under the current stage.
- **Step back** is suggested when the current stage was held below another share in each of the last M such weeks.
- **Anything else suggests nothing, and says why:** too few judged days, a week under another stage, or a partial version in force today.
- **Suggestions only.** While the note is the source, the owner moves `current` in the note. After the import, a `confirm` command does it, with undo. Either way the suggestion is a fact with a next step: `wake 6:15 held 6 of 7 days, 3 weeks running · next stage 6:00?`.
- **Revise.** A block that is on no ladder and was held below 50 % in each of the last 4 such weeks gets one fact: `held 2 of 6 judged days, 4 weeks running · change the block?`. The fact corrects the template; MoonShine never edits it.
- **Phase 4:** the assistant helps build a ladder from the owner's words, as a proposal (ADR-0013). It explains a suggestion with the principles of ADR-0024 (P2-R3).

### The template shapes the plan

- **Capacity:** the template's flexible and protected minutes per line are the weekly capacity the Board starts from (phase 3; this amends ADR-0006 § The model, Capacity).
- **Effort levels:** the budget's `budget_h_week` stays the default `normal` level (ADR-0006). The line's template minutes per week are shown beside it (spec question 28).
- **Template and budget disagree:** for example `template 4 h / week` against `budget 6 h / week`. This is shown as a fact on the line and never reconciled automatically. Showing template hours needs rule 8 to name the routine's block durations among the numbers the owner sets himself (spec question 35).

### Views

- **Ghosts:** today's template blocks drawn as outlines under the facts on the day rail. They are neutral, with no colour for "not held".
- **A week adherence table:** blocks by days, each day's state as a fact (`6:52 · 22 min after 6:30`, `30 of 45 min`, `not tracked`, `no data`), and the metrics against their targets.
- **Line charts:** plan, template and fact on one axis per line and week (P2-RC, after the plans exist).
- **Day checkpoints** (ADR-0022) gain the kind `routineBlockOpen`. It covers a flexible or protected block, or an anchor on a line, of today, whose time has not ended and which is not held yet: `🎻 Violin · 0 of 45 min · 17:00–21:00`. It is offered on a tracked day, and not while today's version is partial.
- **The tone glossary** gains "skipped" among the English banned words with the phase-2 spec's PR (2026-11-01; «пропущено» was already banned), so `scripts/check-catalog.mjs` enforces it.

### The move to MoonShine (the migration path)

1. **Import:** a `confirm` command, undoable. The version in force becomes native `Routine` records. The block ids are kept, so history continues. From then on the note is not read for the template, and the "no note ends the version" rule no longer applies.
2. **Changes in the note after the import** give one info problem, `routineNoteChangedAfterImport`, so an edit there is never silently ignored. The owner removes the marker when he is ready.
3. **Native edits** are commands with undo. Each starts a new version in the same sequence, under the same rule for which version judges a day.
4. **Undo of the import** makes the note the source again; native versions made since are kept in the history. How native versions sync is ADR-0010's matter, decided with the import slice.
5. **Writing back to the note** comes only from the Write phase, as an explicit export command (ADR-0015), never automatically.

The import comes after the routine views and a design round for the editor, not in phase 2 (spec question 27).

### Consequences

- Good — the owner sees, day by day and week by week, whether his routine holds, in facts. A day without data never reads as a lapse.
- Good — progression becomes a ladder with stated criteria instead of willpower; the rules are testable and explainable.
- Good — the template sets the Board's capacity, so planning starts from the week the owner actually schedules.
- Good — one explicit switch from note to native, with history kept.
- Bad — the owner types blocks and ladders by hand in YAML until the native editor exists; a typo is caught only as a problem.
- Bad — the workbook, and dictation without times, judge only minutes, not position.
- Bad — "first seen" depends on the app running: an edit the app sees days later applies from then.
- Bad — versions are stored forever (small: a few kilobytes each).
- Bad — "away" needs a mark the owner sets; a forgotten mark makes an away day read against the home variant until he sets it (allowed back to the previous week, spec question 34).
- Neutral — the vault contract gains `moonshine: routine` (§5, §6.4).

### Confirmation

- **Reader tests** (P2-R1), on invented notes in a temporary folder:
  - each kind, variant rule, metric and ladder is read;
  - a bad block, variant or ladder is skipped with its own problem, and the version is partial;
  - zero valid variants → unavailable;
  - unknown keys and `6:30` are problems;
  - colliding variants and conflicting block keys are reported;
  - the identity rule holds: missing on a clean read, unavailable when anything was unread, rejected at any stage, ambiguous;
  - nothing of the body is read.
- **Version tests** (P2-R1):
  - an unchanged note adds nothing; an edit adds one;
  - A → B → A appends;
  - partial X followed by complete X appends;
  - an unreadable note keeps the last;
  - a clean read without the note ends it from the next day;
  - the canonical hash is the same in every process.
- **Adherence tests** (P2-R2), with a fake clock and invented entries and boundaries:
  - each kind's states at the edges of its tolerances, with minutes claimed once;
  - "no data" against "not tracked", by the evidence rule (a Health walk alone → no data);
  - timer and workbook on one day, never added;
  - running sessions;
  - variant order, away without an away variant, a skipped variant;
  - a day judged against the version in force at its start;
  - Health boundaries before dictated ones, and a Sleep entry as the last source;
  - daylight-saving days in winter and summer.
- **Ladder tests** (P2-R2):
  - advance and step back at the edges of their shares and weeks;
  - weeks under an earlier stage, too few judged days, other variants and a partial version suggest nothing;
  - revise after 4 weeks under 50 %, with at least four judged days a week.
- **Tone check:**
  - no red;
  - none of "missed", "failed", "behind", "skipped" in the UI, in English or Russian, enforced by `scripts/check-catalog.mjs`;
  - distances, not shortfalls.
- **Owner acceptance:** four weeks with a routine note. The method log records, as counts only, the judged days, the share with no data, and the suggestions made and taken.

## Pros and Cons of the Options

### 2. Native from the start

- Good — no YAML; validation in the editor.
- Bad — an editor (blocks, variants, ladders) must be designed and built before anything is compared, and phase 2 has no room for it.

### 3. The note for good

- Good — Obsidian stays the editor; no migration.
- Bad — ladders and suggestions stay manual edits forever. The assistant's ladder proposals (phase 4) could only become vault writes, which wait for the Write phase and its preconditions.

### 4. Two-way sync

- Good — edit anywhere.
- Bad — two sources for one template, which is exactly the two realities this ADR exists to avoid; conflict rules for every field.

### 5. The calendar as the template

- Good — the owner may already have recurring events.
- Bad — events are read-only and never stored (ADR-0012), so history cannot be judged against the template of that time.
- Bad — no kinds, tolerances or ladders.
- Bad — a calendar full of routine blocks changes busy and free time on the day rail.

## More Information

- **Not checked yet:**
  - how many blocks the owner's real routine has; the 64 KiB cap and P2-R1's caps assume a few hundred at most;
  - whether the owner's day ends after midnight often enough that 06:00 should be another hour.
- **Questions for the owner** (`docs/specs/phase-2-plan.md`), decided as proposed (owner, 2026-11-01):
  - 25, the frontmatter cap;
  - 26, where "away" comes from;
  - 27, when the import happens;
  - 28, template against budget;
  - 31, tracking evidence;
  - 32, "shifted" and claimed minutes;
  - 33, a paused line in the past;
  - 34, how far back an away mark may go;
  - 35, rule 8 and the template's hours.
