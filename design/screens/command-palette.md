---
title: Command palette (⌘K)
status: draft-1
date: 2026-10-01
slice: S5
artboards: [mockups/Palette.dc.html, mockups/Palette-Dark.dc.html]
---

# ⌘K palette (draft-1)

## Layout

A scrim over the window (black 18 % light / 42 % dark). The panel is 640 wide, 104 from the window top, centred on the content area, radius 14, with an overlay shadow.

- Input row (52): magnifying glass 18, text field 18 pt, `esc` keycap.
- Results grouped: **Tasks**, **Projects**, **Notes**, **Commands** (group label 11 semibold tertiary). Row 40: icon column 20, title 13.5 with the match in bold, subtitle 11.5 tertiary (trace or path, match in bold), kind or shortcut on the right. The first row is selected by default.
- Footer (32, band background): `↑↓ move · ↵ open · ⌘↵ open in OmniFocus / Obsidian · ⌘K anywhere`.

## Behaviour

- Empty query: recent items + navigation commands (Go to Today ⌘1 … Lines ⌘4, Refresh ⌘R, Settings ⌘,).
- Search over task titles, project names, line names, note titles and paths. Prefix or fuzzy match (queries under 3 characters: case- and diacritic-insensitive substring scan, `i18n.md`), ranked: exact word > prefix > substring; tasks available today rank higher.
- A task with the reminder tag (ADR-0017) is found like any task and labelled `reminder` on the right; ↵ opens it in OmniFocus.
- ↵: task or project → select in the app (or open in OmniFocus if not shown); line → Line detail; note → Obsidian; command → run.
- Max ~12 visible rows; the list scrolls.

## SwiftUI

An overlay in the window (`ZStack` + `.transition(.opacity)`), or an `NSPanel` via `NSViewRepresentable` for HUD behaviour. `TextField` with `.onKeyPress(.upArrow/.downArrow/.return/.escape)`. Results: `List(selection:)` with `Section`s. Store search: SQLite FTS5 table in GRDB (add in S5).

## Acceptance

- [ ] Opens from any view in < 100 ms; typing updates in < 50 ms on demo data.
- [ ] Fully keyboard operable; esc restores focus.

## My take (draft-4)

Drawn as a panel on `TakeStates`. A command `My take: <line>…` (typing `my take vio` finds `My take: 🎻 Violin…`). `↩` turns the palette into a one-line note field for that line; `1`–`4` set an optional direction; `↩` saves a dated **draft** on the current week and closes the palette. Nothing is confirmed from the palette.

## Timer (draft-5)

The in-window route to the timer (Timer (Mac), phase 2); the menu bar popover is the main one (`timer-mac.md`).

- `Start timer: 🎻 Violin` for every activity (lines that are neither nested nor paused, pinned projects and tasks, Life ops categories) and today's tasks: typing `start vio` or just `vio` lists them under **Commands**. `↵` starts (a switch); `⌥↵` starts alongside, and the row reads `Start alongside: 🎻 Violin` while ⌥ is held.
- `Pause timers` / `Resume timers` (⇧⌘T) · `Stop timers` (⌃⌘T) · `Pin to palette: Bach Partita No. 2` · `Show Time view` (⌘6).
- A paused line is found here by name; a nested line is not offered (ADR-0019).
