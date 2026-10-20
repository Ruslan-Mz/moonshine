---
title: "0018 — Memos: notes bound by rules to events and tasks, shown before and after"
status: accepted
date: 2026-10-19
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0012-calendar-eventkit-read-only-per-device]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0014-project-hub-bindings-in-project-note-and-link-index]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[0017-reminders-native-entity-omnifocus-tag-bridge]]"
  - "[[0019-practice-lines-nested-lines-measured-by-entries]]"
---

# 0018 — Memos: notes bound by rules to events and tasks, shown before and after

## Context and Problem Statement

Some of the owner's activities need a short text at the right moment rather than a task. Some examples:

- **Daily sessions of one study line** live in the calendar, not in OmniFocus. Before a session the owner wants a list of how to prepare. At its end he wants a nudge to do the closing steps and to record whether he did them.
- **Exercise slots** (a main slot on fixed weekdays, a morning slot) follow a programme that depends on the weekday and the slot. Some exercises have variants that should rotate: cross-lateral moves with eyes closed, counting backwards, counting by 7 or by 3, counting in another language or in a different language for each number.
- **Trips** have a preparation note that is useful a day before, not 15 minutes before.
- **Tasks** built on an old plan need that plan read before starting, and some need a report filled in after finishing.

The text changes often and must not be copied into each event. **How does MoonShine attach such texts to events and tasks, show them at the right moments, start the follow-up writing, and record what was done?**

## Decision Drivers

- The text lives in one place and is edited in Obsidian. Events and tasks are not touched.
- Binding is by rule (calendar, title, weekdays, time, tag), with a one-off form for single events.
- More than one moment per activity: before the start, at the end, a day ahead.
- The vault stays read-only until the Write phase (ADR-0015). The calendar stays read-only (ADR-0012). OmniFocus is not written before the Act phase.
- The same day must look the same on every device, without extra synced state.
- UI tone (CLAUDE.md rule 8): no red, no "missed".
- Memo texts are private: they never reach the repository, logs or the assistant unless the allowlist of ADR-0015 says so.

## Considered Options

1. **Memo notes in the vault with their rules in frontmatter; programmes as vault notes; outcomes as native records.**
2. A text in the notes field of each calendar event or OmniFocus task.
3. Rules and texts stored in MoonShine and edited in its UI.
4. One central vault note with a table of all rules pointing to text notes.

## Decision Outcome

**Chosen option: "1"** (owner, 2026-10-19), because the rule sits next to the text it governs, the owner edits both in Obsidian, and the reader already parses frontmatter with typed problems (ADR-0014).

**This ADR amends ADR-0017** (its notification planner also schedules memo moments), **ADR-0015** (a ritual can be started from a memo), **ADR-0013** (the memo commands join the native `auto` class) and **ADR-0010** (memo sections are synced in encrypted fields). ADR-0012 is not amended: no calendar identifier is stored or synced (owner, 2026-10-19).

### The `moonshine` key

- One frontmatter key marks every note kind that MoonShine reads by kind rather than by folder: `moonshine: memo`, `moonshine: programme` (here) and `moonshine: entry` (ADR-0019). The owner's own keys, such as `type`, are never used for this.
- One scanner finds them across the vault under the vault contract's rules (hidden folders, links, limits). It reads only the frontmatter: at most the first 8 KiB, stopping at the closing `---`. Bytes after it are discarded unparsed.
- An unknown value (a typo such as `memmo`) yields the problem `noteKindUnknown` with the path.

### Memo notes

- A note with `moonshine: memo` in frontmatter is a memo. Its body is read only to extract the two sections named below. Its body has two sections, named in frontmatter, with defaults `До` and `После`. Text outside them is ignored.
- `match` holds one or more matchers. A memo applies when any matcher matches.
  - **Event matcher:** `calendar`, `title` (exact, or `prefix:` / `contains:`, case-insensitive), `weekdays`, `starts_between` (a local time window, for slots such as "morning"), `date` (a one-off event, such as a trip).
  - **Task matcher:** `omnifocus_tag`, `project`.
  - Tasks match by `omnifocus_tag` or `project` only. There is no implicit binding through links in a task's note: the snapshot never carries task-note text (owner, 2026-10-19).
- `moments`: a list of anchors with offsets:
  - for events: `before_start` (e.g. `15m`, `1d`), `at_start`, `after_end`;
  - for tasks: `timer_start`, `timer_stop` (ADR-0016), `defer`, `due`, `completed` (seen at the next import).
- `private: true` keeps the text out of notification banners; they show only the event's or task's title.
- `after` (optional):
  - `status: true` asks for an outcome;
  - `items: true` turns the checklist of the `После` section into checkboxes;
  - `ritual: <name>` names the ritual to start (below);
  - `entry: {line: <id>, kind: <kind>}` names the practice entry (ADR-0019) that counts as "written" for this occurrence.
- A memo note that cannot be read as a memo yields the typed problem `memoNotRecognised` with its path. A bad matcher or moment is dropped with its own problem, never silently. A memo with no valid matcher matches nothing and says so.
- **Several memos on one item:** all are shown, ordered by path. There is no winner, so no memo can hide another. At most 5 are shown; above that, a problem names the item.
- **A memo never shows a note with `moonshine: entry`** (ADR-0019), however it is named, for example by `programme:` (owner, 2026-10-19).

### Storing memo sections (owner, 2026-10-19)

- The stored and synced copy of each section is at most 2 KiB. A longer section is cut at the last line break before the limit and ends with "…", and the memo gets the problem `memoSectionTruncated`. On the Mac the full section opens from the vault (owner, 2026-10-20).
- The Mac stores the two sections of each memo locally, so that Today and the planner read them from the store like any other data.
- With sync on, they are synced in CloudKit encrypted fields, as the command text of ADR-0015 is (ADR-0010 is amended to name them on the consent screen).
- **A memo with `private: true` is never synced.** It is stored on the Mac only, and is shown and notified only there.

### Programmes

- A note with `moonshine: programme` describes slots × weekdays → exercises, from its `start` date. Each exercise may have variant sets: the move variants, and the counting modes (languages, "a different language per number", backwards, by N). The owner converts his current Excel plan into such a note; there is no Excel import.
- **Today's choice is computed, not stored.** Each set rotates by the number of occurrences of the slot since the programme's `start` date, modulo its length, not by the day number: a slot on fixed weekdays would otherwise see only some of its variants (owner, 2026-10-19). When the lengths are coprime (for example 7 move variants × 5 counting modes), every combination appears once in 35 occurrences of the slot. Every device computes the same choice; an occurrence the owner skips still counts, so the cycle does not break.
- `ChooseOtherVariant` stores an override for that occurrence only.
- A programme is the content of a memo: the memo's `До` section may embed `programme: <note>` and `slot: <name>`. Today shows it as a card (exercise · variant · counting mode), not as raw text.
- The exact note format is fixed in the slice spec (P4), with fixtures.

### Occurrences and outcomes (native, synced under ADR-0010)

- An **occurrence** is keyed by the memo note's path and (owner, 2026-10-19 and 2026-10-20):
  - for an event: its start as a local date-time, plus an ordinal when several matched events share that start. The ordinal comes from a stable sort, by end time and then by title, never from Today's display order. The title is used only for sorting and is not stored. No calendar identifier is used anywhere, so ADR-0012 stays as it is.
  - for a task: the OmniFocus task id plus the local date. Task ids are stable and are already stored.
- **`MemoOutcome`**:
  - the occurrence key;
  - a status (`done` · `partly` · `not done`);
  - the checked items, each by the SHA-256 of its text after Unicode NFC normalisation (stable across launches and devices);
  - an optional variant override;
  - the device and the time.
- Commands, all native `auto` (ADR-0013), logged and undoable: `RecordMemoOutcome`, `ChooseOtherVariant`, `DismissMemo`.
- When `after.entry` is set and the vault holds a matching practice entry (ADR-0019) for the occurrence's day, the outcome shows "written" by itself. The fact comes only from the entry, so one action is never counted twice; the outcome's own status stays what the owner recorded. Nothing is written for it.

### Starting to write

- `after.ritual` names a `Ritual` of ADR-0015. From the Write phase on, the memo's button opens the ritual's draft in MoonShine's editor, pre-filled from the template with the occurrence's facts (`{{title}}`, `{{date}}`, the line). Saving runs `CreateNote` or `AppendToNote` under ADR-0015's rules.
- The ritual's template is expected to carry the entry's frontmatter (`moonshine: entry`, `line`, `kind`, `date`), so the note it creates counts at once.
- **Before the Write phase** the button opens Obsidian on the ritual's template, or on the day's entry when it exists. MoonShine writes nothing, and the Obsidian URL scheme is used only to open, never to create or append.

### Where memos are shown

| Place                                       | What                                                                                              | From                      |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------- |
| Today on the Mac: next to the event or task | `До` before the item, `После` and the outcome after it                                            | P1 (phase 2)              |
| Notifications at the memo's moments         | title + up to 3 lines of the section, or the title only when private; tapping opens the full memo | P2 (with Reminders (Mac)) |
| Outcome sheet                               | status, items, "start report"                                                                     | P3                        |
| Exercise card                               | today's programme for the slot                                                                    | P4                        |
| iPad and iPhone                             | all of the above                                                                                  | 3b                        |

**Notifications ring on the iPhone** (the watch mirrors it). Once the iPhone app exists, the Mac shows memos on Today without sound. Until then the Mac notifies. A private memo is never synced, so it is shown and notified on the Mac only.

### Roadmap

| Phase / slice   | Change                                                                                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 2         | **P1** (risky: parses vault notes): memo notes, matchers, problems, the stored sections, display on Today for events and tasks. Re-baseline phase 2's forecast. |
| After phase 2   | **P4** (risky: parses vault notes): programmes, the rotation, the exercise card, `ChooseOtherVariant`.                                                          |
| Reminders (Mac) | **P2**: memo moments in the notification planner of ADR-0017. Task anchors `timer_start` and `timer_stop` need Timer (Mac).                                     |
| After P2        | **P3** (risky: commands and storage): outcomes, report detection, "open in Obsidian".                                                                           |
| Write           | "Start report" runs the ritual inside MoonShine.                                                                                                                |
| 3b              | Memos, notifications and outcomes on the iPad and iPhone; private memos stay on the Mac.                                                                        |

### Consequences

- Good:
  - one text per activity, edited in Obsidian, shown wherever the activity appears;
  - the day's programme rotates without stored state and looks the same on every device;
  - preparation and closing steps get their own moments, and outcomes say what was actually done;
  - reports start from the memo without a new write path.
- Bad:
  - rules in frontmatter are typed by hand. A typo shows up as a problem, but only in MoonShine.
  - notifications reflect the calendar as of the last refill (ADR-0017). An event moved while the app was not running may be announced at its old time.
  - before the Write phase, "start report" only opens Obsidian.
  - an occurrence is known by its start: an event moved to another time is a new occurrence, and items that share a start are told apart only by their order.
- Neutral:
  - a `MemoReader` in the `ObsidianAdapter`;
  - matching and rotation in Core, with no platform types.

### Confirmation

- **Reader tests on fixtures:**
  - each matcher and moment kind is read;
  - a bad matcher or moment gives its own problem and does not drop the memo;
  - a non-memo note is ignored;
  - text outside the two sections is not shown;
  - the caps hold: more than 5 memos on one item gives a problem, a section over 2 KiB is cut at the last line break before the limit, ends with "…" and gives `memoSectionTruncated`;
  - a memo never shows a note with `moonshine: entry`.
- **Matching tests:** weekdays, a time window across midnight, a one-off date, case-insensitive titles, a task tag, a task project. Two memos on one item are both shown.
- **Rotation tests:**
  - with coprime lengths, every combination appears once per product of lengths, counted in occurrences of the slot;
  - a Mon/Wed/Fri slot with 7 variants shows all 7 in 7 occurrences;
  - the same date gives the same choice regardless of device or time zone of computation (local day);
  - an override affects one occurrence only.
- **Outcome tests:**
  - every command can be undone;
  - the occurrence key holds no calendar identifier and no event title; two events with the same start get ordinals by end time, then title, the same on every device and whatever Today's order; a task's key is its OmniFocus id and local date;
  - a checked item's hash is the same after a relaunch and on another device;
  - a matching entry for the day marks "written", while an entry for another line, kind or day does not;
  - nothing is written to the vault.
- **Privacy tests:** a private memo's notification carries no body text; a private memo is never in the sync payload; synced sections are in encrypted fields only; no memo text appears in logs or problem messages.

## Pros and Cons of the Options

### 2. Text in each event's or task's notes

- Good — no new file format.
- Bad — the text is copied into every occurrence and goes stale. Editing it means writing to the calendar or OmniFocus.

### 3. Rules and texts in MoonShine

- Good — a UI to pick events; no typos.
- Bad — the texts leave Obsidian. A UI for rules has to be built before the feature is useful. Every edit becomes a command.

### 4. One central rules note

- Good — all rules visible at once.
- Bad — the rule and its text drift apart. One bad row affects every memo.

## More Information

Spikes before P1's spec:

1. How many lines of a notification body do the Mac, iPhone and watch show?
2. The current Excel programme converted by the owner into a note: its constructs only, no content, to size the format.

Follow-ups: export the vault links of a task's note (links only, never its text) from OmniFocus, so that a task can show the notes it links to; matchers on the event's location or attendees; a memo moment relative to travel time; memos for reminders (ADR-0017).
