---
title: Settings → Calendars
status: draft-3
date: 2026-10-02
artboards:
  [
    mockups/SettingsCalendars.dc.html,
    mockups/SettingsCalendars-None.dc.html,
    mockups/SettingsCalendars-Denied.dc.html,
    "+ -Dark variants",
  ]
related: ["[[settings]]", "[[today]]", "[[week]]"]
---

# Settings → Calendars (draft-3)

Calendar events come from the system calendars (EventKit) on each device. **Read-only**: MoonShine never creates or edits events in this round. The app works fully without calendar access.

## Layout

A tab in the native `Settings` scene (General · Data · **Calendars** · Refresh), drawn as a 780 × 660 window.

1. **Access row**: `Calendar access` + state + one button.

   | State                          | Label               | Button                                | Caption                                                                                                                                                       |
   | ------------------------------ | ------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | not determined                 | `Not connected`     | `Connect calendars…` (default button) | MoonShine asks macOS for read-only access. Nothing is created or edited. The app works fully without it.                                                      |
   | granted                        | `Connected`         | `Open System Settings…`               | MoonShine reads events through macOS (EventKit), read-only.                                                                                                   |
   | denied                         | `Access denied`     | `Open System Settings`                | Calendar access is off for MoonShine. Allow it in System Settings → Privacy & Security → Calendars. Today, Week and Month work without events.                |
   | write-only ("Add Events Only") | `Can't read events` | `Open System Settings`                | MoonShine can only read calendars with Full Access. Change it in System Settings → Privacy & Security → Calendars. Today, Week and Month work without events. |
   | restricted                     | `Not available`     | —                                     | Calendar access is restricted on this device, for example by a device-management profile. Today, Week and Month work without events.                          |

   Demo mode shows invented calendars and a `Demo data` badge next to the label.

2. **Calendars** (only when connected), grouped by account (`iCloud`, `Work · Exchange`, `Subscribed`). Columns: Calendar (`CalendarDot` + name) · **Show** (switch) · **Counts as busy** (switch) · **Line** (`Picker(.menu)`: None or one line, e.g. `Music lessons` → `🎻 Violin`; the line mapping is cut from phase 1, owner 2026-10-30, `docs/specs/phase-1-see.md` Goal: phase 1 ships no Line column). A calendar with Show off is greyed; Counts as busy can be off while Show is on (e.g. public holidays).
3. **Day window** (configurable — decided 2 Oct 2026): two time pickers, default `08:00`–`22:00`, end after start, 15-minute steps. It defines the span of the day rail on Today, which items are pinned above or below it, and the free-time fact. Caption: `Free time = day window − time in calendars that count as busy − tasks with a planned time and an estimate. Today counts from now to the end of the window. Overlaps count once. Tentative, all-day and free events are shown but not counted; declined, delegated and cancelled events are hidden.`
4. Footer note: `Events stay on this device. They are not synced by MoonShine.`

Not connected / denied: the list is replaced by one neutral placeholder line (`Calendars appear here after you connect.`).

## Data

- `EKEventStore`, full read access to events (`requestFullAccessToEvents`), no reminders. Per calendar (by `calendarIdentifier`) the app stores **locally**: `show`, `countsAsBusy`, `lineID?`. Day window: two local settings.
- The per-calendar settings and the events are **per device** and never enter the MoonShine store that syncs (ADR-0010), in any phase. Each device asks for its own access. The day window is the only setting here that syncs, from 3b (a preference, not calendar data; ADR-0012).
- **A calendar with no stored setting** (owner, 2026-10-16): Show on; Counts as busy on, except subscribed and birthday calendars (off). A calendar with Show off contributes nothing, even with Counts as busy on. Each event carries its calendar's kind, so these defaults apply by kind even before the calendar list is read again (owner, 2026-10-17).
- Event → view model: start, end, isAllDay, title (empty or blank → `Busy`; EventKit exposes no private flag), calendar (name, colour), display, whether it occupies time, time zone. Display and occupying are separate (owner, 2026-10-16), read by the adapter from the owner's participation, the event's status and its availability. The adapter applies these rules **in this order**, the first that decides wins (owner, 2026-10-17):

  1. Event status cancelled → hidden (not read).
  2. The owner is the organiser → his own answer as an attendee is ignored.
  3. The owner's answer is declined or delegated → hidden (not read).
  4. Any tentative signal → display tentative (hatched), occupies no time: his answer is pending (not answered), tentative or in process; or the event status is tentative (set by the organiser); or the availability is tentative.
  5. Otherwise → display normal, occupies time: accepted, completed (treated as accepted; owner, 2026-10-17), unknown, no attendees, the owner is the organiser, the owner is not among the attendees.
  6. Last: availability free → occupies no time, display unchanged. Out of office (availability unavailable) has no rule of its own.

  An all-day event never occupies time, whatever the rules above say.

## Behaviour

- `Connect calendars…` triggers the system prompt once. After a denial the button becomes `Open System Settings` (deep link to Privacy & Security → Calendars).
- Toggling Show / Counts as busy / Line (Line: cut from phase 1, owner 2026-10-30) applies immediately everywhere; no restart.
- Calendar changes arrive through `EKEventStoreChanged`; views refresh without the importer.
- Cut from phase 1 (owner, 2026-10-30): a mapped calendar adds the line emoji to its events and feeds "Upcoming" in Line detail and the quick-log suggestion on iPhone.

## SwiftUI

`Settings { TabView { … CalendarsSettingsView().tabItem { Label("Calendars", systemImage: "calendar") } } }`. `Form(.grouped)`; the list as `Table` or `Grid` inside a `Section` per `EKSource`; `Toggle().toggleStyle(.switch).controlSize(.mini)`; `Picker(.menu)` for the line. A `CalendarProvider` port in Core with an EventKit adapter and a fixture adapter (Demo).

## Acceptance

- [ ] With access never requested, denied or revoked, every screen renders completely and no error is shown.
- [ ] No write API of EventKit is linked or called (`save`, `remove`).
- [ ] Turning off "Counts as busy" changes the free-time facts and nothing else.
- [ ] Demo mode never calls EventKit.
- [ ] Checked in Russian.
