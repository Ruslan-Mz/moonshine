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
- Obsidian vault (S4-4d): the folder's name with a folder symbol, never its path (owner, 2026-11-10), + `Choose…` (Live only) → `.fileImporter(allowedContentTypes: [.folder])` → a security-scoped, read-only bookmark, then an import as ⌘R. A folder without `.obsidian/` is refused with one sentence under the row, `This folder is not an Obsidian vault — choose the folder that holds .obsidian`, and nothing is saved (owner, 2026-10-28). A folder whose bookmark cannot be made keeps the vault chosen before: `Couldn't keep the new folder — the vault is still <name>` (owner, 2026-11-10, PR #53 round 1); with none chosen before, `Couldn't keep this folder — choose it again` (owner, 2026-11-10). Switching to Live with no folder chosen opens the picker; cancelling keeps Live. The row says, in this order: `not read in Demo mode` in Demo (the bookmark is never shown there); `Not chosen`; `Not read yet` (no import since the folder was chosen, or that import had none); `Can't be read — choose it again` (the bookmark does not resolve, or the folder no longer holds `.obsidian/`: nothing is read and nothing stored is removed, owner 2026-11-10); `More than 20,000 notes — not read`; otherwise the name.
- OmniFocus: status text (`not read in Demo mode` / `last full import 14.0 s`, one decimal; S4-4c-1: `last full import` with no number when the duration was not measured, `not read yet`, `Live data could not be opened.` when Today says so, or the words of `design/copy.md` § Live source when OmniFocus is not running or the last import did not commit).
- Tag groups (S4-4c-2): `groups found: n of m`, the names of `mapping.yaml` (Demo: its own invented set) that a top-level tag of the workspace shown has, whatever groups it was imported under; `not counted yet` while no workspace is shown (before the first import, or when the store cannot be read); with no file, `no mapping file — …` and the next step; with an invalid one, the OmniFocus line's sentence, `The mapping file cannot be read — fix it, then quit MoonShine (⌘Q) and open it again`; when the source's data could not be set up at all (no data folder, store or bridge script), `Live data could not be opened.` in Live and `Demo data could not be loaded.` in Demo (`design/copy.md` § Live source).
- Caption: "Demo shows bundled sample data — nothing is read from OmniFocus or your vault." and, since S4-4d, "MoonShine only reads the vault; the folder is remembered as a bookmark" (owner, 2026-11-10, PR #53 round 1: the app is not sandboxed, so read-only is the code's rule, ADR-0004).

**General** group (draft-2). **Not in phase 1** (owner, 2026-11-25; timebox decision, option A): the language spike, the picker and the restart move to the usage period; until then the app follows macOS' language and its per-app setting.

- Language: `Picker(.menu)` **System** + every shipped language in its own name (phase 1: English, Русский) (see `i18n.md`, ADR-0009). Changing it shows a confirmation `MoonShine will restart to switch the language.` with Restart / Cancel, unless the S4 spike proves a live switch. **Not in phase 1** (owner, 2026-11-25).
- Content languages: an ordered list of the languages the owner writes in (default from macOS preferred languages; e.g. RU, EN, LV, IT, DE) — hints for content-language detection only. Changing it applies immediately (re-detection runs at the next import); no restart. **Not in phase 1** (owner, 2026-10-30, Q3.2; recorded 2026-11-24, S4-3c-1): nothing reads it until a `LanguageDetector` exists, so it would store a setting nobody reads.
- Caption: "Line names, tasks and notes are shown as they are in OmniFocus and Obsidian." **Not in phase 1**, with the picker (owner, 2026-11-25).

**Refresh** group. **Not in phase 1** (owner, 2026-11-25, S4-3c-2 Q1): it moves to the usage period; until then the coordinator's timer runs at 15 minutes and the toolbar's Refresh button and ⌘R import at once (§ Toolbar).

Refresh follows ADR-0011: imports are always full and start when OmniFocus resigns active, on launch, on ⌘R and on a timer.

- Timer: `Picker(.menu)` 15 / 30 minutes, default **15 min**. It runs only while OmniFocus is running and not frontmost.
- Last import: `3 min ago · 4.0 s` + "Refresh now ⌘R".
- Caption: "Imports run in the background; the window always renders from the local store."

**Deadlines** group (owner decision 2026-10-02)

- Which due dates are deadlines: `Picker(.radioGroup)` **All due dates** (default) | **Due date + tag**.
- Tag (only with "Due date + tag"): text field, default `deadline`, matched by leaf name like `anchor`. The value is trimmed; an empty value reverts to `deadline`; the leaf name is compared case-insensitively (`Deadline` matches `deadline`). The tag counts when it is on the task or on **any of its ancestors** (action group or project), so an inherited due date follows the same rule.
- Caption: "Only deadlines get the amber due badge. Other due dates are shown as plain text."
- The rule is a Core value (`DeadlineRule`) that the Overview service uses for urgency on Today (its list and the Day rail), Week and Line detail; the view only displays the result.
- Built in S4-3c-2 (owner, 2026-11-25): a `Section` of the one Settings form, after Data (no tabs until Calendars, S4-3d); the picker's label hidden, the section header naming it. The tag field starts with the stored tag and commits on Return, on focus loss, when any window resigns key (a click into the main window keeps the field's focus) and when Settings closes, never per keystroke (a cleared field would revert to `deadline` while typing); an unchanged tag writes nothing; after a commit it shows the stored tag (PR #72 round 1). Stored in the app's defaults as two strings, `deadlineMode` (`allDueDates` | `dueDateAndTag`) and `deadlineTag`, never in the store; an unknown mode reads as all due dates.
- When no tag of the workspace shown has the tag's leaf name, a quiet caption under the field says so: `No tag is named “Deadlne” — check the name; no due date is amber now` (owner, 2026-11-25, S4-3c-2 Q2; like the Tag groups line). None while nothing is shown, or with all due dates.

**Reminders** group (S4, ADR-0017; cut with the whole bridge if the timebox is at risk)

- Reminder tag: text field, default `напоминание`, matched by leaf name like `deadline`; trimmed, an empty value reverts to the default, compared case-insensitively. Tasks with this tag are shown in Today's Reminders strip and hidden from every task list, count, statistic, forecast and load.
- Caption: "Tasks with this tag are reminders: you see them on Today; they are not counted as tasks. Notifications stay with OmniFocus for now."

Buttons (sheet variant only): Cancel, Done (default, accent). The Settings scene applies changes immediately.

**Time** tab (draft-5; Timer (Mac), phase 2; `timer-mac.md`)

- **Work:** a list of the lines, each with a checkbox; checked lines are **work** in the day balance and the week table's Work row (owner, 2026-10-28). Asked once on the first open of the timer (`timer-mac.md` § Work lines); until answered, or after `Not now`, none is checked and no Work term is shown anywhere.
- **Activity palette:** sections in order (Lines · Projects · Life ops, reorderable); pinned projects and tasks (up to 8, removable; with eight, `Pin to Palette` is disabled until one is removed); the system-wide shortcut (a recorder, default `⌃⌥T`); `Show in the menu bar: Always | While a timer runs` (with the second and nothing running, ⌃⌥T shows the item while the popover is open).
- **Life ops categories:** eight defaults (Sleep, Food, Cooking, Hygiene, House, Transport, Errands, Inbox); rename, change the emoji, reorder, add, archive (owner, 2026-10-28). Sleep is built in: it can be renamed, not archived (it marks where "today so far" starts). Each category may set its own break-nudge minutes and check limit; by default Sleep has no break nudge and a 12 h check limit, the others use the defaults below.
- **Nudges** (ADR-0016): Break nudge on/off and its **default** minutes (50); the **default** check limit (4 h); day marks on/off; the calendar suggestion on/off. A line overrides the two defaults with `break_after_min` and `check_after_h` in the budget note (owner, 2026-10-28; `docs/discovery/vault-contract.md` § 1, "Nudge values"); caption `A line can set its own values in the budget note: break_after_min, check_after_h.`
- Caption: `Time entries are MoonShine’s own data. They are never written to OmniFocus, your vault or your calendars.`

## Toolbar

On the right of the main window's toolbar (`design/principles.md`): **Refresh**, an `arrow.clockwise` icon with the tooltip `Refresh (⌘R)`, which imports as ⌘R does, in Demo and Live, and is never disabled (the coordinator coalesces requests, ADR-0011); the ⌘R shortcut stays on the menu item (owner feedback 2026-11-06; S4-3c-2, 2026-11-25). Then **Settings**, a `gearshape` icon with the tooltip `Settings (⌘,)` (S4-3c-1).

## Status bar

`.safeAreaInset(edge: .bottom)` HStack, 28 high: the source, "Demo data" or "Live" (S4-4c-1, as `docs/specs/phase-1-see.md` asks) · `Updated 3 min ago` (relative, refreshes every minute, counted from the last committed import's end; for 5 s after an open that did not open, the opener's notice stands in its place, `Note not found`, `Could not open it`, `Demo data — opens with Live data`, or in Live `Vault not chosen` / `Vault can't be read`, which may then repeat a vault note further along the bar; S4-5, owner 2026-11-25, `design/copy.md` § Opening links: `Updated just now` under a minute, `Updated N min ago` under an hour, `Updated N h ago` under a day, then `Updated on 3 October`, with the year only when it is not the current one; owner, 2026-10-28; it redraws on the clock's whole minutes, so a step can show up to a minute late, and at once when an import finishes; owner, 2026-11-04) · in Live, in this order (S4-3c-2, 2026-11-25: the code's order, `StatusBarTests`): first, with data shown, OmniFocus' note: `OmniFocus is not running — showing the last import` while it is not running; when the last import could not read OmniFocus (no permission, no answer in time, data it cannot read), `OmniFocus can't be read — see Settings` / `OmniFocus не читается — см. Настройки`; any other unfinished import, `The last import did not finish`; Today shows no other notice of it while data is shown (owner, 2026-11-24) · then, whatever OmniFocus' state, the mapping file's sentence while the file is invalid (`design/copy.md` § Live source) · then, while the shown import did not read the vault (none shown, or not chosen, unreadable or too large; owner, 2026-11-10), whatever Today shows, the reason, shorter than the Settings row's sentence (`design/copy.md` § Live source): `Vault not chosen` / `Хранилище не выбрано`, `Vault can't be read` / `Хранилище не читается`, `Vault too large to read` / `Хранилище слишком большое — не прочитано`, otherwise `Vault not read yet` (owner, 2026-11-24) · while importing: a small `ProgressView` + `Updating…` (never blocks the UI; ADR-0011:64, owner, 2026-10-28) · shortcut hints on the right.

## Acceptance

- [ ] Fresh clone runs in Demo mode with no vault and no OmniFocus.
- [ ] Switching to Live without a vault prompts "Choose…", not an error.
- [ ] No write APIs anywhere (phase 1).
- [ ] The timer offers no interval under 15 min; there is no "incremental" label. Not in phase 1, with the Refresh group (owner, 2026-11-25).
- [ ] Switching the deadline rule changes which due dates are amber on Today, Week and Line detail, and nothing else (strong quotas stay amber whatever the rule: owner, 2026-10-27; ADR-0020).
- [ ] Changing the reminder tag moves those tasks between the Reminders strip and the task lists and counts; nothing else changes (unless the bridge is cut).
- [ ] Language picker switches the whole UI; user data stays untranslated; dates and plurals follow the chosen language. Not in phase 1, with the picker (owner, 2026-11-25).

## Calendar (draft-3)

A new tab **Calendars**: access state, calendars with Show / Counts as busy / Line, day window. Spec: `settings-calendars.md`.
