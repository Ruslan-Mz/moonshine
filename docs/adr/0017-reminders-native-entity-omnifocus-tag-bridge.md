---
title: "0017 — Reminders: a native entity that is seen, not done; an OmniFocus tag as the bridge"
status: proposed
date: 2026-10-16
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
---

# 0017 — Reminders: a native entity that is seen, not done; an OmniFocus tag as the bridge

## Context and Problem Statement

Some of the owner's OmniFocus "tasks" are not tasks. They are reminders: a line he wants to see when he opens the system, or a nudge at a set time ("every hour from 10 to 18 on weekdays"). Nothing is completed; he reads them and goes on. As tasks they distort what MoonShine counts (open tasks, rhythm, forecast load), and OmniFocus cannot express the schedules he wants. He also wants them on a dashboard: Today on the Mac, a desktop widget, and the first screen of the iPad. **Where do reminders live, how are they shown and notified, and how do today's OmniFocus reminders get there?**

## Decision Drivers

- A reminder has no "done". It is seen, snoozed or put away; it never becomes overdue.
- Flexible schedules: once; daily, weekdays or chosen days; every N hours inside a time window.
- Visible without asking: on Today and in widgets, on the Mac and later on the iPad.
- Usable now, before MoonShine has native writes and sync.
- UI tone (CLAUDE.md rule 8): no red, no "missed".
- One write path with undo (ADR-0013); one notification planner shared with the timer nudges (ADR-0016).

## Considered Options

1. **A native `Reminder` entity, with OmniFocus tasks carrying a tag as a read-only bridge until it exists.**
2. Only the OmniFocus tag: MoonShine shows tagged tasks apart and leaves notifications to OmniFocus.
3. Apple Reminders through EventKit.
4. Calendar events used as reminders.

## Decision Outcome

**Chosen option: "1"** (owner, 2026-10-16), because only a native entity has "seen" instead of "done" and the schedules the owner wants, while the tag bridge makes the existing reminders useful in phase 1 at almost no cost.

**This ADR amends ADR-0013** (the reminder commands join the native `auto` class) and **ADR-0016** (its nudges and these reminders share one notification planner).

### The bridge (phase 1, S4)

- OmniFocus tasks that carry the tag `напоминание` (the name is a setting) are **reminders**, not tasks: Today shows them in a **Reminders** strip, read-only, and they open in OmniFocus.
- **The strip's filter** (owner, 2026-10-17): tagged, not completed, not dropped, and available now (defer date absent or ≤ now). A repeating task shows only its current copy; completed copies are never shown.
- They are hidden from every task list and count (owner, 2026-10-17): Today's sections and totals, Line detail, Week, Month, rhythm and progress, the forecast, the Board's load. They are shown only in the strip. ⌘K still finds them, labelled "reminder". The trace still shows them under their project if they have one.
- Notifications stay with OmniFocus until the native entity exists.
- **The unit that is cut** (owner, 2026-10-17) is the whole bridge (the tag setting, the exclusion and the strip): it is the first thing cut from S4 if its timebox is at risk, and every acceptance line for it holds "unless cut".

### Records (native, synced under ADR-0010)

- **`Reminder`**: text (1–500 characters), an optional line or project, a **display** and a **schedule**, `notify` (on or off), an optional quiet window, an optional `snoozedUntil`, `archived`, and, when it was converted from a bridged task, an `ExternalRef` to that OmniFocus task (provider `omnifocus`; ARCHITECTURE § Identity) rather than a raw provider id.
  - **Display:** `pinned` — visible until archived; `scheduled` — visible from each occurrence until the owner marks it **seen** or the next occurrence comes.
  - **Schedule:** once at a time; daily, weekdays or chosen weekdays at a time; every N hours (N = 1…12) inside a window (e.g. 10:00–18:00) on daily, weekdays or chosen weekdays.
  - **Snooze:** `snoozedUntil` is stored on the reminder and synced. `SnoozeReminder(until)` requires now < `until` ≤ now + 7 days; any other value is refused. While snoozed, the reminder is not shown and the planner schedules none of its notifications before `until`; at `until` it shows again and, with `notify` on, gets one notification. A seen, archived or edited reminder clears the snooze.
- **`ReminderSeen`**: the occurrence marked seen, with the device and the time. Seen on one device is seen everywhere after sync.

### Commands

All go through the `CommandBus`, land in the activity log and can be undone: `CreateReminder`, `EditReminder`, `MarkReminderSeen`, `SnoozeReminder(until)`, `ArchiveReminder`, `ConvertTaskToReminder(task)`. All are native `auto` commands (ADR-0013). By voice (the Ask phase) `CreateReminder` is `auto` only when the text and the whole schedule are spans of the utterance and parse to exactly one schedule; otherwise it is a proposal.

- `ConvertTaskToReminder` creates the native reminder and hides the bridged task from the strip. Removing the task from OmniFocus is a provider write: until the Act phase the owner deletes it in OmniFocus himself.

### Notifications

- One **notification planner** in Core decides what to schedule; a per-device adapter (the `Notifier` port) schedules local notifications. It also schedules ADR-0016's nudges. The planner and the `Notifier` arrive with whichever of the Timer slice or the Reminders slice ships first.
- **On the Mac** (owner, 2026-10-17): a recurring reminder is scheduled as repeating calendar triggers (one per weekday and time of its schedule), which macOS fires with the app closed; one-off notifications (a reminder at a single time, the end of a snooze, nudges) are scheduled as they come. MoonShine runs as a login item. The planner refills on launch, on wake and whenever a reminder changes; the Mac has no background refresh.
- **On the iPad and iPhone** (3b): the planner schedules the next 24 hours and refills on launch, on wake, on background refresh and whenever a reminder changes. iOS keeps at most 64 pending notifications per app, so the planner ranks: a running timer's nudges first, then reminders by time; what does not fit is scheduled at the next refill. A reminder whose triggers do not fit in that budget is marked "notifications limited on this device" in its editor.
- A reminder marked seen or archived on one device removes its pending notifications on the others when the change arrives. Until then the other device may still show it once; this is best effort and stated in Settings.
- Wording is a fact (`🎻 Scales · 10:00`), never "missed". On a locked screen, notification text follows the system's preview setting for MoonShine on every platform; MoonShine has no setting of its own for it (owner, 2026-10-17).

### Where reminders are shown

| Place                                         | From                                       |
| --------------------------------------------- | ------------------------------------------ |
| Today on the Mac: the Reminders strip         | S4 (bridge); native in the Reminders slice |
| Mac desktop widget: reminders now, next tasks | the Reminders slice                        |
| iPad home screen widget, iPhone widget        | 3b                                         |
| The assistant: "remind me every hour…"        | the Ask phase                              |

### Roadmap

| Phase / slice                              | Change                                                                                                                                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 See, S4                                  | The tag bridge and the Reminders strip on Today; excluded from task counts.                                                                                                                |
| **Reminders (Mac)**, after phase 2 and Hub | The native entity, commands, the notification planner and the `Notifier` (unless the Timer slice brought them), the Mac widget and its snapshot, the Mac widget, converting bridged tasks. |
| 3b                                         | Reminders on the iPad and iPhone, their notifications, the iPad home screen widget.                                                                                                        |
| Ask                                        | Creating reminders by voice.                                                                                                                                                               |

### Widgets (owner, 2026-10-17)

- The widgets cannot read the store, so the app writes a small **widget snapshot** into an App Group container: the current reminders and a few next tasks, exactly what the widgets show. It holds data from MoonShine's store only, never event titles (events are never stored, ADR-0012), and the app rewrites it whenever its content changes.
- Reminder text in widgets is privacy-sensitive: on a locked screen, in StandBy and on a locked device it is redacted like task titles (`.privacySensitive()`; `design/screens/iphone-widgets.md` § Privacy on the Lock Screen).

### Consequences

- Good — reminders stop counting as tasks from phase 1; forecasts and rhythm get cleaner.
- Good — the schedules the owner wants, with "seen" instead of "done".
- Good — one planner for reminders and nudges keeps the 64-notification limit under control.
- Bad — until the Reminders slice, bridged reminders notify only through OmniFocus, with its schedules.
- Bad — a converted task lives in two places until the owner deletes it in OmniFocus (before the Act phase).
- Bad — "seen on one device" reaches the others only after sync; a notification may show once more.
- Bad — the widget snapshot is a second copy of some real data, outside the store.
- Bad — on the iPad and iPhone a reminder with many triggers can exceed the 64-notification budget; its editor says so.
- Neutral — the dashboard is Today plus widgets; no separate dashboard screen.

### Confirmation

- Bridge tests: a task with the tag is in the strip and in no task list, count, statistic, forecast or load; a completed, dropped or deferred tagged task, or a completed copy of a repeating one, is not in the strip; ⌘K finds a tagged task labelled "reminder"; renaming the tag in Settings moves the set.
- Schedule tests with a fake clock: each schedule kind gives the right occurrences across a week, a daylight-saving change and a time-zone change; "every N hours in a window" never fires outside the window.
- Planner tests: on the iPad and iPhone never more than 64 pending, the timer's nudges win over reminders and refill schedules what was cut, and a reminder that does not fit is marked limited; on the Mac a recurring reminder becomes repeating calendar triggers; a snoozed reminder has no notification before `until` and one at `until`; `until` ≤ now or > now + 7 days is refused.
- Seen tests: seen on one device hides the occurrence everywhere after sync and removes its pending notifications.
- Command tests: every command can be undone; a voice schedule that does not parse to exactly one schedule is a proposal.

## Pros and Cons of the Options

### 2. Only the OmniFocus tag

- Good — nothing new to store.
- Bad — reminders stay completable tasks; no window schedules; no notifications of MoonShine's own.

### 3. Apple Reminders

- Good — notifications and sync for free.
- Bad — reminders there are tasks with a checkbox; no "every N hours in a window"; a third place for the same kind of item.

### 4. Calendar events

- Good — already read (ADR-0012).
- Bad — events take time on the day rail and in the busy minutes; reminders take none.

## More Information

- Not checked yet: whether macOS limits the number of pending notification requests per app; how often iPadOS refreshes a home screen widget that shows time-dependent reminders; whether background refresh on the iPad is frequent enough for the planner's refill.
