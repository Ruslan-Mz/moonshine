---
title: "0016 — Time tracking: one running timer, interval entries, nudges as facts, Excel reconciled by day and line (amended 2026-10-16: up to three timers)"
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

# 0016 — Time tracking: one running timer, interval entries, nudges as facts, Excel reconciled by day and line (amended 2026-10-16: up to three timers)

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

**Chosen option: "1"**, together with option 3 since 2026-10-16 (§ Up to three running timers), because intervals on the clock give the forecast exact evidence, put actual time on the same day axis as the calendar and the plan, make corrections simple, and let two sources be compared instead of summed.

**This ADR amends ADR-0013** (timer commands join the `auto` class), **ADR-0012** (what a confirmed calendar entry and a timer target keep of an event, below) and the Excel import contract (the workbook is no longer "the source of truth until the quick log exists").

### Records

- **`TimerSession`** (native, synced under ADR-0010): subject, started at, state (`running` · `paused` · `stopped`), the device it was started on, an optional target (a duration or a clock time; a target taken from an event is only a duration).
- **`TimeEntry`** gains fields: `day` (the local calendar date it belongs to), optional `start` and `end` (instants) with the time zone at capture, `minutes`, the subject, `source`, `session`, `edited`.
  - **Subject:** a line (or Life ops, when the task maps to no line), and optionally a project, a task or a plan step. The line is stored on the entry at capture, so a later change of mapping does not rewrite history; re-attributing is an explicit command.
  - **Source:** `timer` · `manual` · `excel` · `calendar` (confirmed by the owner from an ended event) · `omnifocusEstimate` (derived).
- **Calendar entries** (owner, 2026-10-09; amends ADR-0012). A time entry the owner confirms from an event keeps the event's start, end and line, never its title, attendees, id or calendar name. A timer target taken from an event is only a duration. These are the only event-derived values besides ADR-0012's busy minutes that leave the device.
- **Life ops categories** (amendment 2026-10-28, owner; design draft-5). An entry or a session whose subject is Life ops carries `lifeCategory`, stored at capture like the line, so renaming a category later does not rewrite history. The categories are native data, edited in Settings → Time: eight defaults (Sleep, Food, Cooking, Hygiene, House, Transport, Errands, Inbox), renamed, reordered, added or archived by the owner. Sleep is built in (it can be renamed, not removed): the end of the night's Sleep interval is where "today so far" starts; without one, the day window's start. A category never has a budget, a floor, a portion or a day mark, and is never a line.
- **Intervals are the atoms.** Pause closes an interval and resume opens the next one in the same session; each interval is one entry. An interval that crosses local midnight is split in two at stop. A workbook entry has a day and minutes and no clock times.

**Amendment (2026-11-01, owner; `docs/specs/phase-2-plan.md`, questions 9–11 and 17).**

- **Two new sources.** `dictation` (stated, like `manual`): entries the owner confirms from Log by text. `health` (measured): workouts from the Health bridge, slice H, until HealthKit replaces it in 3b. § Two sources counts `dictation` with the native entries.
- **How Health minutes count.** A Health entry counts only outside the union of the owner's own clock intervals that day, whatever their unit. Against his own minutes-only capture of the same unit, the larger counts, never the sum. Against the workbook, § Two sources applies, with Health on the native side.
- **Wake and bed are day boundaries**, a native record of their own (wake or bed, the instant, the stored day, the source). Health's main sleep comes first (measured), then a dictated wake or bed (stated), then a Sleep entry with clock times. A dictated boundary more than 15 minutes from Health's is marked, the mark computed when read and never stored; neither is deleted. Of two dictated wakes (or beds) on one day, the one confirmed most recently is used; the earlier one stays stored and comes back through undo (owner, 2026-11-04; `DayBoundaries.resolve`, spec slice LT2b). One Core function sets every boundary's day: a bed before 06:00 belongs to the day before. The day's wake boundary is where "today so far" starts (§ Records, Life ops categories); without one, the end of the night's Sleep interval, else the day window's start.
- **The fields arrive with the slices that fill them:** `TimeEntry` from X2 with day, clock times, minutes, subject, source and `edited`; `session` with the timer (TM1), `step` with plans in the store (F2).

### Up to three running timers

**Amendment (2026-10-16, owner).** This section was "One running timer": _"Starting a timer stops the one that is running, at that instant. The same rule merges sessions started on two devices without a network: ordered by start time, a session still running when a later one starts ends at that later start. Every device computes the same result."_ The owner does two things at once and both are real: violin scales during the part of a meeting where he only listens, Anki vocabulary on a commute. Splitting the time would say he did half of each, which is false; refusing it would lose one of them. The data model already allows it: every interval has clock times, so overlap is computed, not stored.

- **Up to three sessions may run at the same time.** Each is its own `TimerSession` with its own intervals, pauses and nudges.
- **A plain start switches and never blocks** (owner, 2026-10-17). It stops **every** running session at that instant and starts the new one; a quiet, non-modal notice shows for about eight seconds: "🎻 stopped · Keep running". `Keep running` resumes the stopped sessions from the instant they stopped, so there is no gap (it undoes the stops), within the cap of three.
- **Starting alongside**: ⌥-click, `Start alongside` in ⌘K, and the word "alongside" / «параллельно» by voice. It stops nothing while fewer than three run.
- **At three running sessions** (owner, 2026-10-17) a start cannot keep them all: an alongside start stops the oldest, a plain start stops all three, and the notice reads "🎻 stopped (three at most)" with no button.
- **Offline merge across devices:** sessions are kept as they are while at most three overlap; when a fourth overlaps, the one that started first ends at the later start. Every device computes the same result.
- A running session survives the app being closed (the start time is stored).
- **Undo on the notice** (amendment 2026-10-28, owner). Undo of a start is the undo of `StartTimer` that ADR-0013 requires of every command: the new session is removed and the sessions it stopped resume from the instant they stopped, with no gap. On the iPhone the switch notice carries it as a button for about eight seconds, next to `Keep running` ("🎻 stopped · Keep running · Undo"); on the Mac it is ⌘Z. With three running, both "three at most" notices offer only the undo. After the notice, a wrong interval is corrected with `EditTimeEntry` (the Day list's `Change`).

How time is counted:

| What                                                                   | Counted as                                                                                                                                                                                                                        |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A line's, project's or task's hours (week table, reviews, forecast)    | The full duration of its own entries                                                                                                                                                                                              |
| The day's clock time (Today rail, free time, day load, Board capacity) | The union of all intervals: overlapping time counts once; a day never exceeds 24 h                                                                                                                                                |
| Shown                                                                  | "Tracked 26 h · by the clock 23 h · in parallel 3 h"; in reviews each line carries "in parallel 30 min"                                                                                                                           |
| "In parallel" (owner, 2026-10-17)                                      | For the day: tracked minus by the clock. For a line: the part of its own time during which at least one other session ran                                                                                                         |
| Break nudge                                                            | Continuous activity of the union, not each session separately: fires once per mark, after N minutes, where N is the smallest among the running sessions' lines; on the device of the earliest running session (owner, 2026-10-17) |
| Check mark of a forgotten timer                                        | Per session, by its own line's limit (owner, 2026-10-17)                                                                                                                                                                          |
| Reconcile with the workbook (unit: day and line)                       | Unchanged: per line                                                                                                                                                                                                               |
| Forecast evidence                                                      | Weight 1 for now; overlap is derivable, so a weight can be added later without a migration                                                                                                                                        |

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

**Amendment (2026-10-19, owner; ADR-0019).** Time attributed to a nested line (a line with `within`) is recorded on its parent, from every source: timer, task, calendar, manual and workbook. The timer's line picker, the quick log and voice `LogTime` do not offer nested lines; a workbook row mapped to a nested line is recorded on its parent with the info problem `excelRowMovedToParent`, so the reconcile by (day, line) pairs it with the parent's entries.

### Voice

`StartTimer`, `PauseTimer`, `ResumeTimer` and `StopTimer` are `auto` commands (ADR-0013): native, undoable, answered in one line. The conditions of ADR-0013 hold: the subject and any time offset are spans of the utterance, and the app resolves the subject itself (exactly one line, project or open task). No match or several matches → one question, never a guess. `EditTimeEntry` by voice is `auto` only for the entry just stopped; anything else is a proposal.

### The day by the clock

- **Today** shows tracked intervals on the day rail next to calendar events and planned tasks: plan against actual on one axis. Interval edges can be moved; a gap can be filled with a manual entry.
- **A week table**: lines by days, in minutes, with a drill-down to projects and tasks. It reads like the workbook's grid.
- Weekly, quarterly and yearly views read the same entries. The facts placeholder of ADR-0015 puts the day's or week's hours into a journal note; entries themselves are never written to the vault.

### Nudges

A nudge is a local notification on the device where the session was started (for the break nudge, while sessions overlap, the device of the earliest running session; § Up to three running timers), and a quiet state everywhere else. Each kind can be switched off; none is repeated for the same mark.

| Kind                | Fires when                                                                                                                                   | Wording, as a fact         |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| Break nudge         | every N minutes of continuous activity (N per line, default 50; with several sessions running, the smallest N of their lines; on by default) | `🎻 50 min · short break?` |
| Session target      | the target set at start is reached                                                                                                           | `🎻 2 h reached`           |
| Day mark            | today's tracked time on a line reaches its floor or its portion                                                                              | `Today's 4 h are in`       |
| Calendar suggestion | five minutes before an event in a line-mapped calendar: an offer to start a timer on that line, with the event's length as the target        | `🏃 17:00 · Start timer?`  |

- **Day mark.** The _floor_ is the line's `floor_h_day`. The _portion_ is the sum of today's events in the line's calendar, else the line's optional `portion_h_day` in the budget note. A line with neither has no day mark. From the Board phase a project's portion comes from the plan. Hours may be shown next to the portion: CLAUDE.md rule 8 names `portion_h_day` and the length of events in a line's calendar (owner, 2026-10-08).
- The calendar suggestion reads events on the device, as every calendar feature does (ADR-0012); nothing about the event is stored except, once the owner starts the timer, the target's duration (§ Records). It needs the app to have run that day, so it is best effort.
- On a locked screen, notification text follows the system's preview setting for MoonShine on every platform; MoonShine has no setting of its own for notifications (owner, 2026-10-17).
- **Break nudge.** Its two actions are `Break` and `Keep going`. `Break` pauses every running session, so the break is not counted, and one nudge to resume follows after the break length (default 5 minutes); resuming resumes all of them (amendment 2026-10-16). Without an answer the timers keep running.
- No streaks. A day mark is never shown as missed.
- **Per-line values** (amendment 2026-10-28, owner). A line's break-nudge N and its check-mark limit come from the optional budget-note keys `break_after_min` and `check_after_h` (vault contract v0.6, § 1); without them the defaults in Settings → Time apply (50 min, 4 h). A Life ops category sets its own values in Settings → Time; Sleep has no break nudge and a 12 h check limit by default.
- **Amendment (2026-10-16, ADR-0017).** Nudges are scheduled by the one notification planner in Core that also schedules reminders; a running timer's nudges rank first within the 64 pending notifications iOS allows. The planner and the `Notifier` arrive with whichever of the Timer slice or the Reminders slice ships first. The break nudge was called "Break reminder" until then; it is renamed so that "reminder" names only ADR-0017's entity.

### A forgotten timer is visible (owner decision, 2026-10-07)

- A running session is always in sight: elapsed time in the Mac menu bar, a growing block on the Today rail, the Live Activity and widgets on the phone.
- A session gets a **check** mark when it has run longer than its own line's limit without a pause (default 4 hours; each running session separately), or when the Mac slept while it ran. The mark shows on the menu bar item and on the resulting entry.
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

| Phase    | Change                                                                                                                                                                                                                                                                       |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2 Plan   | `TimeEntry` gets the new fields from its first slice; the import and the quick log use them. The reconcile rule is part of the import.                                                                                                                                       |
| 2 Plan   | **Timer (Mac)** is the last slice: sessions (up to three at once), the notification planner and the `Notifier` if it ships before the Reminders slice (ADR-0017), menu bar, start from a row and from ⌘K, the day rail with editing, the week table, nudges, the check mark. |
| 3b       | The iPhone timer takes a task or a project as well as a line; buttons in widgets and controls; Siri.                                                                                                                                                                         |
| Ask      | Start, stop and corrections through the assistant.                                                                                                                                                                                                                           |
| After 3b | Watch; standalone countdown timers that belong to nothing.                                                                                                                                                                                                                   |

**Amendment (2026-10-09, owner).** The fallback is removed: it said that if the other phase-2 slices were not merged by 2026-12-07, Timer (Mac) would move to directly after R1. It existed only to protect R1's deadline (2026-12-28). R1 is now built in the two-week usage period after phase 1 (`docs/ROADMAP.md`, rule of gates), so that deadline has a margin of weeks, and Timer (Mac) stays the last slice of phase 2.

**Amendment (2026-10-28, owner; design draft-5).** The two-sources choice (§ Two sources: the cell mark, the four choices, the reconcile list) is its own slice, **Time reconcile**, right after Timer (Mac) (`docs/ROADMAP.md`). Until it ships, the import's rule holds: the native entries are counted and the pairs stay open. Whether a minimal iPhone capture (Lock Screen widgets and controls, the Live Activity) comes before 3b is decided at phase-2 planning; its prerequisites are CloudKit sync of native records (ADR-0010) and the paid Apple Developer Program.

**Amendment (2026-11-01, owner; `docs/specs/phase-2-plan.md`).** Timer (Mac) is no longer the last slice of phase 2. Time capture comes first: `TimeEntry` (X2), Log by text (LT1–LT4), then the sessions, the notifier and the menu bar (TM1–TM3) early, and the Today time lane, the Day view and Settings → Time (TM4–TM6) after the workbook. Time reconcile stays right after the phase. No minimal iPhone capture comes before 3b. `manual` (the quick log) and `calendar` (an entry confirmed from an ended event) stay reserved source values and are not built in phase 2, nor the calendar-based nudges and the day portion from a line's calendar, which need the calendar's line mapping cut in phase 1; Log by text replaces the quick log in phase 2.

### Consequences

- Good — exact hours with one action; the forecast gets actual against estimate per task and per line.
- Good — plan against actual on one day axis; corrections are edits with a trace and undo.
- Good — start on one device and stop on another; no AI needed for voice through Siri.
- Good — the workbook keeps working, and no hour is counted twice.
- Bad — keeping both sources means a reconcile list to work through; while a day is undecided its total may be too low.
- Bad — two kinds of daily total (tracked and by the clock) must both be labelled wherever a day total appears (amendment 2026-10-16).
- Bad — a forgotten session is marked, not stopped: its entry stays wrong until the owner confirms or trims it.
- Bad — the calendar suggestion and the nudges depend on notifications the system may delay, and on the app having run.
- Bad — phase 2 grows by a slice. R1's fixed date no longer depends on it: R1 is built before phase 2 (amendment 2026-10-09).
- Bad — the line stored on an entry can disagree with a later mapping; re-attribution is manual.
- Neutral — the screen spec's "no streaks or goals in the log" becomes "no streaks; targets and day marks are optional, neutral facts".

### Confirmation

- Core tests: a plain start stops every running session, and `Keep running` restores them without a gap; ⌥-start runs both; with three running, an alongside start stops the oldest, a plain start stops all three, and neither offers `Keep running`; offline sessions with four overlaps merge to the same result on every device; a day's clock time never exceeds 24 h while its tracked time may; each line's hours count its own entries in full; three sessions each running 10:00–11:00 give tracked 3 h, by the clock 1 h, in parallel 2 h for the day and 1 h for each line (amendment 2026-10-16); pause and resume give separate intervals; an interval across midnight is split; a daylight-saving change and a time-zone change keep the minutes right; an edit that would overlap a neighbour is refused until the owner chooses; every command can be undone.
- Reconcile tests: totals within the tolerance list nothing and resolve as "the same session", and reopening that pair from the day view offers all four choices; a smaller workbook total offers only keep MoonShine and keep the workbook, and keeping the workbook marks the native entries as not counted without deleting any; no choice creates a negative entry; beyond it the pair is listed, the native entries are counted and the two are never summed; each choice gives the stated result; a re-import does not reopen a decided pair unless the workbook's value changed; a derived entry is not counted next to a measured or stated one.
- Assistant tests (the Ask phase): a subject with two matches never starts a timer; a time offset that is not in the utterance is never applied.
- Nudge tests with a fake clock: each kind fires once per mark; none fires on a device that did not start the session; with overlapping sessions the break nudge uses the smallest N and fires once, on the device of the earliest running session; a line without a floor or a portion has no day mark; `Break` pauses every running session, resuming resumes all of them, and the resume nudge fires once.
- Calendar tests: an entry confirmed from an event stores its start, end and line and no title, attendee, id or calendar name; a timer target from an event stores only a duration.
- Check-mark tests: a session past its own line's limit (each overlapping session checked separately), or one that spans Mac sleep, is marked; nothing is trimmed without the owner's choice; a marked entry stays marked until it is confirmed or edited.
- Timer-slice acceptance: one working week tracked on the Mac, compared by the owner with his workbook for the same week.

## Pros and Cons of the Options

### 2. Duration-only entries

- Good — the simplest model; matches the workbook.
- Bad — no clock times: no day rail, no "moved the end by half an hour", no plan against actual, no detection of two timers.

### 3. Parallel timers

Chosen together with option 1 since 2026-10-16 (§ Up to three running timers).

- Good — can express two things at once.
- Bad — every day total needs the union rule of § Up to three running timers.

### 4. Automatic tracking from app activity

- Good — nothing to start or stop.
- Bad — records what was on screen, not what the time was for; no line or task without rules to maintain; privacy-heavy; nothing for work away from the Mac.

### 5. An existing tracker app, imported

- Good — nothing to build; widgets and a watch app exist today.
- Bad — a third silo with its own names for lines and tasks; no nudges tied to MoonShine's budgets and plan; an import and a mapping to maintain, as with the workbook.

## More Information

- Not checked yet: whether a Live Activity started on the iPhone gives usable stop and pause controls on the watch without a watch app; how reliably iOS delivers a local notification scheduled from a calendar event when the app has not been opened that day.
- Follow-ups: idle detection while the Mac is awake; exporting a month in the workbook's layout; per-task actual against estimate in the forecast view. The login item that was a follow-up here is decided by ADR-0017 (owner, 2026-10-17): MoonShine runs as a login item from whichever of the Timer slice or the Reminders slice ships first.
