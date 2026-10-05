---
title: "0012 — Calendar: EventKit read-only on each device; events are never stored or synced"
status: proposed
date: 2026-10-02
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0001-own-domain-model-with-ports-and-adapters]]"
  - "[[0005-assistant-tools-over-domain-proposals-and-mcp]]"
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[settings-calendars]]"
---

# 0012 — Calendar: EventKit read-only on each device; events are never stored or synced

## Context and Problem Statement

Tasks alone give a false picture of a day: Today can list ≈ 11 h of tasks on a day with 4 h of fixed commitments. MoonShine is meant to become the owner's main app for time, so calendar events must be visible at every scale and must feed "free time" (phase 1) and capacity (phase 2). Events are personal data from a third system and often carry other people's names. **Where do events come from, where do they live, and who may see them?**

## Decision Drivers

- Private by default (VISION principle 5): as few copies of third-party personal data as possible.
- Near real-time: a changed event should be visible without an import.
- The iPad and iPhone must not depend on the Mac for calendar data (unlike OmniFocus data, ADR-0010).
- Ports and adapters (ADR-0001): Core stays free of EventKit.
- No writes to external tools before the Act phase (CLAUDE.md rule 6).

## Considered Options

1. **EventKit on each device, read live through a `CalendarProvider` port; events are not persisted and not synced.**
2. Import events into the MoonShine store on the Mac and replicate them through CloudKit, like provider data.
3. Own CalDAV / Google Calendar / Exchange adapters.
4. No calendar; rely on OmniFocus tasks only.

## Decision Outcome

**Chosen option: "1"**, because the system calendar database already exists on every device, is kept current by the system, announces its own changes, and is covered by the system permission prompt. Reading it live means MoonShine holds no second copy of the events.

Rules that follow:

- **Port.** `CalendarProvider` in Core: access state, calendars, `events(in:)`, and a change stream. `CalendarEvent` and `CalendarInfo` are Core value types. Adapters: `EventKitCalendarProvider` (macOS, iPadOS, iOS) and a fixture provider for Demo mode and tests.
- **Read-only.** No EventKit write API (`save`, `remove`) is called until the Act phase spec exists. Access is requested with `requestFullAccessToEvents` (the only level that allows reading); reminders are not requested.
- **No storage, no sync.** Events are not written to the MoonShine store, the change log, CloudKit, logs or crash reports. They are held in memory for the visible range only.
- **Derived numbers may be stored.** From phase 2, per-day busy minutes (numbers only, no titles, no attendees) may be stored as MoonShine-native data for calibration and synced under ADR-0010. This is the only calendar-derived data that leaves the device.
- **Settings.** Per-calendar `show`, `countsAsBusy`, `line` and the day window are local in phase 1 (keyed by `calendarIdentifier`). When the iPad arrives (3b) they become synced native settings keyed by account title + calendar title, with `calendarIdentifier` kept as a per-device cache, because the identifier is not stable across devices.
- **Day load in Core.** Busy, planned and free time are computed by a Core service from events (values), tasks and the day window, so that every platform shows the same numbers for the same inputs. The presentation rules live in `design/screens/`.
- **Timed tasks.** A task appears on the day rail by its planned date-time; a due date-time today is a due mark. OmniFocus stores a time on every date, so the bridge exports OmniFocus' default times and Core treats a time equal to the default as "date only".
- **Change signal.** `EKEventStoreChanged` feeds the change stream; views refresh without the importer. It is the first source for change-driven refresh (ADR-0011, planned).
- **Assistant (phase 4).** Tools expose event counts and busy time by default. Event titles are exposed only after an explicit opt-in in Settings.
- **Demo mode** uses the fixture provider and never calls EventKit.

### Consequences

- Good — events are current within a second on every device, with no importer and no Mac dependency.
- Good — the fewest possible copies of third-party personal data; nothing to leak through sync or backups of the store.
- Good — the same adapter serves macOS, iPadOS and iOS.
- Bad — a number that mixes synced plans with local calendar time can differ between devices when they see different calendars; phase 2's stored busy minutes reduce this for forecasts.
- Bad — no event history: a past event that is deleted or changed disappears from past days. Past busy time is reproducible only from phase 2 onward (stored busy minutes).
- Bad — each device asks for calendar access separately; the app must be complete without it.
- Neutral — needs the calendars entitlement and `NSCalendarsFullAccessUsageDescription`.
- Neutral — privacy rule 5 in `CLAUDE.md` is extended: no real event titles, attendees or calendar names in commits, PRs or logs; fixtures are invented.

### Confirmation

- Architecture test: `MoonShineCore` does not import EventKit; no call to `EKEventStore.save` / `remove` exists in the repository.
- With access not requested, denied or revoked, every screen renders completely; Demo mode makes no EventKit call (mock provider asserts zero calls).
- Core tests derive the demo day's facts from the fixtures: `4 events · 4 h in calendar · 1 h 15 min planned`, overlap counted once, tentative and all-day events not counted.
- The store schema has no table or column that can hold an event title.

## Pros and Cons of the Options

### 2. Import into the store and replicate

- Good — one consistent picture on all devices; event history for free.
- Bad — copies other people's data into SQLite and iCloud; needs an importer run for every change; makes the iPad depend on the Mac for something it can read itself.

### 3. Own CalDAV / Google / Exchange adapters

- Good — independent of Apple's calendar database.
- Bad — credentials, tokens and three protocols to maintain for data the system already has.

### 4. No calendar

- Bad — Today and Week keep showing a day that does not exist; capacity in phase 2 would have to be typed by hand.
