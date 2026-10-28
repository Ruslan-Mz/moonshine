---
title: iPhone — capture at the moment (Lock Screen, Live Activity, capture app)
status: draft-5
date: 2026-10-28
platform: iOS 26
slice: 3b (iPhone timer, ADR-0016), or a minimal capture slice before it (question A2, design/README.md § Draft-5)
artboards:
  [
    mockups/iPhoneLockSwitch.dc.html,
    mockups/iPhoneLockSwitch-RU.dc.html,
    mockups/iPhoneCapture.dc.html,
    "+ -Dark variants",
  ]
related:
  - "[[0016-time-tracking-interval-entries-one-timer-sources-reconciled]]"
  - "[[iphone-quick-log]]"
  - "[[iphone-widgets]]"
  - "[[timer-mac]]"
---

# iPhone — capture at the moment (draft-5)

**What works for the owner is capture at the moment, not afterwards** (owner, 2026-10-28). With his phone tracker he uses a Lock Screen widget: one tap switches the current activity. He switches between projects constantly, and logging afterwards from memory is what failed with the workbook. So the **iPhone Lock Screen is the primary capture surface**, with one tap meaning "switch to this" (ADR-0016's switch-by-default); the Mac menu bar is the second (`timer-mac.md`). There is **no import from the phone tracker**: he uses it for one month to measure his real time, then logs directly in MoonShine.

## Surfaces

| Surface                                            | What it does                                                                                 | Drawn in           |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------ |
| **Lock Screen widgets**, four `accessoryCircular`  | one tap = switch to that activity; the running one has a ring and its elapsed time           | `iPhoneLockSwitch` |
| **Live Activity** (Lock Screen and Dynamic Island) | the running activity, elapsed time, pause, stop and **one changing slot**; the switch notice | `iPhoneLockSwitch` |
| **Lock Screen controls** (the two bottom buttons)  | the palette control opens the capture app on Now; the other control stays the owner's choice | `iPhoneLockSwitch` |
| **Capture app**: Now · Day · Settings              | the whole palette, the day's intervals with corrections, the Lock Screen set                 | `iPhoneCapture`    |

Activities are the same as on the Mac (`timer-mac.md` § Activities): lines that are neither nested nor paused, pinned projects and tasks, Life ops categories.

## Which activities are on the Lock Screen

Question A1 for the architect. Options, judged by the one thing that matters on a Lock Screen: a thumb that hits the right place without looking twice.

| Option                                     | Stable places                                  | Covers the switching pairs       | Mis-tap risk                      | Needs                                | Verdict                          |
| ------------------------------------------ | ---------------------------------------------- | -------------------------------- | --------------------------------- | ------------------------------------ | -------------------------------- |
| A fixed set, chosen by the owner           | yes                                            | yes, if he chooses them          | lowest: positions never move      | a setting                            | **chosen for the four widgets**  |
| The most recent                            | no                                             | yes                              | high: places move after every tap | nothing                              | rejected for widgets             |
| The day's planned lines                    | no                                             | partly (work is rarely planned)  | high: changes daily               | the plan and the calendar            | rejected for widgets             |
| **One changing slot** in the Live Activity | the slot's place is fixed, its content changes | the pair he is switching between | low: the label says what it is    | the session history and the calendar | **chosen for the Live Activity** |

So: **four fixed one-tap places** under the clock, and in the Live Activity **one place that changes**, always labelled:

- `↩ Back to 🔬 Research` — the activity that ran before the current one (most switches go back and forth);
- `▶ 🎻 17:00 · 1 h` — five minutes before an event in a line-mapped calendar, the calendar suggestion of ADR-0016, with the event's length as the target. No event title on the Lock Screen.
- Everything else is one tap away: the palette control opens the capture app on **Now**.

## How a switch is confirmed

- The tapped widget gets the ring and its time starts at `0:00`; the previous one loses its ring.
- The Live Activity flips at once to the new activity, `since 15:00`, and its changing slot becomes `↩ Back to 🤖 AI/ML`.
- A haptic where the system allows it from a widget's intent (not checked yet: question A6); the visual confirmation does not depend on it.
- No sound, no banner, no unlock.

## How a mis-tap is undone

- **For about eight seconds** the Live Activity's bottom row becomes the switch notice: `🤖 stopped at 15:00 · 22 min` · `Keep running` · `Undo`.
- **Undo** removes the new session and resumes the stopped ones from the instant they stopped, with no gap: the tap never happened. It sits on the side away from the changing slot, so a second quick tap on `↩ Back to` cannot land on it, and taps on the notice are ignored for its first half second.
- **Keep running** resumes the stopped sessions next to the new one (ADR-0016), within the cap of three.
- **After the notice:** the capture app's **Day** lists the interval; `Change` gives it another activity (the usual fix: the time was right, the label wrong), `Split` cuts it, `Delete` removes it and leaves a gap that `Fill…` gives to a neighbour.
- `Undo` on the notice is new to ADR-0016's notice ("🎻 stopped · Keep running"); on the Mac the same undo is ⌘Z. Question A5 for the architect.

## Layout

**Lock Screen** (`iPhoneLockSwitch`, 402 × 874): date and clock as the system draws them; four circular widgets 72 pt, gap 14, under the clock: emoji (rendered by the system in the Lock Screen's vibrant style, so it reads by shape) and a short name 10 semibold; running: a 3 pt ring and the elapsed time 9.5. The Live Activity (370 wide, radius 26) at the bottom: emoji badge 44 · activity name 17 semibold · `since 14:38` 14 · elapsed 34 semibold, tabular, accent; bottom row 44: the changing slot (flex) · pause · stop. Line and category names are shown; task, project and event titles are hidden unless **Show titles on the Lock Screen** is on (`iphone-widgets.md` § Privacy on the Lock Screen).

**Dynamic Island**: compact = emoji · `0:22`; minimal = emoji; expanded = the Live Activity's content (`iphone-quick-log.md` § Layout).

**Capture app** (`iPhoneCapture`), a tab bar Now · Day · Settings:

- **Now:** the running card (emoji 40 · title · `AI/ML · since 14:38` · elapsed 24 · pause · stop); `Today so far` (the compact `DayBalance`); the palette: sections Lines · Projects · Life ops, tiles four per row, 72 pt high, emoji 24, name 11.5, today's time 10.5; a small lock glyph marks the four on the Lock Screen. One tap switches; a long press offers Start alongside, Pin, Put on the Lock Screen.
- **Day:** newest first, 56 pt rows: time range · emoji · title and line · duration; the running row in accent. A short-switch run is one row (`15 intervals` · the shares) that opens to its intervals. A gap row is hatched with `Fill…`. Swipe left: `Change` (accent) · `Split` · `Delete`, both in neutral fills: **no red**, here as everywhere (CLAUDE.md rule 8).
- **Settings → Lock Screen:** the four places in order, with drag handles and `Change places…`; toggles `Back to the previous activity`, `Events from line-mapped calendars`, `Show titles on the Lock Screen` (off by default), `Haptic on switch`.

## Behaviour

- One tap on a widget or a tile is a plain start (ADR-0016): every running session stops at that instant. Starting alongside is a long press in the app, never on the Lock Screen.
- Pause and stop on the Live Activity act on all running sessions; with two or three running, the Live Activity shows the earliest and `+1` / `+2`.
- Writes go through the `CommandBus` as native data (ADR-0013, ADR-0016); buttons in widgets are allowed before the Act phase, because a timer is not a provider write.
- No streaks, no "missed", no red. Day marks are a quiet line in Now (`🎻 1 h is in`), never a warning.

## A minimal iPhone capture slice before 3b — the design view

Question A2: whether a minimal iPhone capture (Lock Screen widgets and controls, the Live Activity, writing timer sessions) is worth a slice before the full iPhone app of 3b. **From the design side, yes**, and nothing in it is thrown away later:

- **It is where the habit already lives.** The owner's working capture is a Lock Screen widget; Mac-only tracking would leave every switch away from the desk to memory, the failure the workbook showed.
- **It is small.** Three screens (Now, Day, Settings → Lock Screen), four widget configurations, one Live Activity, one control. No Today, Week, Lines or review on the phone.
- **It carries into 3b unchanged.** Now and Day become the Log tab of 3b; the quick-log sheet (`iphone-quick-log.md`) stays for logging afterwards; the practice timer sheet becomes the running card.
- **What it needs is not a design question:** the sessions and entries written on the phone must reach the Mac (ADR-0010 sync of native records, opt-in). The architect decides that.
- **Design risks to check in the slice:** how fast a Lock Screen widget redraws after its intent runs; whether intents run on a locked phone (question A6); the mis-tap rate in the first week (the Day list's `Change` count is the measure).

## SwiftUI

Widgets: WidgetKit `accessoryCircular` with `Button(intent:)` (App Intents, `StartTimerIntent(subject:)`), one configurable intent per place. Live Activity: ActivityKit with `LiveActivityIntent`s for the changing slot, pause, stop, Undo and Keep running; the notice is a state of the activity with a stale date eight seconds out. Controls: `ControlWidgetButton` opening the app on Now. App: `TabView`; Day is a `List` with `.swipeActions` (tints from the tokens, no `.destructive` red role colour).

## Acceptance

- [ ] From the Lock Screen, one tap on a widget switches; the ring, the Live Activity and the Mac menu bar (once synced) agree.
- [ ] `Undo` within eight seconds leaves the day exactly as before the tap, with no gap; `Keep running` leaves both running.
- [ ] A second quick tap on `↩ Back to` never lands on `Undo`.
- [ ] With the setting off, no task, project or event title is readable on a locked phone.
- [ ] Day: `Change`, `Split`, `Delete`, `Fill…` each undo; no red in the swipe actions.
- [ ] Nested lines and paused lines are not offered on the Lock Screen; Life ops categories are.
- [ ] Checked in Russian (`iPhoneLockSwitch-RU`): `Не останавливать` and `Отменить` fit the notice row.
