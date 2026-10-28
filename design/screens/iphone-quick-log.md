---
title: iPhone — Quick log, practice timer, Live Activity
status: draft-2
date: 2026-10-01
platform: iOS 26
artboards:
  [
    mockups/iPhoneLog.dc.html,
    mockups/iPhoneTimer.dc.html,
    mockups/iPhoneLock.dc.html,
    mockups/iPhoneIsland.dc.html,
    "+ -Dark variants",
  ]
related: ["[[platforms]]"]
---

# iPhone — Quick log and practice timer (draft-2)

The quick log and the timer write **time entries** (MoonShine-native data, `platforms.md`). They never write to OmniFocus or the vault.

## Layout

**Quick log sheet** (from the Log tab or the "+" in Today; 700 pt, large detent, grabber):

- Nav row: Cancel · `Log time` · Save.
- `LINE · recent first`: horizontal capsule chips (44 high); the selected one is filled with the accent.
- `MINUTES`: chips 10 · 15 · 20 · 30 · 45 · 60 in a 3 × 2 grid (48 high) + a stepper row (±5 min).
- `When` (default now, rounded to 5 min) and an optional note.
- Primary button: `Save 20 min to 🎻 Violin` (full width, 54). Secondary: `Start practice timer`.

**Practice timer sheet**: line + current next action, elapsed `18:42` (76 pt, tabular digits), `started 17:58 · running`; Pause (76 circle) and Stop & save (76, accent). Caption: stopping saves the session as time entries, one per interval between pauses; the timer continues on the Lock Screen and in the Dynamic Island.

**Live Activity**:

- Lock Screen: emoji badge, `Violin · practice`, the next action, elapsed time in the accent colour; Pause and Stop & save buttons (44). The next action is a task title: redacted on the Lock Screen by default (`.privacySensitive()`), shown only with the setting **Show titles on the Lock Screen** (off by default; `iphone-widgets.md` § Privacy on the Lock Screen).
- Dynamic Island: compact (emoji · `18:42`), minimal (emoji only), expanded (title, subtitle, time, Pause / Stop & save).

## Data

`TimeEntry { day, start?, end?, minutes, subject, note, source: manual | timer | calendar, session? }` (ADR-0016). The subject is a line, or a task or a project with its line. Recent lines = last 7 days of entries, then foundation lines, then the vault order. A timer session gives one entry per interval: Pause closes an interval and Resume opens the next, so a paused session gives several entries.

## Behaviour

- One-hand: all controls in the lower two thirds; Save is reachable with the thumb.
- Up to three timers at once (ADR-0016, amended 2026-10-16): a plain start switches and never blocks: every running timer stops at that instant and a quiet one-line notice shows for about eight seconds (`🎻 stopped · Keep running`); `Keep running` resumes them from the instant they stopped, with no gap, within the cap. Starting alongside stops nothing while fewer than three run. With three running, an alongside start stops the oldest and a plain start stops all three; the notice reads `🎻 stopped (three at most)` with no button.
- No streaks. Targets and day marks are optional and shown as neutral facts (ADR-0016). The line's rhythm updates after save.

## SwiftUI

`.sheet` with `.presentationDetents([.large])`; chips as `Button`s in `ScrollView(.horizontal)` / `Grid`; `Stepper`. Timer: `TimelineView(.periodic)` or `Text(timerInterval:)`. Live Activity: ActivityKit `ActivityAttributes` + WidgetKit `ActivityConfiguration` with `DynamicIsland { expanded; compactLeading; compactTrailing; minimal }`, App Intents for Pause and Stop.

## Acceptance

- [ ] A log takes ≤ 3 taps for the common case (line from recents, chip, Save).
- [ ] The timer survives app termination (Activity + persisted start time).
- [ ] The Live Activity uses no red; times use tabular digits.

## Calendar (draft-3)

Artboards: `iPhoneLog-Cal`, `iPhoneLog-Cal-Dark`.

When an event from a **line-mapped** calendar has ended (today, within the last 3 hours, and no time entry overlaps it), the Log sheet offers a first row: `Log 60 min to 🎻 Violin` / `from "Violin lesson" · ended 18:00`. One tap fills the form (line, minutes = event duration, When = the event's time range); the note stays empty: the entry keeps the event's start, end and line, never its title, attendees, id or calendar name (ADR-0016, owner 2026-10-09). The user still presses Save and the entry gets source `calendar`. No notification in this round.

## My take (draft-4)

Artboards: `iPhoneTakeSheet`, `iPhoneTakeSheet-Dark`. The iPhone is the main place to capture a draft at any moment.

### Layout

The Log sheet gets a segmented control at the top: `Log time | Note for my take`. In the second mode (`TakeDraftSheet`, about 610 pt high):

1. `Cancel` · title `Note for my take` · `Save` (dimmed until there is text).
2. `LINE · recent first`: the same line chips as in Log time, the most recent line preselected (44 pt).
3. One text field, focused: `One line: what happened?`
4. `DIRECTION · optional`: four buttons in a row (56 pt high, mark above the word). Tapping the selected one clears it.
5. Caption: `Saved as a draft for week 40, dated Thu 1 Oct. You confirm it at the weekly review — or leave it; nothing expires.`
6. Primary button `Save draft to 🎻 Violin` (54 pt).

### Behaviour

- Common case in three taps with one thumb: open the sheet (Log tab, or `Note for my take` on a line), type, `Save`. The sheet opens in the mode used last; from a line glance the line is fixed.
- A saved note appears at once as a draft mark on the line's current week and in its take history with the day it was written. A direction is optional; a note without one shows the note-only mark.
- Nothing is confirmed on the iPhone; confirming happens only in the weekly review (Mac or iPad).

### SwiftUI

Second `Picker(.segmented)` state of the existing sheet; `TextField` with `.focused`; direction buttons in a `Grid` with `.accessibilityAddTraits(.isSelected)`.

### Acceptance

- [ ] Reachable with one thumb; every control ≥ 44 pt.
- [ ] Saving with an empty direction works.
- [ ] No reminder, badge or notification is created by a draft.

## Draft-5 — capture at the moment

The Lock Screen widgets, the Live Activity's changing slot and switch notice, and the capture app (Now, Day, Lock Screen set) are specified in `iphone-capture.md`. In 3b, Now and Day become the Log tab; this quick-log sheet stays for logging afterwards, and the practice timer sheet becomes Now's running card.
