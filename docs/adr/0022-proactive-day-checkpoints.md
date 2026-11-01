---
title: "0022 — Proactive day checkpoints: facts at set times, few, decided by rules on the device"
status: proposed
date: 2026-11-01
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0011-change-driven-import-full-snapshots-on-omnifocus-deactivation]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[0017-reminders-native-entity-omnifocus-tag-bridge]]"
  - "[[0019-practice-lines-nested-lines-measured-by-entries]]"
  - "[[0020-period-quotas-n-times-per-week-or-month]]"
  - "[[0023-routine-template-adherence-progression]]"
---

# 0022 — Proactive day checkpoints: facts at set times, few, decided by rules on the device

## Context and Problem Statement

The owner learns in the evening where his day went (`design/README.md` § Draft-5 changes). Draft-5 answers this when he looks: Today so far on the rail and in the menu bar popover (`design/components.md` § DayBalance). He also wants to be told without looking (owner, 2026-10-30): "it is midday, and X and Y are not started".

His own time log sets the price of telling him:

- 41–50 activity switches in a 12-hour day, about 4 an hour;
- in 2025, a median awake interval of 22 minutes, with 34 % of intervals at 15 minutes or less.

A notification at a random moment usually lands in the middle of an activity, so each one is an interruption. MoonShine already notifies through one planner: the timer's nudges (ADR-0016), reminders (ADR-0017) and memo moments (ADR-0018). Each of those exists because the owner started or set something. A checkpoint would be the first notification MoonShine sends on its own initiative.

**How does MoonShine say, during the day and without being asked, what is still open, at the lowest cost in interruptions, in rule 8's tone, and in a form the assistant can build on later?**

## Decision Drivers

- **Interruptions cost.** Few notifications, each worth reading, landing between activities when possible; one notification carries everything due at that moment.
- **Tone** (CLAUDE.md rule 8): facts and distances, with no red and no "missed", "overdue" or "behind"; amber only for a deadline or a strong quota (ADR-0020). A share of work is a fact, never a verdict (`design/tone-glossary.md` § Time).
- **Deterministic and testable**: rules over stored facts, tested with a fake clock.
- **Private**: the first layer runs on the device and sends nothing anywhere; notification text follows the system's preview setting (ADR-0016 § Nudges, ADR-0017 § Notifications).
- **The owner stays in control**: each kind can be switched off; a daily limit; `Not today` and `Later` on every notification; plain counters, no learning.
- **Honest with partial or stale data**: "not started" is known only while the owner tracks; a fact from a failed or stale read is not a fact.
- **A path for the assistant**: the model proposes later as `confirm` commands (ADR-0013) and applies later still; nothing in the first layer depends on a model.
- **One planner, one `Notifier`** (ADR-0017).

## Considered Options

1. **Checkpoints at set times, decided by rules on the device, capped per day; the assistant proposes actions in a later layer and applies them in a third.**
2. **Notifications triggered by conditions**: one the moment a condition becomes true (a floor can no longer be reached in the day window, work passes a share of the tracked day, a Top 3 task is still untouched at a set hour).
3. **Pull only**: the same facts as a card on Today and in the popover, no notification.
4. **Model-written checkpoints from the start**: the assistant reads the day and writes the message (the second layer first).

Writing reminders or alerts into OmniFocus or a calendar is not an option before the Act phase (CLAUDE.md rule 6).

## Decision Outcome

**Proposed: option 1, with option 3 as its quiet half.** A card on the Today rail and in the popover always shows the current checkpoint items, computed live, so a held, dismissed or unseen notification loses nothing. Option 1 bounds interruptions by the clock and the cap, not by how often conditions change. It is testable, and it leaves the model out until the Ask phase.

**This ADR amends ADR-0017**: its notification planner gains a kind whose content is computed when it is sent, not scheduled ahead.

### Three layers

| Layer | When                                                                        | What it does                                                                                                                                                |
| ----- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1    | slice DC, inside phase 2, right after TM2, the notifier (owner, 2026-11-01) | Rules compare plan and fact at the checkpoint and send one notification with one or two items. No model.                                                    |
| L2    | phase 4, Ask                                                                | For a delivered checkpoint the assistant proposes one or two actions, each a `confirm` command (ADR-0013), shown on the card. Nothing is applied by itself. |
| L3    | phase 5, Act                                                                | Confirmed proposals that change OmniFocus are applied through the adapters (ADR-0013 § Execution).                                                          |

L1 is specified below; L2 and L3 get their specs in their phases. What L2 may send to the model is open question 3: the consent for cloud AI is required (ADR-0013 § Standing context), note bodies only from the allowlist (ADR-0013, amendment 2026-10-06), and titles are data that can never supply a target (ADR-0013 § Safety).

### The day

- **The day starts** at the day's wake boundary: Health's first (measured), else a dictated one (stated; ADR-0023 § Adherence, Health bridge H). Without a boundary, it starts at the end of the first Sleep entry that ends after local midnight, else at the day window's start. A nap later in the day never moves it. This is the "since" of `design/components.md` § DayBalance and ADR-0016's amendment of 2026-10-28, made exact.
- **The day ends**, for checkpoints, at the end of the day window. Every checkpoint not sent by then, held or waiting, **expires**. After the window a floor not reached is nothing at all (`design/tone-glossary.md` § Time).

### When

- **Checkpoint times:** a list of up to three local times; default 13:00 and 16:00 (open question 1). A checkpoint less than 3 h after the day's start moves to the day's start + 3 h. If that is at or after the next checkpoint, the two merge into one.
- **Precedence while sessions run**, first match wins:
  1. **During focus** (a running session on a line, a project or a task: work the owner chose to time) the checkpoint is held. It is sent at that session's next stop or pause, or merged into the next checkpoint if that comes first.
  2. **With only Life ops sessions running**, it waits up to 20 minutes for the next start, stop or pause of any session, then is sent anyway.
  3. **With nothing running**, it is sent at once.
     Interruption studies find that a break between activities is a cheaper moment to interrupt than the middle of one. Whether checkpoints land on switches is counted in the acceptance week, not assumed.
- **Fresh facts.** A checkpoint due while OmniFocus is frontmost waits until it resigns active and the import that follows ends (ADR-0011 never imports while OmniFocus is frontmost). A kind whose source read failed or was only partly read is not offered: for a quota that is the partly-read state of ADR-0020 § Counting; for tasks, a failed last import.
- **Computed when sent, never in advance**: a notification scheduled hours ahead would carry stale facts. The Mac app evaluates the rules itself; it runs as a login item from the slice that brings the `Notifier` (ADR-0017 § Notifications). After a sleep or a launch, a checkpoint that is due and not expired is evaluated then. With the app not running, there is no checkpoint; Settings says so.

### What counts (open question 2)

| Kind               | Counts when                                                                                                                                                                  | Fact, as written (invented)                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `deadlineDue`      | an open task with a deadline under the deadline rule (`docs/specs/phase-1-see.md` § Global), due today or earlier, as Today places it (`docs/specs/phase-1-see.md:11`)       | `Due 17:00 · Submit workshop abstract`, `Due Wed 18:00 · …` (amber) |
| `quotaTime`        | a quota task in its "time" state, read in full (ADR-0020 § Showing it)                                                                                                       | `time · 1 of 2 · by Sun · Long run` (amber when strong)             |
| `top3NotStarted`   | a Top 3 task (`docs/specs/phase-1-see.md:11`), not completed, with no time entry and no session on it today                                                                  | `Top 3 · not started yet: Eval harness`                             |
| `floorOpen`        | a line that is not paused, not nested and not measured by entries (ADR-0019: their time goes elsewhere), with `floor_h_day`, whose tracked time today is below its floor     | `🧘 Core practice · 2 h 10 min to the floor`                        |
| `routineBlockOpen` | a block of today's routine template (ADR-0023): flexible, protected, or an anchor on a line; its window not yet ended, and not held yet (P2-R2)                              | `🎻 Violin · 20 of 45 min · 17:00–21:00`                            |
| `workShare`        | the work lines (`design/screens/timer-mac.md` § Work lines) took more than the share **the owner set** of the time by the clock since the day started; off until he sets one | `Since 06:40 · work 5 h 24 min of 8 h by the clock`                 |

- **Tracking gate:** `top3NotStarted`, `floorOpen`, `routineBlockOpen` and `workShare` are offered only on a day with at least one entry or session that is not Life ops since the day started. A logged night of Sleep does not make "not started" true. A Health workout counts.
- **One item per task or line:** a task that is both a deadline and a Top 3 task appears once, under the kind that comes first in the order below. A line that is both `floorOpen` and `routineBlockOpen` appears once too, as `floorOpen`.
- **One or two items per notification**, in this order: `deadlineDue`, a strong `quotaTime`, `top3NotStarted`, `floorOpen` (foundation lines first), `routineBlockOpen`, a neutral `quotaTime`, `workShare`. The rest reads `+3 more on Today`. A checkpoint with no item sends nothing and does not count.
- Wording follows the rail's: facts and distances, never a shortfall; hours only from real time data or numbers the owner set (rule 8).
- A kind whose data does not exist yet is not offered. DC ships with `deadlineDue`, `top3NotStarted` and `floorOpen`. The others join later:
  - `routineBlockOpen` from P2-R2, only on a day with a routine template, and not while today's routine version is partial (ADR-0023);
  - `workShare` from TM3's work lines, once a share is set;
  - `quotaTime` from the Quotas slice.

### How many (open question 4)

- At most **3 checkpoint notifications a day** by default (0 turns them off), counting each `Later` delivery and each split delivery below. **The limit is hard**: once reached, nothing more is sent that day, a deadline included. Today keeps showing it in amber, and OmniFocus keeps its own due notifications.
- The limit covers checkpoints only. Nudges, reminders and memo moments follow what the owner started or set, and keep their own rules.

### Focus and a deadline

A held checkpoint that has a `deadlineDue` item sends that item alone at once, as one notification that counts. The rest stays held as above and counts again when it is sent.

### Actions on the notification

- **`Not today`**: every kind in that checkpoint, those behind `+N more` included, stays silent until local midnight.
- **`Later`**: one retry 60 minutes later, inside the day window, computed again then. The next checkpoint would come anyway; `Later` is what brings the items back sooner.
- **Opening it** shows Today with the card.
- **A kind dismissed 3 days running** (`Not today`, or the notification cleared without opening, on three consecutive local days) gets one question **inside the app**, never a notification: a quiet row on the Today rail, `Turn off "Top 3 not started" checkpoints?` · `Turn off` · `Keep`. `Keep`, or a day on which that kind was sent and not dismissed, resets the count. A day on which it was not sent leaves the count as it is. Plain counters, nothing learned or weighted.

### Where it runs and what it stores

- **On the Mac only** in phase 2; the iPhone after 3b, with its own planner (ADR-0017 § Notifications). Mac first, because only the Mac app runs all day as a login item.
- **On the device only.** L1's rules are a pure function of a `DayFacts` value: Top 3, deadlines, quotas with their read state, floors, today's routine blocks (P2-R2), today's entries, sessions and boundaries, the work lines and share, the read state of the last import, and the clock. They take no port. From LT3 on, a CI check allows the network API in the AI adapter target only (`docs/specs/phase-2-plan.md`, LT3), so a checkpoint cannot reach the network without failing CI.
- **Stored**, as native records keyed by (local day, kind), so they can sync from 3b (open question 4): the settings (times, kinds, the share, the limit), and per day the checkpoints sent (time, kinds, the items by MoonShine id, never a title), the held one, the kinds silenced and the dismissal counters. Logs carry kinds and counts only (rule 5).

### Consequences

- Good — at most three interruptions a day by default, each with one or two facts, landing after a session ends when one runs.
- Good — deterministic rules with fake-clock tests; nothing leaves the Mac.
- Good — dismissing loses nothing: the card on Today keeps the items, computed live.
- Good — L2 and L3 reuse ADR-0013's classes, and L1 keeps item ids, so neither changes L1.
- Bad — no checkpoint when the app is not running, or once the day window has ended.
- Bad — "not started", floors and the work share need tracking. On a day without it, a checkpoint can report only deadlines and quotas.
- Bad — a long focus session can hold a checkpoint until it ends or the window closes; the deadline item is the only exception.
- Bad — a fourth source of notifications beside nudges, reminders and memos; the daily limit does not cover them.
- Bad — new native state and one more Settings section.
- Neutral — ADR-0016's day mark (`Today's 4 h are in`) is the reached side of `floorOpen`.

### Confirmation

- **Core tests with a fake clock** on an invented day:
  - at 13:00 with four open items: one notification with the first two by the order above and `+2 more on Today`; with no items: nothing, and the count stays;
  - a task that is a deadline and a Top 3 task appears once, as `deadlineDue`; a deadline from yesterday counts with its day in the text;
  - `routineBlockOpen`:
    - a flexible block at 20 of 45 min with its window ahead → one item;
    - a bed anchor → none;
    - a block with no data → none;
    - a day without a routine template → none; today's version partial → none;
    - a line that is also `floorOpen` → one item, as `floorOpen`;
  - a fourth checkpoint on a day with the limit 3 is not sent, a deadline included; a `Later` delivery and a split deadline delivery each count;
  - `Not today` silences every kind of that checkpoint, hidden ones included, until local midnight, on a daylight-saving day too;
  - precedence: a focus session from 12:30 to 15:30 holds the 13:00 checkpoint until 15:30; with only a Life ops session running, it is sent at the next switch or at 13:20; with nothing running, at 13:00; the inputs of the three tests are disjoint;
  - a held or waiting checkpoint expires at the end of the day window; a wake at 23:40 sends nothing;
  - a checkpoint due while OmniFocus is frontmost waits for the resign and the import; a quota partly read is not offered;
  - a day that starts at 11:00 moves the 13:00 checkpoint to 14:00; one that starts at 14:00 merges 13:00 and 16:00 at 17:00;
  - a nap logged as Sleep at 14:00 does not move the day's start; a Health wake at 06:41 and a dictated one at 06:50 start the day at 06:41;
  - a day with only Sleep entries offers neither `top3NotStarted` nor `floorOpen`; a paused, nested or entries line never gives `floorOpen`;
  - `workShare` uses time by the clock: two parallel work sessions 10:00–11:00 count 1 h, not 2;
  - three consecutive days dismissed raise the in-app question once; a sent and not dismissed day resets the count; a day not sent leaves it;
  - the same day gives the same result in any process time zone (the workspace zone is used).
- **Tone check:** no red; amber only on `deadlineDue` and a strong `quotaTime`; none of "missed", "overdue", "behind", "failed" in English or Russian (`scripts/check-catalog.mjs`); no "only", "just", "already" / «всего», «уже» next to Work (`design/tone-glossary.md` § Time).
- **Privacy:** the rules take no port; the CI network rule of LT3; logs and problem texts carry kinds and counts only; stored items are ids, never titles.
- **Owner acceptance:** one working week with checkpoints on. Per day, counts only, into the method log: sent, sent at a switch, sent at the 20-minute cap, held by focus, expired, `Not today`, `Later`, opened. The ADR becomes `accepted` after that week, with the defaults the week supports.

## Pros and Cons of the Options

### 1. Checkpoints at set times, by rules

- Good — the number of interruptions is set by the owner, not by his day.
- Good — every fact is computed, testable and explainable.
- Bad — a fixed time ignores what the owner is doing; the focus hold and the wait for a switch only soften it.
- Bad — a condition that becomes true just after a checkpoint waits for the next one.

### 2. Notifications triggered by conditions

- Good — a fact arrives when it becomes true.
- Bad — the number of notifications follows the day's events, not a cap; on a day of 40–50 switches, conditions flip often, and a cap would cut at random which facts get through.
- Bad — "can no longer be reached" needs a prediction of the rest of the day, which is the forecast's job and uncertain.

### 3. Pull only

- Good — no interruption at all; the rail and the popover already show the day (draft-5).
- Bad — it does not answer the brief: on a day he does not open MoonShine, he sees nothing, and that is the day the evening surprise happens.
- Kept as the quiet half of option 1.

### 4. Model-written checkpoints from the start

- Good — natural sentences, and judgement about what matters today.
- Bad — needs the Ask phase, a network call per checkpoint, and the owner's data leaving the device several times a day.
- Bad — not deterministic: the same day can give different messages; tests can only sample.
- Bad — the model would decide what interrupts the owner; ADR-0013 keeps the model to proposals the owner confirms.

## More Information

- The owner's facts above come from his own log, as counts only (rule 5).
- Background on interrupting at a break: Adamczyk and Bailey, "If not now, when? The effects of interruption at different moments within task execution", CHI 2004; Iqbal and Bailey, "Effects of intelligent notification management on users and their tasks", CHI 2008.
- Not checked yet:
  - whether macOS delivers a notification from a login-item app over a full-screen app the same way;
  - whether a custom dismiss action (`UNNotificationCategoryOptions.customDismissAction`) reports a notification cleared from Notification Center on macOS;
  - whether a time-sensitive interruption level for `deadlineDue` needs an entitlement that a free development identity can have (L1 uses the default level).
- This ADR lands with the phase-2 spec's PR, with its row in `docs/adr/README.md` and the DC row in `docs/ROADMAP.md`.
- Questions for the owner (`docs/specs/phase-2-plan.md`, questions 3–6), decided as proposed (owner, 2026-11-02):
  1. Fixed times (13:00, 16:00), or times relative to the day's start? Proposed: fixed, with a checkpoint moved to the day's start + 3 h on a late day.
  2. Which kinds count? Proposed: all six, each with its own switch; `workShare` only once the owner sets its share.
  3. What may L2 send to the model? Proposed: only the facts of the delivered notification and the line names, under the consent for cloud AI; no task notes, no entries, no calendar.
  4. The daily limit, and across devices? Proposed: 3, settable from 0 to 3; from 3b, one limit and one `Not today` for the owner across his devices (records keyed by day and kind, synced under ADR-0010).
