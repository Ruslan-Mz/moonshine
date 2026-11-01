---
title: "0024 — Evidence base: principles as vault notes, population evidence beside the owner's own data"
status: proposed
date: 2026-11-01
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0005-assistant-tools-over-domain-proposals-and-mcp]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
  - "[[0021-modules-and-the-library-module]]"
  - "[[0022-proactive-day-checkpoints]]"
  - "[[0023-routine-template-adherence-progression]]"
---

# 0024 — Evidence base: principles as vault notes, population evidence beside the owner's own data

## Context and Problem Statement

From phase 4, the assistant will suggest actions:

- for a day checkpoint (ADR-0022, L2);
- for a routine ladder (ADR-0023, slice P2-R3).

A suggestion such as "split the 90-minute practice into two sessions" or "keep bed within 30 minutes every night" rests on a claim about how people learn, sleep or work. The owner wants every such claim:

- written down once, with its conditions and its sources;
- with its evidence stated: how strong it is, and for which outcome;
- checked against his own data.

A result that holds on average across people need not hold for one person. Group-level averages do not, in general, describe the processes within an individual: non-ergodicity, in Molenaar's term. Every suggestion therefore shows two things side by side: what the population evidence says, and what the owner's own data (N = 1) shows.

**How are principles written down, how does MoonShine check them on the owner's data, and how do suggestions use them?**

## Decision Drivers

- **Two levels, never merged**: population evidence and personal data are shown side by side. No single score blends them.
- **Curated by the owner**: the corpus is his, kept outside the repository. The repository holds the format and invented examples only (CLAUDE.md rule 5).
- **Nothing from the vault is executed** (ADR-0015, ADR-0021): a principle names a data rule from a fixed catalogue in code; it never carries a formula.
- **Honest uncertainty**: personal data comes with its n, its period and an interval, and "not enough data" below a minimum. Observational data is labelled as such.
- **Evidence is graded per outcome**: the same practice can have strong evidence for one outcome and only observational evidence for another, so a single label cannot carry it.
- **Citations are verifiable**: a citation counts as verified only when the owner verified it, with a date. The assistant never marks one verified.
- **Model access** (owner, 2026-11-01): the whole principle corpus may be sent to the model. The owner's personal data still follows ADR-0013's consent.

## Considered Options

1. **Principle notes in the vault (`moonshine: principle`), each naming a built-in data rule; suggestions cite them and show both levels.**
2. **A curated database inside MoonShine**, edited in the app.
3. **The model finds evidence at answer time** (web search), with no corpus.
4. **No evidence layer**: suggestions from rules only, with no claims.

## Decision Outcome

**Proposed: option 1.** The owner already curates notes in Obsidian, and the format reuses the vault reader's guards. A fixed catalogue of data rules keeps the personal check deterministic and testable. Citing a principle makes every suggestion traceable.

**Revision (owner, 2026-11-01; `docs/specs/phase-2-plan.md` § Decided, Q30).** The first draft graded a principle with one label on a scale the owner kept in Settings. The owner's corpus grades evidence by design, status and level, for a named outcome; the format below takes that grading. The two levels, the agreement computed from the interval, nothing executed from the vault, citations verified only with the owner's date and the first use in phase 4 are unchanged.

### A principle note

Frontmatter only: the body stays the owner's prose and is never parsed. Invented example; the citation is a placeholder:

```yaml
---
moonshine: principle
id: spaced-practice
title: "Spread practice over several sessions"
claim: "Practice spread over several sessions is retained better than the same time in one session."
conditions: "Skill and recall practice; sessions at least a few hours apart; not for warm-up routines."
mechanism: "Retrieval after a delay strengthens the memory more than repetition within one session."
evidence:
  design: meta-analysis
  status: established
  level: II
  outcome: "recall after a week or more"
  effect: "an invented effect size, with its invented interval"
cost: low
reversible: true
feedback: without
applies_to: [practice]
sources: ["[[Invented corpus note#Spacing]]"]
source_checked: 2026-10-20
corpus_snapshot: 2026-11-01
sharing: private
citations:
  - {
      text: "Invented, A. (2001). An invented review of spaced practice. Invented Journal, 1(1), 1–10.",
      doi: "10.0000/invented.1",
      verified: 2026-11-01,
    }
data_rule: { rule: practice_days_vs_minutes, needs: [entries], window_days: 84 }
---
```

| Key                   | Meaning                                                                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                  | a stable slug, the key suggestions cite                                                                                                                               |
| `title`               | a short name, shown in lists                                                                                                                                          |
| `claim`, `conditions` | the owner's words, shown as written                                                                                                                                   |
| `mechanism`           | optional: the corpus often states none                                                                                                                                |
| `evidence`            | `design`, `status`, `level`, `outcome` and `effect` (below)                                                                                                           |
| `cost`                | `low` · `medium` · `high`                                                                                                                                             |
| `reversible`          | `true` or `false`                                                                                                                                                     |
| `feedback`            | `with` · `without`: whether the outcome is visible to the owner                                                                                                       |
| `applies_to`          | line roles, never line names                                                                                                                                          |
| `sources`             | wiki-links to the corpus notes and their sections                                                                                                                     |
| `source_checked`      | the corpus note's own check date                                                                                                                                      |
| `corpus_snapshot`     | when the principle was last reconciled with the corpus                                                                                                                |
| `sharing`             | the note's sharing setting                                                                                                                                            |
| `citations`           | a list of `{ text, doi?, url?, verified? }`: `text` is the full reference as the corpus writes it; `verified` is the date the owner checked it, absent for unverified |
| `data_rule`           | `{ rule, needs, window_days?, …params }`: a rule from the catalogue, the data sources it reads, and its parameters; absent for a design principle with no metric      |

### Evidence

```yaml
evidence:
  design: cohort # rct-clinical | rct-intermediate | meta-analysis | experiment | cohort | cross-sectional | mechanism | review | method
  status: established # established | contested | null-confirmed | open | single-study
  level: II # the corpus's levels for a cognitive or dementia outcome: I | II | III | n/a
  outcome: "..." # the outcome the evidence is about, in the owner's words
  effect: "..." # the effect as the source states it, with its interval
```

- **The vocabularies are fixed in code**, like the rule catalogue. A value outside them is a problem, and the principle is still shown, with "evidence unknown".
- **Status is shown, never hidden.** `contested`, `null-confirmed`, `open` and `single-study` principles appear with their status. A null-confirmed principle is evidence too: it tells the owner what not to spend time on.
- **Citations:** shown with "verified" and its date, or "not verified". The corpus's own check date is `source_checked`, never a citation's `verified`. The assistant may propose a citation, as a proposal (ADR-0013). It never writes `verified`.

### The data-rule catalogue (in code)

Each rule turns the owner's own stored data into an observational comparison. It returns an effect, n, the period and an interval (bootstrap over days or weeks), or "not enough data". A rule whose `needs` are absent says "not enough data yet" without running.

These are the rules the owner's first principles name. **They are built in phase 4** (owner, 2026-11-01), each in code with tests on invented histories. The last column names the earliest point a rule can be built, once its data exists; nothing from the catalogue lands inside a phase-2 slice:

| Rule                                                                                         | Needs                          | Earliest it can be built                                                                     |
| -------------------------------------------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------- |
| `sleep_regularity`                                                                           | Health sleep                   | after H                                                                                      |
| `short_night_next_day`                                                                       | Health sleep, routine, entries | after H and P2-R2                                                                            |
| `steps_daily`                                                                                | Health steps                   | after H                                                                                      |
| `weekly_exercise_volume`                                                                     | Health workouts                | after H                                                                                      |
| `days_since_practice`                                                                        | entries, OmniFocus completions | after X2                                                                                     |
| `long_sessions_share`                                                                        | entries                        | after TM1                                                                                    |
| `practice_days_vs_minutes`                                                                   | entries                        | after X2                                                                                     |
| `retrieval_share`, `hard_block_reading_share`                                                | a session kind on entries      | needs a session-kind field: not planned yet (`docs/specs/phase-2-plan.md`, open question 37) |
| `hard_blocks_week`, `routine_stage_age`, `anchor_vs_plain_adherence`, `adherence_by_context` | routine, entries               | after P2-R2                                                                                  |
| `estimate_bias`                                                                              | OmniFocus estimates, entries   | F4 already computes it                                                                       |

- A principle naming an unknown rule, wrong parameters or unknown `needs` is a problem. The principle is shown with population evidence only.
- New rules are added in code, each with tests on invented histories. That is a slice, never a note.
- **Every personal result is labelled as an observation**: "your data, not a trial", with n and the interval. Below each rule's minimum n it reads "not enough data yet".

### Two levels side by side

A suggestion that cites a principle shows, in this order, never blended:

1. **The claim** with its evidence (design, status, level, outcome) and its verified citations.
2. **The owner's data:** the rule's result with n, the period and the interval, or "not enough data yet".
3. **Agreement, as a fact:** `your data agrees` · `your data shows no difference` · `your data points the other way` · `not enough data`. The fact is computed from the interval: it excludes zero on the claim's side, contains zero, or excludes zero on the other side.

"Your data points the other way" is a fact, never a verdict on the claim or on the owner.

### Use

- **Phase 4**, the first slice that uses principles (L2 of ADR-0022, P2-R3 of ADR-0023), reads them. Until then the format is reserved: vault contract §5 reserves `principle`, and no phase-2 slice reads it.
- **Every suggestion of L2 and P2-R3 cites** the principle ids it rests on. A suggestion with none says `no principle`.
- **Rules never need principles.** ADR-0022's checkpoints and ADR-0023's ladder rules work without them. Principles explain and inform; they do not trigger.

### Reading and access

- **The reader** is the `moonshine` key scanner of vault contract §6 (P1, or whichever slice brings it first), with its 8 KiB frontmatter cap: a principle is short.
- **To the model** (owner, 2026-11-01): the whole corpus of principle notes may be sent, as part of the standing context (ADR-0013 § Standing context). The rules that still hold:
  - the consent for cloud AI of the chosen provider is still required (ADR-0005, amendment 2026-11-01);
  - a note with `moonshine_ai: false` is never sent (ADR-0013, amendment 2026-10-06);
  - the owner's personal results are sent only under ADR-0013's rules for his data.
- **Content stays outside the repository.** Fixtures and examples are invented, with placeholder DOIs (`10.0000/invented.N`).

### Consequences

- Good — every suggestion is traceable to a claim, its evidence and its sources, and the owner sees whether his own data agrees.
- Good — evidence is stated for an outcome, with its status shown, so a contested or null result is visible rather than graded away.
- Good — non-ergodicity is built into the screen: the average never stands in for the person.
- Good — the data rules are deterministic and tested; the model explains, it does not compute the evidence.
- Bad — the corpus is the owner's work to keep; an uncurated claim gives a suggestion without a principle.
- Bad — personal results are observational: confounded, with small n; the labels say so, and that does not remove it.
- Bad — new rules need code, so a principle can wait for its rule; two rules wait for a session kind that is not planned yet.
- Neutral — the vault contract gains a reserved kind; the evidence vocabularies are code, so a new design or status needs a slice.

### Confirmation

- **Reader tests** (in the phase-4 slice) on invented notes:
  - each key read;
  - an evidence value outside its vocabulary, an unknown rule and unknown `needs` reported, with the principle still shown;
  - a citation without `verified` shown as not verified; `source_checked` never shown as a citation's verification.
- **Rule tests** on invented histories, each:
  - an effect that agrees, none, and the reverse;
  - "not enough data" below the minimum, and without its `needs`;
  - intervals with a fixed seed.
- **View-model tests:**
  - the two levels are separate fields, and no score combines them;
  - every status is shown;
  - agreement follows the interval;
  - a suggestion without a principle says so.
- **Privacy:**
  - principle text is sent only with consent, and never from a `moonshine_ai: false` note;
  - personal results follow ADR-0013;
  - logs carry kinds and counts.

## Pros and Cons of the Options

### 2. A database in MoonShine

- Good — structured editing, validation in the editor.
- Bad — an editor before any value; the owner's notes move out of Obsidian, against ADR-0015's "notes stay Markdown files".

### 3. Evidence found by the model at answer time

- Good — no corpus to keep.
- Bad — unverified sources, a different answer each time, citations that may not exist; nothing to test.

### 4. No evidence layer

- Good — nothing to curate.
- Bad — suggestions with no stated basis. The owner cannot tell a sound one from a plausible one.

## More Information

- Background for the two levels:
  - Molenaar, "A manifesto on psychology as idiographic science: bringing the person back into scientific psychology, this time forever", _Measurement_ 2(4), 2004;
  - Fisher, Medaglia and Jeronimus, "Lack of group-to-individual generalizability is a threat to human subjects research", _PNAS_ 115(27), 2018.
- The first draft's rules `session_spacing`, `bed_time_spread` and `switches_per_hour` became `practice_days_vs_minutes`, `sleep_regularity` and a later rule (owner, 2026-11-01).
- Questions for the owner (`docs/specs/phase-2-plan.md`, question 30), decided on 2026-11-01:
  1. the grade: replaced by the evidence block, with vocabularies fixed in code;
  2. citation verification: the owner's date only;
  3. the rule catalogue: fixed, in code, built in phase 4; the table names the earliest point each rule can be built;
  4. when principles are first read: the first phase-4 slice that uses them.
- Open: a session kind on time entries (`docs/specs/phase-2-plan.md`, question 37), decided at TM1's planning.
