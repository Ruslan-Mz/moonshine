---
title: Timer on the Mac — menu bar, activity palette, start points
status: draft-5
date: 2026-10-28
slice: Timer (Mac), the last slice of phase 2 (ADR-0016)
artboards:
  [
    mockups/MenuBarTimer.dc.html,
    mockups/MenuBarTimer-RU.dc.html,
    mockups/TimerStates.dc.html,
    "+ -Dark variants",
  ]
related:
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[time]]"
  - "[[iphone-capture]]"
---

# Timer on the Mac (draft-5)

The owner finds out only in the evening that the day went to work. He switches between projects all day, mostly while working in other apps, and logging afterwards from memory is what failed with the workbook. On the Mac the timer therefore has to start, switch and stop **without bringing MoonShine to the front**, and say during the day where the time is going. The iPhone Lock Screen is the first capture surface (`iphone-capture.md`); the Mac menu bar is the second.

Data model, commands and counting rules are ADR-0016's. This spec adds the surfaces.

## Where the palette lives — decided: the menu bar

| Option                                              | Reach from another app                                  | Keyboard            | Running time in view              | Room                     | Verdict                                                                            |
| --------------------------------------------------- | ------------------------------------------------------- | ------------------- | --------------------------------- | ------------------------ | ---------------------------------------------------------------------------------- |
| **Menu bar popover** (`MenuBarExtra`, window style) | one click, or the system-wide shortcut; no app switch   | full in the popover | yes, the item itself (ADR-0016)   | 380 wide, about 820 high | **chosen**                                                                         |
| A section of the main window                        | ⌘-Tab to MoonShine, then the view: two moves per switch | full                | only while the window is in front | plenty                   | rejected: a switch costs an app switch, the cost that made the end-of-day log fail |
| ⌘K only                                             | the window must be in front                             | full                | no                                | a list, not a grid       | kept as the second route inside the window (`command-palette.md` § Timer)          |

## Activities: what can be timed

The palette shows **activities**, the owner's word for the tiles of his phone tracker. An activity is one of:

- **A line** that is neither nested (ADR-0019: time on a nested line is recorded on its parent, and the picker does not offer nested lines) nor paused. Order: tier (foundation, active, maintenance), then the vault order. A paused line has no tile; typing its name in the palette still finds it.
- **A pinned project or task** (up to 8), with its line's emoji: `Pin to Palette` in the Timer menu or a row's context menu, and `Pin to palette: …` in ⌘K. For the projects the owner switches between all day.
- **A Life ops category.** Life ops is not a line and has no budget (`principles.md`); its time still needs a name. Default categories: 😴 Sleep · 🍽️ Food · 🍳 Cooking · 🪥 Hygiene · 🏠 House · 🚌 Transport · 🛒 Errands · 📥 Inbox. The owner renames, reorders, adds and archives them in Settings → Time. **Sleep is built in** (it can be renamed, not removed): the end of the night's Sleep interval is where "today so far" starts (`components.md` § DayBalance). A category is never a line, never budgeted, never quiet; its time shows under Life ops (`time.md` § Week). Storing the category on a time entry is a model change: question A4 for the architect (`design/README.md` § Draft-5).

Sections in the palette: Lines · Projects · Life ops (the order is a setting).

## Layout (popover, `MenuBarTimer`)

380 wide, radius 14, overlay shadow, anchored under the menu bar item. Top to bottom:

1. **Running timers.** One row per running session, up to three, the earliest first: emoji badge 32 (selection tint) · title 13 semibold (the task, else the project, else the line or category) · subtitle 11 tertiary (`Workshop 2026 · since 14:38`; `· alongside` for a session started alongside) · elapsed `0:22` 20 semibold, tabular, accent · pause or resume 26 · stop 26. A paused session shows its elapsed time in secondary with the pause glyph. A marked session carries the check glyph (§ Check mark). Nothing running: one quiet line `No timer running` and the keys below.
2. **Filter field** (28): `Start a timer…`, with the system-wide shortcut shown on the right (`⌃⌥T`). Typing filters every section (prefix or substring, case and diacritics ignored, as ⌘K) and adds matching projects and today's tasks as rows under the grid.
3. **Tiles**, four per row, 82 × 56, gap 6: emoji 18 · name 11, one line, tail truncation · today's tracked time 10, tertiary (`—` when none). Running: 1.5 pt accent outline, selection fill and an accent dot. Hover: tooltip with the full name and its shortcut (`⌘3`).
4. **Today so far**, the compact `DayBalance` on the `band` background (`components.md` § DayBalance).
5. **Footer** (30): `Time view ⌘6` (accent) · `↩ start · ⌥↩ alongside · ⌘Z undo`.

**The menu bar item** (`TimerStates`, panel "Menu bar item"):

| State           | Item                                                                        |
| --------------- | --------------------------------------------------------------------------- |
| nothing running | the `timer` glyph only                                                      |
| one running     | line or category emoji + `0:22` (h:mm, tabular, so the width does not jump) |
| two or three    | the earliest started + `+1` / `+2`                                          |
| paused          | dimmed, with the pause glyph                                                |
| marked          | `clock.badge.questionmark` after the time                                   |
| popover open    | the system highlight                                                        |

No colour in the item, ever. VoiceOver: "MoonShine timer, AI/ML, 22 minutes, 1 more running".

## Starting a timer where the work already is

**One affordance, one shortcut** (`TimerStates`, panel "Start a timer where the work is"):

- **▶ `TimerButton`** at the trailing edge of the row's name or title cell, on hover and on the selected row. A click starts a timer on that subject; ⌥-click starts it alongside.
- **⌘T** (Timer ▸ Start Timer on Selection) starts on whatever is selected: a task, a project, a line, an event or a timed task on the Day rail. **⌥⌘T** starts alongside. Both are menu commands acting on the selection, never shortcuts on lazily drawn rows (CLAUDE.md rule 9).
- **Running pill.** On the running subject the ▶ becomes an accent pill with a dot and the elapsed time (`● 0:22`); paused, a neutral pill with the pause glyph. A click on the pill pauses or resumes. A line-only session shows the pill on its line section header and its Lines row.

| Where                                                           | What starts                                                                                                                                                            | Phase or slice                                       |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Today: task rows (Top 3, line sections, From earlier, Life ops) | the task (its project and line are stored with the entry)                                                                                                              | Timer (Mac)                                          |
| Today: line section headers                                     | the line, with no task                                                                                                                                                 | Timer (Mac)                                          |
| Lines rows; Line detail toolbar `▶ Start timer`                 | the line (⌘T in Line detail with nothing selected)                                                                                                                     | Timer (Mac)                                          |
| Line detail: project rows and next-action rows                  | the project or the task                                                                                                                                                | Timer (Mac)                                          |
| Day rail: an event block (hover ▶, or selected + ⌘T)            | the event's line, target = the event's length (ADR-0016 keeps only the duration). An event in a calendar with no line opens the palette filtered to lines, to pick one | Timer (Mac)                                          |
| Day rail: a timed task block                                    | the task                                                                                                                                                               | Timer (Mac)                                          |
| The calendar suggestion, five minutes before a mapped event     | `🎻 17:00 · Start timer?` · `Start` · `Not now` (ADR-0016 § Nudges)                                                                                                    | Timer (Mac)                                          |
| A memo's "before" card (ADR-0018)                               | a button `▶ 🎻 Violin · 1 h` in the card: the event's line and length, or the task                                                                                     | P1 draws the card; the button comes with Timer (Mac) |
| Anchors strip chips, Week cards                                 | no ▶ (too dense): the context menu `Start Timer` and ⌘T on the selection                                                                                               | Timer (Mac); Week from S5                            |
| Reminders strip                                                 | nothing: a reminder is seen, not timed (ADR-0017)                                                                                                                      | —                                                    |

## Switching and the notice

ADR-0016 § Up to three running timers: **a plain start switches and never blocks**. Every running session stops at that instant; the new one starts.

- **The notice** shows for about eight seconds, non-modal, never taking focus. Started from the main window it sits in the centre of the status bar: `🤖 stopped · Keep running · ⌘Z`. Started from the popover it replaces the popover's footer line. Two stopped: `🤖 🔬 stopped · Keep running`. Three were running and the start was alongside: `🤖 stopped (three at most)`, no button.
- **Keep running** resumes the stopped sessions from the instant they stopped, with no gap, within the cap of three.
- **⌘Z** (Edit ▸ Undo Start Timer) undoes the start itself: the new session is removed and the stopped ones resume with no gap. This is the mis-tap fix on the Mac; on the iPhone the notice carries an `Undo` button (`iphone-capture.md`). The notice wording follows the ADR (`Keep running`); the brief's "Keep both" is question O1 for the owner (`design/README.md` § Draft-5).
- VoiceOver announces the notice once.

## Timer menu and keys

A **Timer** menu between View and Window:

| Command                  | Keys | Notes                                                        |
| ------------------------ | ---- | ------------------------------------------------------------ |
| Start Timer on Selection | ⌘T   | switches; disabled with nothing selected outside Line detail |
| Start Alongside          | ⌥⌘T  | stops nothing while fewer than three run                     |
| Pause All / Resume All   | ⇧⌘T  | one command, the title follows the state                     |
| Stop All                 | ⌃⌘T  | a marked session asks first (§ Check mark)                   |
| Activity Palette         | ⌃⌥T  | system-wide; changeable in Settings → Time                   |
| Pin to Palette / Unpin   | —    | on the selected project or task                              |
| Show Time View           | ⌘6   | also in the sidebar (`time.md`)                              |

⌘T is free in MoonShine (no tabs, no font panel). If automatic window tabbing would add New Tab, it is turned off for the main window. ⌘5 stays reserved for Plan (`design/README.md`, iPad open question 4); question O4 for the owner offers the swap.

In the popover: `↩` start the selected tile · `⌥↩` alongside · `⌘1`–`⌘9` the first nine tiles in display order · arrows move · `⇧⌘T` pause or resume · `⌃⌘T` stop · `⌘Z` undo the last timer command · `esc` close.

## Check mark

ADR-0016 § A forgotten timer is visible. A session that ran past its own line's limit (default 4 h) without a pause, or across Mac sleep, gets `clock.badge.questionmark` on its menu bar item, its running row and its resulting interval. Stopping it opens a small sheet: `🤖 Stop the timer from 11:20?` · `It ran 4 h 12 min without a pause. The Mac was asleep from 13:40.` · `End at 13:40` (default) · `Keep as it is`. Without sleep the first button is `Edit…`. Nothing is trimmed silently.

## Nudges

macOS notifications, wording as ADR-0016 § Nudges: `🤖 50 min · short break?` (`Break` · `Keep going`); `🎻 1 h reached`; `🎻 Today’s 1 h is in`; `🎻 17:00 · Start timer?` (`Start` · `Not now`). Shown in `TimerStates`.

## Data

- Sessions and entries: ADR-0016 (`TimerSession`, `TimeEntry`), through the `CommandBus` (`StartTimer`, `PauseTimer`, `ResumeTimer`, `StopTimer`), every command undoable.
- Tile times: today's entries per subject, full duration of each (tracked, not by the clock).
- Pinned items, category list, section order, the palette shortcut: native settings, synced under ADR-0010 when sync is on.

## SwiftUI

`MenuBarExtra(content:label:)` with `.menuBarExtraStyle(.window)`; the label is a `TimelineView(.everyMinute)` text with `.monospacedDigit()`. Tiles: `LazyVGrid` of `Button`s with `.keyboardShortcut` only for ⌘1–⌘9 inside the popover. The system-wide shortcut is a registered hot key in the app target (Carbon's `RegisterEventHotKey` needs no permission; no new dependency): question A7 for the architect. The notice: a `safeAreaInset` overlay in the status bar with a timer task that clears it.

## Acceptance

- [ ] From another app: ⌃⌥T, type `res`, ↩ starts 🔬 Research and stops the running timer; the notice offers Keep running; ⌘Z inside the popover restores the earlier state with no gap.
- [ ] ⌥↩ runs two; a third alongside runs three; a fourth alongside stops the oldest and the notice has no button.
- [ ] ⌘T on a selected task row, line header, Lines row, project row, event block and timed task block starts that subject; an event in an unmapped calendar asks for a line.
- [ ] The running pill appears on every row of the running subject and nowhere else; a click pauses and resumes.
- [ ] Nested lines and paused lines have no tile; a paused line is found by typing.
- [ ] No red anywhere; no "missed", "overdue" or "behind" in the popover, the notice, the sheet or the nudges, in English and Russian.
- [ ] The popover fits 380 × 820 with 10 lines, 3 pinned projects and 8 categories; checked in Russian (`MenuBarTimer-RU`).
