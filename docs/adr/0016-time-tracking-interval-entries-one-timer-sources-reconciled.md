---
title: "0016 — Time tracking: one running timer, interval entries, nudges as facts, Excel reconciled by day and line"
status: proposed
date: 2026-10-07
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0012-calendar-eventkit-read-only-per-device]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
---

# 0016 — Time tracking: one running timer, interval entries, nudges as facts, Excel reconciled by day and line

## Context and Problem Statement

The owner records his hours in an Excel workbook, mostly from memory at the end of the day; he cannot say whether work took 5 or 6 hours. He wants to start a timer on a task, a project or a line (also by voice, from a widget, later from a watch), to be told "you have been working for an hour" or "today's four hours are done", to see the day by the clock and correct it, and to keep the option of the workbook. The project already has a `TimeEntry` (line or project or step, start, duration, source), a quick log in phase 2, an iPhone "practice timer" on a line in 3b, a voice `LogTime` command (ADR-0013) and the Excel import (phase 2). It has no timer on the Mac, no timer on a task, no editing of intervals, no nudges, and no rule for two sources of hours. **How is time recorded so that it is exact, correctable, usable by the forecast, and never counted twice?**

## Decision Drivers

- Exact time is evidence for the forecast (ADR-0006): actual against estimate, per line and per task.
- Recording must cost one action, or it will be skipped like the end-of-day log.
- The owner is often in flow and forgets the clock; corrections after the fact must be easy and leave a trace.
- The Mac is where most tracked work happens; the phone and the watch are where a timer is easiest to reach.
- The workbook stays in use (owner decision, 2026-10-07): both sources live on, and no hour is counted twice.
- UI tone (CLAUDE.md rule 8): no guilt, no streaks, no red.
- One write path with undo for the UI, the widgets and the assistant (ADR-0013).

## Considered Options

1. **A synced timer session that produces interval entries; one running timer; every entry has a source; sources reconciled by day and line.**
2. Duration-only entries: minutes per day per line, as in the workbook; a timer only adds minutes.
3. Parallel timers with overlapping entries.
4. Automatic tracking from the frontmost app and window.
5. An existing time-tracker app, imported like the workbook.

## Decision Outcome

**Chosen option: "1"**, because intervals on the clock give the forecast exact evidence, put actual time on the same day axis as the calendar and the plan, make corrections simple, and let two sources be compared instead of summed.

**This ADR amends ADR-0013** (timer commands join the `auto` class), **ADR-0012** (what a confirmed calendar entry and a timer target keep of an event, below) and the Excel import contract (the workbook is no longer "the source of truth until the quick log exists").

### Records

- **`TimerSession`** (native, synced under ADR-0010): subject, started at, state (`running` · `paused` · `stopped`), the device it was started on, an optional target (a duration or a clock time; a target taken from an event is only a duration).
- **`TimeEntry`** gains fields: `day` (the local calendar date it belongs to), optional `start` and `end` (instants) with the time zone at capture, `minutes`, the subject, `source`, `session`, `edited`.
  - **Subject:** a line (or Life ops, when the task maps to no line), and optionally a project, a task or a plan step. The line is stored on the entry at capture, so a later change of mapping does not rewrite history; re-attributing is an explicit command.
  - **Source:** `timer` · `manual` · `excel` · `calendar` (confirmed by the owner from an ended event) · `omnifocusEstimate` (derived).
- **Calendar entries** (owner, 2026-10-09; amends ADR-0012). A time entry the owner confirms from an event keeps the event's start, end and line, never its title, attendees, id or calendar name. A timer target taken from an event is only a duration. These are the only event-derived values besides ADR-0012's busy minutes that leave the device.
- **Intervals are the atoms.** Pause closes an interval and resume opens the next one in the same session; each interval is one entry. An interval that crosses local midnight is split in two at stop. A workbook entry has a day and minutes and no clock times.

### One running timer

Starting a timer stops the one that is running, at that instant. The same rule merges sessions started on two devices without a network: ordered by start time, a session still running when a later one starts ends at that later start. Every device computes the same result. A running session survives the app being closed (the start time is stored).

### Commands

All go through the `CommandBus`, land in the activity log and can be undone: `StartTimer(subject, target?, startedAt?)`, `PauseTimer`, `ResumeTimer`, `StopTimer(at?)`, `LogTime` (exists), `EditTimeEntry` (start, end, minutes, subject, note), `SplitTimeEntry`, `DeleteTimeEntry`, `ResolveTimeSources(day, line, choice)`.

- An edited entry keeps `edited` and its previous values in the log. Edits never overlap another entry silently: the neighbour is shown and the owner chooses to trim it or to cancel.
- `startedAt` and `at` cover "I started twenty minutes ago" and "I finished half an hour ago".

### Where a timer is started and stopped

| Place                                                                            | From                       |
| -------------------------------------------------------------------------------- | -------------------------- |
| Mac: menu bar item, ⌘K, a task, project or line row                              | the Timer slice            |
| iPhone and iPad: the timer sheet, Live Activity, buttons in widgets and controls | 3b                         |
| Siri and Shortcuts on every device (App Intents; no AI involved)                 | with each platform's timer |
| The assistant, from a dictated sentence                                          | the Ask phase              |
| Watch                                                                            | after 3b                   |

Buttons in widgets are allowed before the Act phase because a timer is native data, not a provider write.

### Voice

`StartTimer`, `PauseTimer`, `ResumeTimer` and `StopTimer` are `auto` commands (ADR-0013): native, undoable, answered in one line. The conditions of ADR-0013 hold: the subject and any time offset are spans of the utterance, and the app resolves the subject itself (exactly one line, project or open task). No match or several matches → one question, never a guess. `EditTimeEntry` by voice is `auto` only for the entry just stopped; anything else is a proposal.

### The day by the clock

- **Today** shows tracked intervals on the day rail next to calendar events and planned tasks: plan against actual on one axis. Interval edges can be moved; a gap can be filled with a manual entry.
- **A week table**: lines by days, in minutes, with a drill-down to projects and tasks. It reads like the workbook's grid.
- Weekly, quarterly and yearly views read the same entries. The facts placeholder of ADR-0015 puts the day's or week's hours into a journal note; entries themselves are never written to the vault.

### Nudges

A nudge is a local notification on the device where the session was started, and a quiet state everywhere else. Each kind can be switched off; none is repeated for the same mark.

| Kind                | Fires when                                                                                                                            | Wording, as a fact         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| Break reminder      | every N minutes of a running session (N per line, default 50; on by default)                                                          | `🎻 50 min · short break?` |
| Session target      | the target set at start is reached                                                                                                    | `🎻 2 h reached`           |
| Day mark            | today's tracked time on a line reaches its floor or its portion                                                                       | `Today's 4 h are in`       |
| Calendar suggestion | five minutes before an event in a line-mapped calendar: an offer to start a timer on that line, with the event's length as the target | `🏃 17:00 · Start timer?`  |

- **Day mark.** The _floor_ is the line's `floor_h_day`. The _portion_ is the sum of today's events in the line's calendar, else the line's optional `portion_h_day` in the budget note. A line with neither has no day mark. From the Board phase a project's portion comes from the plan. Hours may be shown next to the portion: CLAUDE.md rule 8 names `portion_h_day` and the length of events in a line's calendar (owner, 2026-10-08).
- The calendar suggestion reads events on the device, as every calendar feature does (ADR-0012); nothing about the event is stored except, once the owner starts the timer, the target's duration (§ Records). It needs the app to have run that day, so it is best effort.
- Titles of tasks and events are not shown on a locked screen unless the existing setting allows it.
- **Break reminder.** Its two actions are `Break` and `Keep going`. `Break` pauses the timer, so the break is not counted, and one reminder to resume follows after the break length (default 5 minutes). Without an answer the timer keeps running.
- No streaks. A day mark is never shown as missed.

### A forgotten timer is visible (owner decision, 2026-10-07)

- A running session is always in sight: elapsed time in the Mac menu bar, a growing block on the Today rail, the Live Activity and widgets on the phone.
- A session gets a **check** mark when it has run longer than the line's limit without a pause (default 4 hours), or when the Mac slept while it ran. The mark shows on the menu bar item and on the resulting entry.
- Nothing is stopped or trimmed silently. When a marked session is stopped, the owner is offered "end at the time the Mac went to sleep" next to "keep as it is". The entry stays marked until he confirms or edits it.
- Detecting idle time while the Mac is awake is not in the first version.

### Two sources: the timer and the workbook

Both stay. The unit of comparison is **(day, line)**.

- Entries are _measured_ (`timer`), _stated_ (`manual`, `excel`, `calendar`) or _derived_ (`omnifocusEstimate`).
- A derived entry is counted only for a (day, line) that has no measured and no stated entry.
- When a (day, line) has both native entries (`timer`, `manual`, `calendar`) and `excel` entries, and their totals differ by more than the tolerance (default 10 minutes), the pair goes to a **reconcile list**. Within the tolerance the pair is resolved automatically as "the same session" (the native entries stand) and is not listed; it can be reopened from the day view, where all four choices are offered (owner, 2026-10-09).
- Until the owner decides, the native entries are counted and the cell is marked "two sources". The two are never added together.
- Choices: keep MoonShine · keep the workbook · keep both (they were different sessions) · **the workbook's total is right** (the difference becomes one manual entry without clock times). Keeping the workbook marks that day's native entries for the line as not counted.
- "The workbook's total is right" is offered only when the workbook's total is larger. When it is smaller, the choices are keep MoonShine or keep the workbook. No entry is ever negative, and no measured entry is deleted (owner, 2026-10-09).
- The choice is stored for that (day, line). Importing the sheet again does not reopen it unless the workbook's value changed.

### Roadmap

| Phase    | Change                                                                                                                                                  |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2 Plan   | `TimeEntry` gets the new fields from its first slice; the import and the quick log use them. The reconcile rule is part of the import.                  |
| 2 Plan   | **Timer (Mac)** is the last slice: sessions, menu bar, start from a row and from ⌘K, the day rail with editing, the week table, nudges, the check mark. |
| —        | Fallback: if the other phase-2 slices are not merged by 2026-12-07, Timer (Mac) moves to directly after R1. The R1 deadline does not move.              |
| 3b       | The iPhone timer takes a task or a project as well as a line; buttons in widgets and controls; Siri.                                                    |
| Ask      | Start, stop and corrections through the assistant.                                                                                                      |
| After 3b | Watch; standalone countdown timers that belong to nothing.                                                                                              |

### Consequences

- Good — exact hours with one action; the forecast gets actual against estimate per task and per line.
- Good — plan against actual on one day axis; corrections are edits with a trace and undo.
- Good — start on one device and stop on another; no AI needed for voice through Siri.
- Good — the workbook keeps working, and no hour is counted twice.
- Bad — keeping both sources means a reconcile list to work through; while a day is undecided its total may be too low.
- Bad — one timer at a time cannot express two things done at once.
- Bad — a forgotten session is marked, not stopped: its entry stays wrong until the owner confirms or trims it.
- Bad — the calendar suggestion and the nudges depend on notifications the system may delay, and on the app having run.
- Bad — phase 2 grows by a slice next to a fixed R1 date; the fallback rule limits the risk and does not remove it.
- Bad — the line stored on an entry can disagree with a later mapping; re-attribution is manual.
- Neutral — the screen spec's "no streaks or goals in the log" becomes "no streaks; targets and day marks are optional, neutral facts".

### Confirmation

- Core tests: starting a timer stops the running one at the same instant; two offline sessions merge to the same entries on both devices; pause and resume give separate intervals; an interval across midnight is split; a daylight-saving change and a time-zone change keep the minutes right; an edit that would overlap a neighbour is refused until the owner chooses; every command can be undone.
- Reconcile tests: totals within the tolerance list nothing and resolve as "the same session", and reopening that pair from the day view offers all four choices; a smaller workbook total offers only keep MoonShine and keep the workbook, and keeping the workbook marks the native entries as not counted without deleting any; no choice creates a negative entry; beyond it the pair is listed, the native entries are counted and the two are never summed; each choice gives the stated result; a re-import does not reopen a decided pair unless the workbook's value changed; a derived entry is not counted next to a measured or stated one.
- Assistant tests (the Ask phase): a subject with two matches never starts a timer; a time offset that is not in the utterance is never applied.
- Nudge tests with a fake clock: each kind fires once per mark; none fires on a device that did not start the session; a line without a floor or a portion has no day mark; `Break` pauses the session and the resume reminder fires once.
- Calendar tests: an entry confirmed from an event stores its start, end and line and no title, attendee, id or calendar name; a timer target from an event stores only a duration.
- Check-mark tests: a session past its limit, or one that spans Mac sleep, is marked; nothing is trimmed without the owner's choice; a marked entry stays marked until it is confirmed or edited.
- Timer-slice acceptance: one working week tracked on the Mac, compared by the owner with his workbook for the same week.

## Pros and Cons of the Options

### 2. Duration-only entries

- Good — the simplest model; matches the workbook.
- Bad — no clock times: no day rail, no "moved the end by half an hour", no plan against actual, no detection of two timers.

### 3. Parallel timers

- Good — can express two things at once.
- Bad — a day can add up to more than 24 hours; every total needs a rule for overlaps; the owner's workbook already assumes one activity at a time.

### 4. Automatic tracking from app activity

- Good — nothing to start or stop.
- Bad — records what was on screen, not what the time was for; no line or task without rules to maintain; privacy-heavy; nothing for work away from the Mac.

### 5. An existing tracker app, imported

- Good — nothing to build; widgets and a watch app exist today.
- Bad — a third silo with its own names for lines and tasks; no nudges tied to MoonShine's budgets and plan; an import and a mapping to maintain, as with the workbook.

## More Information

- Not checked yet: whether a Live Activity started on the iPhone gives usable stop and pause controls on the watch without a watch app; how reliably iOS delivers a local notification scheduled from a calendar event when the app has not been opened that day.
- Follow-ups: idle detection while the Mac is awake; exporting a month in the workbook's layout; a login item so the Mac menu bar timer is always available; per-task actual against estimate in the forecast view.
