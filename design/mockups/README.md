---
status: draft-1
---

# Mockup sources (draft-1)

The exact `.dc.html` source of every artboard on the Claude Design canvas "MoonShine". Use them to read exact values: paddings, widths, colours (`theme()` near the bottom of each file) and the demo arrays. They need the canvas runtime (`support.js`), so they **won't render** when opened directly.

- `Name.dc.html` = light; `Name-Dark.dc.html` = the same component rendered with `dark = true`.
- `Main.dc.html`, `TodayA-Dark`, `TodayB`, `TodayB-Dark` = the two rejected Today directions (A: list-centric, B: dense outline), kept for history. The chosen hybrid is `Today.dc.html`.
- `Palette` and `Settings` embed `Today` as their background.
- `Components.dc.html` renders the light and dark sets side by side.

## Draft-5 (2026-10-28)

`MenuBarTimer`, `TimerStates`, `Today-Time`, `TimeDay`, `TimeWeek`, `TodayReminders`, `Lines-Periods`, `iPhoneLockSwitch` and `iPhoneCapture` (+ `-Dark`, and `-RU` / `-RU-Dark` for `MenuBarTimer`, `Today-Time`, `Lines-Periods`, `iPhoneLockSwitch`) were **authored in the repository**, not generated on the canvas, in the same format: `theme()` copied from the canvas files, `{{ }}` values, `sc-for` / `sc-if`, `dc-import` wrappers. `Today-Time` is `Today` with the draft-5 additions. They can be pasted into the canvas; until a designer redraws them there, the screen specs win, as always.
