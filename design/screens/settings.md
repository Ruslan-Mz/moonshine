---
title: Settings and status bar
status: draft-2
date: 2026-10-01
slice: S4
artboards: [mockups/Settings.dc.html, mockups/Settings-Dark.dc.html]
---

# Settings + status bar (draft-2)

## Settings

Recommended implementation: a native `Settings` scene (⌘,) with `Form { }.formStyle(.grouped)`. The canvas draws a sheet (580 wide, attached under the toolbar) only to show it in context.

**Data** group

- Source: `Picker(.segmented)` **Demo | Live**.
- Obsidian vault: path field (folder symbol + `~/Documents/Life vault`) + "Choose…" → `.fileImporter(allowedContentTypes: [.folder])` → security-scoped bookmark.
- OmniFocus: status text (`not read in Demo mode` / `last full import 14 s`).
- Caption: "Demo shows bundled sample data — nothing is read from OmniFocus or your vault. The vault is opened read-only through a security-scoped bookmark."

**General** group (draft-2)

- Language: `Picker(.menu)` **System** + every shipped language in its own name (phase 1: English, Русский) (see `i18n.md`, ADR-0009). Changing it shows a confirmation `MoonShine will restart to switch the language.` with Restart / Cancel, unless the S4 spike proves a live switch.
- Content languages: an ordered list of the languages the owner writes in (default from macOS preferred languages; e.g. RU, EN, LV, IT, DE) — hints for content-language detection only. Changing it applies immediately (re-detection runs at the next import); no restart.
- Caption: "Line names, tasks and notes are shown as they are in OmniFocus and Obsidian."

**Refresh** group

Refresh follows ADR-0011: imports are always full and start when OmniFocus resigns active, on launch, on ⌘R and on a timer.

- Timer: `Picker(.menu)` 15 / 30 minutes, default **15 min**. It runs only while OmniFocus is running and not frontmost.
- Last import: `3 min ago · 4.0 s` + "Refresh now ⌘R".
- Caption: "Imports run in the background; the window always renders from the local store."

**Deadlines** group (owner decision 2026-10-02)

- Which due dates are deadlines: `Picker(.radioGroup)` **All due dates** (default) | **Due date + tag**.
- Tag (only with "Due date + tag"): text field, default `deadline`, matched by leaf name like `anchor`. The value is trimmed; an empty value reverts to `deadline`; the leaf name is compared case-insensitively (`Deadline` matches `deadline`). The tag counts when it is on the task or on **any of its ancestors** (action group or project), so an inherited due date follows the same rule.
- Caption: "Only deadlines get the amber due badge. Other due dates are shown as plain text."
- The rule is a Core value (`DeadlineRule`) that the Overview service uses for urgency on Today and Week; the view only displays the result.

**Reminders** group (S4, ADR-0017; cut with the whole bridge if the timebox is at risk)

- Reminder tag: text field, default `напоминание`, matched by leaf name like `deadline`; trimmed, an empty value reverts to the default, compared case-insensitively. Tasks with this tag are shown in Today's Reminders strip and hidden from every task list, count, statistic, forecast and load.
- Caption: "Tasks with this tag are reminders: you see them on Today; they are not counted as tasks. Notifications stay with OmniFocus for now."

Buttons (sheet variant only): Cancel, Done (default, accent). The Settings scene applies changes immediately.

## Status bar

`.safeAreaInset(edge: .bottom)` HStack, 28 high: "Demo data" capsule (Demo only) · `Updated 3 min ago` (relative, refreshes every minute) · while importing: a small `ProgressView` + `Importing…` (never blocks the UI) · shortcut hints on the right.

## Acceptance

- [ ] Fresh clone runs in Demo mode with no vault and no OmniFocus.
- [ ] Switching to Live without a vault prompts "Choose…", not an error.
- [ ] No write APIs anywhere (phase 1).
- [ ] The timer offers no interval under 15 min; there is no "incremental" label.
- [ ] Switching the deadline rule changes which due dates are amber on Today and Week, and nothing else (strong quotas stay amber whatever the rule: owner, 2026-10-27; ADR-0020).
- [ ] Changing the reminder tag moves those tasks between the Reminders strip and the task lists and counts; nothing else changes (unless the bridge is cut).
- [ ] Language picker switches the whole UI; user data stays untranslated; dates and plurals follow the chosen language.

## Calendar (draft-3)

A new tab **Calendars**: access state, calendars with Show / Counts as busy / Line, day window. Spec: `settings-calendars.md`.
