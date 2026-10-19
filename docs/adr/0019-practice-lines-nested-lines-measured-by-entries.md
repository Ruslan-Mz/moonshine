---
title: "0019 — Practice lines: nested lines measured by entries in the vault"
status: accepted
date: 2026-10-19
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0014-project-hub-bindings-in-project-note-and-link-index]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[0018-memos-rule-bound-notes-on-events-and-tasks]]"
---

# 0019 — Practice lines: nested lines measured by entries in the vault

## Context and Problem Statement

Some of the owner's lines have no time and no tasks of their own: a journal, a report to himself. Their time is already spent inside another line, and what matters is how regularly the entries are written. Today such a line can only be given `budget_h_week: 0`. MoonShine then shows an active line with no budget, no hours and no tasks: it reads as a shortfall, or as nothing at all. **How does a line measured by entries live in the budget note, where do its entries come from, and how is it shown?**

## Decision Drivers

- The vault is the source of the facts. An entry is a note the owner writes anyway.
- Entry texts are among the most private data. MoonShine needs only that an entry exists.
- No hour is counted twice, and no hour is lost.
- A failed read never looks like "no entries" (the lesson of S3b-2).
- UI tone (CLAUDE.md rule 8): regularity, not failure.
- Existing budget notes keep working unchanged.

## Considered Options

1. **A nested line with `measure: entries`, counted from entry notes found by `moonshine: entry`.**
2. A normal line with `budget_h_week: 0`, special-cased in the UI.
3. Entries counted from a heading in the daily note.
4. A native counter in MoonShine: a button "I wrote it".

## Decision Outcome

**Chosen option: "1"** (owner, 2026-10-19), because the entry note is the fact itself, the line's time stays with the line that actually spends it, and nothing new has to be typed into MoonShine.

**This ADR amends the vault contract** (budget note fields, the entry note), **ADR-0014** (entry bodies are never read for the link index) and **ADR-0016** (time logged on a nested line goes to its parent).

### Budget note: three optional fields on a line

| Field     | Values                                                         | Meaning                                                  |
| --------- | -------------------------------------------------------------- | -------------------------------------------------------- |
| `within`  | the id of another line                                         | The line is nested; its time belongs to that parent      |
| `measure` | `hours` (default) · `entries`                                  | What the line is measured by                             |
| `targets` | list of `{kind, count, per}`, `per` ∈ `day` · `week` · `month` | Entry targets, e.g. diary 5 per week, report 1 per month |

Rules:

- **One level of nesting.** A parent has no `within`.
- **The parent is measured by hours.**
- **A nested line has no budget.** A budget above 0 is ignored, and the problem says so. The line is never part of shortfall, forecast or the budget total.
- **Time goes to the parent, always.** A timer, a task or a calendar block attributed to a nested line is recorded on its parent (ADR-0016). The timer's line picker does not offer nested lines.
- `measure: entries` without `within` is allowed: a practice with no parent spends no planned time.

### Entry notes

```yaml
---
moonshine: entry
line: reflection # a line with measure: entries
date: 2026-10-19 # optional when the file name starts with YYYY-MM-DD
kind: diary # free text, at most 40 characters; compared with the line's targets
covers: 2026-10 # optional: an ISO week (2026-W43) or a month (2026-10)
---
```

- The note can be anywhere in the vault. It is found by the `moonshine` key (ADR-0018), never by folder.
- **Only the frontmatter is read.** The reader stops at the closing `---`. The body is not parsed, indexed, shown or sent anywhere, and the link index (ADR-0014) skips entry notes. UI, notifications and logs carry counts only.
- **Date:** `date` when present; otherwise the leading `YYYY-MM-DD` of the file name; otherwise the entry has no date, is reported and is not counted.
- **Period:** for a target, an entry counts in the period its `covers` names when present, otherwise in the period of its `date`. A report for October written on 2 November counts for October. Weeks are ISO weeks starting on Monday; all dates are local.
- **Several entries on one day** all count as entries; the day counts once as a day with an entry.
- **Window:** entries are counted for the current month and the 12 before it. Older notes are skipped without a problem.

### Read state

- The counts are a typed result: **read**, **partly read** (some entries were rejected or unreadable; the counts are a lower bound and shown as "at least") or **unavailable** (the vault could not be read).
- When the vault is unavailable, the last known counts are shown with their date. They are never shown as 0, and no streak is broken by a failed read.

### Problems

| Kind                      | When                                                   | Effect                                 |
| ------------------------- | ------------------------------------------------------ | -------------------------------------- |
| `lineParentMissing`       | `within` names no line                                 | The line is read as not nested         |
| `lineNestedTooDeep`       | the parent has its own `within`                        | The line is read as not nested         |
| `lineParentNotHours`      | the parent has `measure: entries`                      | The line is read as not nested         |
| `lineNestedBudgetIgnored` | a nested line has a budget above 0                     | The budget is ignored                  |
| `entryWithoutDate`        | no `date` and no date in the file name                 | The entry is not counted               |
| `entryLineUnknown`        | `line` names no line                                   | The entry is not counted               |
| `entryLineNotEntries`     | the line is measured by hours                          | The entry is not counted               |
| `entryInvalid`            | a bad `covers`, `kind` too long, frontmatter over 8 KB | The entry is not counted               |
| `entryKindNotInTargets`   | `kind` is in none of the line's targets (info)         | Counted for the line, not for a target |

### Display

- **Practice line card:**
  - entries this week and this month, and the last entry's date;
  - progress to each target ("diary 4 of 5 this week");
  - the streak of consecutive **periods** that met their target (weeks for a weekly target, months for a monthly one). The current period is never counted as missed while it is still running.
  - No hours, no budget, no daily streak.
- **Parent line card:** the nested line as a chip. The parent's hours are not split.
- **Weekly and quarterly review:** practices as regularity ("5 of 7 days", "4 of 4 weeks met"), not as hours.

### Memos

A memo's `after.entry` (ADR-0018) names a line and a kind. The memo shows "written" when a matching entry exists for that day. The memo's own outcome is kept by MoonShine, but the fact of writing comes only from the entry.

### Roadmap

| Phase / slice      | Change                                                                                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 2            | **Practice lines**, after P1 (ADR-0018), sharing its scanner. Risky: parses vault notes. Budget note fields, entry notes, counts, problems, the practice card. Re-baseline phase 2's forecast. |
| Later review views | Each review view, when it is built, shows practices as regularity.                                                                                                                             |

### Consequences

- Good:
  - practice lines stop reading as a shortfall;
  - no hour is counted twice;
  - entry texts never leave the vault, not even into MoonShine's memory.
- Good — the memo's "written" and the practice count are the same fact.
- Bad — the owner adds four frontmatter lines to each entry. A template (ADR-0015 ritual or an Obsidian template) does it for him.
- Bad — entries older than 13 months are not counted.
- Neutral — the scanner of ADR-0018 gains a third note kind; matching and counting live in Core.

### Confirmation

- **Budget note tests:**
  - a nested entries line with budget 0 gives no shortfall;
  - each problem in the table, on a fixture;
  - the other lines still read when one line has a problem;
  - a nested line with a budget above 0 is excluded from the budget total.
- **Entry tests:**
  - three entries on one date count three entries and one day;
  - the date is taken from the file name when `date` is absent;
  - `covers` moves a report into its month;
  - the ISO week boundary is Sunday to Monday;
  - an entry on an hours line is not counted;
  - an entry outside the window is skipped.
- **Privacy tests:** an entry's body (with wikilinks and a sentinel string) appears in no index, no model, no log, no problem text, no export.
- **Read-state tests:** an unreadable vault gives "unavailable" with the last counts, never 0; a rejected entry gives "partly read"; a streak is unchanged by a failed read.
- **Time tests:** a timer, a task and a calendar block on a nested line are recorded on the parent; the timer picker lists no nested line.

## Pros and Cons of the Options

### 2. A line with budget 0

- Good — no contract change.
- Bad — the line has no measure; every view needs a special case; regularity has nowhere to live.

### 3. A heading in the daily note

- Good — no new notes.
- Bad — MoonShine would have to read daily note bodies, the most private text. Monthly reports do not live in daily notes.

### 4. A native counter

- Good — no parsing.
- Bad — a second fact beside the note: pressing the button without writing, or writing without pressing, both make the count wrong.

## More Information

Follow-up: entry targets per weekday (e.g. a report on Sundays only).
