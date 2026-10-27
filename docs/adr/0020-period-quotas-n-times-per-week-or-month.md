---
title: "0020 — Period quotas: a repeating task done N times per week or month"
status: accepted
date: 2026-10-26
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0011-change-driven-import-full-snapshots-on-omnifocus-deactivation]]"
  - "[[0017-reminders-native-entity-omnifocus-tag-bridge]]"
  - "[[0019-practice-lines-nested-lines-measured-by-entries]]"
  - "[[0021-modules-and-the-library-module]]"
---

# 0020 — Period quotas: a repeating task done N times per week or month

## Context and Problem Statement

Some of the owner's repeating tasks have no due date in the usual sense. What matters is how many times they are done in a period: once a week, twice a week, twice a month. If the period's count is reached, the task is fine and rests until the next period. If the period is running out with the count not reached, the owner wants to see that it is time. If a period ended short, he wants to see that too, more or less prominently depending on the task. OmniFocus can express a due date or a repeat interval, but not "2 times this week". **How does MoonShine know a task's quota, count it, and show where it stands?**

## Decision Drivers

- Works while OmniFocus is read-only (before the Act phase).
- The same period rules as practice targets (ADR-0019): ISO week from Monday, calendar month, local dates, a streak of periods, the current period never counted as missed while it runs, a failed read never shown as zero.
- Some quotas are gentle reminders of a habit; others matter. The owner chooses how loud a short period is.
- UI tone (CLAUDE.md rule 8): no red, no "missed" or "overdue" wording; amber only where the owner asked for emphasis.

## Considered Options

1. **An OmniFocus tag on the task (`2/нед`, `1/мес`), counted from completed copies in the snapshot; emphasis per line with a per-task override.**
2. A quota set in MoonShine per task (native record).
3. Quotas listed in the vault's budget note per line.

## Decision Outcome

**Chosen option: "1"** (owner, 2026-10-26), because tags already reach the snapshot, so it works now. **Option 2 is the planned successor** once MoonShine has native writes: a native quota then overrides the tag.

### Declaring a quota

- **Tag grammar.** A leaf tag name, trimmed and matched without case:
  - `N/нед` (also `N/week`) — N from 1 to 7;
  - `N/мес` (also `N/month`) — N from 1 to 31;
  - an optional trailing `!` marks strong emphasis;
  - an optional trailing `+` allows carry-over (below). Both may be present in either order, e.g. `2/мес+!`.
- **Only repeating tasks.**
  - A quota tag on a non-repeating task gives the problem `quotaNotRepeating`, and the task behaves as usual.
  - A tag that looks like a quota but is out of range gives `quotaInvalid`.
  - Two quota tags on one task give `quotaAmbiguous`, and neither applies. No tag wins over another.
- **Reminders** (ADR-0017) carry no quota. A quota tag on a reminder is ignored and reported.

### Counting

- **What counts:** the completed copies of the task's repeat series (the live task and its completed occurrences in the snapshot) whose completion date, in the workspace time zone, falls in the period.
- **Periods:** an ISO week starting on Monday, or a calendar month.
- **Coverage:** the snapshot's completion window must cover the current and the previous period, up to 62 days.
  - When it does not, the count is **partly read**, shown as "at least N", and no period is reported short.
  - When the snapshot cannot be read, the last known counts are shown with their date, never 0.

### Showing it

The state of the current period:

| State    | Condition                                          | On Today and in lists                                                                                                           |
| -------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Met**  | count ≥ N                                          | The task leaves Today and every open-task list until the next period starts. It still shows in Done today when completed today. |
| **Open** | count < N, days left > needed + 1                  | Shown by its OmniFocus dates as usual, with a quiet chip `1 of 2 · this week`.                                                  |
| **Time** | count < N, days left ≤ needed + 1 (today included) | Chip `time · 1 of 2 · by Sun`, secondary text when neutral, amber when strong.                                                  |

"Needed" is N minus the count. So "2 per week" with none done shows _time_ from Friday, "1 per week" from Saturday, and "2 per month" from three days before the month ends.

A period that ended short:

| Emphasis              | Where                                                                                          | How long                                          |
| --------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **Neutral** (default) | A fact on the task's row, `last week: 1 of 2`, secondary text; and in the week or month review | The first day of the new period                   |
| **Strong**            | The same fact, in amber                                                                        | Until the current period is met, or until it ends |

Wording is a fact, never "missed" or "overdue". There is no red.

### Over-quota and carry-over (owner, 2026-10-26)

- A period done more often than its quota shows the real count: `3 of 2 ✓`. The period is met, and the history keeps the real number. No count is capped or hidden.
- **No carry-over by default.** The surplus of one period never covers the next, because these quotas are about regularity.
- **Carry-over by flag.** With `+` on the tag, the surplus of a period counts toward the next period only, up to N. Example: `2/мес+` done 4 times in October is already met for November. It is shown as `2 of 2 ✓ (carried)`. The next period's own completions add to it as usual.

### Emphasis

- **Line default:** the budget note's line gains `quota_emphasis: neutral | strong` (absent = neutral).
- **Task override:** a trailing `!` on the quota tag makes that task strong.
- **Precedence:** task override → line default → neutral.
- The same level may later drive other signals (for example the deadline rule). That is a separate decision; this ADR uses it for quotas only.

### Streak

The consecutive periods that met their quota, shown wherever practice streaks are shown (ADR-0019), with the same rule: the running period is never counted as missed.

### Problems

| Kind                       | When                              | Effect  |
| -------------------------- | --------------------------------- | ------- |
| `quotaInvalid`             | a quota-like tag out of range     | ignored |
| `quotaAmbiguous`           | two quota tags on one task        | ignored |
| `quotaNotRepeating`        | quota tag on a non-repeating task | ignored |
| `quotaOnReminder`          | quota tag on a reminder           | ignored |
| `lineQuotaEmphasisInvalid` | a bad `quota_emphasis` value      | neutral |

Every problem names the task by its OmniFocus id, never by title (rule 5 for logs).

### Roadmap

| Phase / slice | Change                                                                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Phase 2       | **Quotas**, after Practice lines (ADR-0019), on the same period, streak and read-state code. Risky: parses outside data (tag names). |
| Later         | A native quota in MoonShine overrides the tag (needs native writes). Optional "by weekday" inside a week, and "every N days".        |

### Consequences

- Good:
  - "N times per period" works without changing OmniFocus;
  - a met task gets out of the way until the next period;
  - one period engine for practices and quotas.
- Bad:
  - the owner must set the OmniFocus repeat to "after completion" (for example defer 1 day). A fixed weekly due date would move the task to next week after the first completion, so the second one would never happen. The setup doc says so.
  - a quota lives in a tag name: a typo is caught only as a problem.
  - hiding a met task depends on the snapshot. Between imports a completion in OmniFocus is not seen yet (ADR-0011's refresh bounds the delay).

### Confirmation

- **Grammar tests:**
  - every valid form, Russian and English, with and without `!` and `+`, in either order;
  - out-of-range values;
  - two quota tags;
  - a non-repeating task;
  - a reminder.
- **Count tests:**
  - completions on Sunday 23:59 and Monday 00:00 land in different weeks;
  - the month boundary;
  - a copy completed in the previous period is not counted;
  - a window that does not reach the period start gives "partly read" and no short period.
- **Over-quota tests:**
  - 3 of 2 is met and the history keeps 3;
  - without `+` the next period starts at 0;
  - with `+` the surplus counts once, toward the next period only, capped at N.
- **State tests with a fake clock:**
  - _met_ hides the task until the next period and shows it again then;
  - _time_ starts on the computed day for 1/week, 2/week and 2/month.
  - a short period:
    - with neutral emphasis it shows only on the first day;
    - with strong emphasis it stays until met;
    - the task's `!` overrides the line default.
- **Tone check:** no red; no "missed" or "overdue" in English or Russian.
