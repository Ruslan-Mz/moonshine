# MoonShine — Claude Design prompt: calendar (design draft-3)

Use in the same Claude Design project, new page "Calendar · draft-3". Attach or re-read: `design/README.md`, `design/principles.md`, `design/tokens.md`, `design/copy.md`, `design/demo-data.md`, `design/screens/today.md`, `week.md`, `month.md`, `settings.md`, `ipad-week.md`, `ipad-shell-today.md`, `iphone-today.md`, `iphone-widgets.md`.

---

Add **calendar events** to the MoonShine design (draft-3). Events come from the system calendars (EventKit) on each device. They are **read-only**. MoonShine never creates or edits events in this round.

## Why

Tasks alone give a false picture of a day: Today can list ≈ 11 h of tasks on a day with 5 h of fixed commitments. The calendar adds two things:

1. **Fixed commitments are visible** next to tasks, at every scale (day, week, month).
2. **Free time is a fact**: how many hours of the day or week are already taken.

## Rules (hard requirements)

- An event is **not a task**: no checkbox, no estimate, no trace chip. It has a time range, a title and a calendar.
- **No amber and no red on events.** Amber stays reserved for tasks with a real due date. An event that has passed is dimmed, nothing more.
- **Calendar colour** appears only as an 8 pt dot or a 3 pt leading bar, desaturated to sit with the tokens. No filled coloured blocks.
- Busy and free time are **plain facts**: `4 h 30 min in calendar · ≈ 6 h free`. No judgement words ("overbooked", "too much", "busy day"). Follow `copy.md` and the forbidden-word lists.
- The app works fully **without calendar access**. No nagging; one quiet row offers to connect.
- Event titles are user data: any language, any script, never translated. Same mixed-language and RTL rules as task titles (`i18n.md`).
- Touch targets ≥ 44 pt on iPad and iPhone. Light and dark for every artboard.

## Screens

### 1. Mac — Today

Propose **two variants** for showing today's events, then recommend one:

- **A · Agenda section.** A section "Fixed today" above the line sections (below Anchors and Top 3): rows `09:30–10:00 · Team stand-up · ● Work`. The next event is marked `in 40 min`.
- **B · Day rail.** A slim vertical timeline (06:00–24:00) in the right rail or along the left edge of the main column: event blocks, free gaps, a "now" rule. The task list stays a list.

Both: the toolbar subtitle gains the fact `3 events · 4 h 30 min in calendar · ≈ 6 h free`, next to the existing `23 open · ≈ 11 h 15 min est.`. Show how the two numbers sit together without implying a verdict.

An event from a calendar mapped to a line (see Settings) shows the line emoji: `17:00–18:00 · Violin lesson · 🎻`.

### 2. Mac — Week

- Events sit in each day column **above** the task cards, visually lighter than tasks: time + title + calendar dot.
- **All-day and multi-day events** are bars across the top of the columns (example: a two-day trip Sat–Sun).
- Per-day caption under the day header: `3 h in calendar`.
- **Weekly review mode**: add a section "Fixed next week" (events of the next ISO week, grouped by day) next to "Real due dates next week".

### 3. Mac — Month

- All-day / multi-day bars at the top of day cells.
- Timed events: a small count or neutral marks, clearly different from the per-line activity dots.
- The selected-day list shows events first, then tasks.

### 4. Mac — Settings → Calendars (new screen)

- Access state: `Not connected` (button `Connect calendars…`) · `Connected` · `Access denied` (button `Open System Settings`).
- Calendars grouped by account, each row: colour dot, name, toggle **Show**, toggle **Counts as busy**, optional **Line** picker (map a calendar to a line, e.g. "Music lessons" → 🎻 Violin).
- Note under the list: `Events stay on this device. They are not synced by MoonShine.`
- Demo mode shows invented calendars with a `Demo data` badge.

### 5. Mac — Line detail

For a line with a mapped calendar: a small "Upcoming" list (next 3 events).

### 6. iPad — Week (planning studio)

- Same event layer as Mac Week, sized for touch.
- While a task card is being dragged, each day column shows its free time (`≈ 5 h free`) as part of the drop target.
- Compact width (Split View ½ and ⅓): events appear inside each day section, before tasks.

### 7. iPhone — Today, widgets, quick log

- Today: a **Next event** row at the top: `15:00 · Violin lesson · in 40 min`, then the rest of the day's events collapsed (`+ 2 more today`).
- Widget (small and medium): next event + next anchor.
- Quick log: when an event from a line-mapped calendar has ended, the Log sheet offers a first row `Log 60 min to 🎻 Violin — from "Violin lesson"`. One tap fills the form. No notification in this round.

### 8. Planning board and forecast (future, direction only)

- The weekly load card shows calendar time as a separate neutral segment: `capacity 22 h/week · 6 h in calendar this week`.
- A multi-day trip appears on the timeline as a neutral band labelled with its title; forecasts that move because of it say `moves +1 week (trip 3–9 Nov)`.

## States to draw

- No access yet (Today and Week look complete without events, plus the quiet connect row).
- Access denied.
- A day with no events.
- Two overlapping events.
- A tentative event (hatched outline) — declined events are hidden.
- An event with a private or empty title → `Busy`.
- An event in another time zone (shown in local time, original zone in the detail).
- Russian UI variant of Today and Week; one mixed-language artboard (event titles in RU, IT, JA, HE).

## Demo data (invented — add to `design/demo-data.md` as "Draft-3: calendar")

Week 40, Mon 28 Sep – Sun 4 Oct 2026. Today is Thu 1 Oct. Calendars: Work, Family, Music lessons (→ 🎻 Violin), Personal.

- Thu 1 Oct: 09:30–10:00 Team stand-up (Work) · 13:00–14:00 Lunch with Marta (Personal) · 17:00–18:00 Violin lesson (Music lessons) · 18:30–20:00 Parents' evening at school (Family). → `4 events · 4 h in calendar`.
- Other days: 2–3 events each; Tue has two overlapping events; Fri has one tentative event.
- Sat 3 – Sun 4 Oct: all-day "Weekend in Sigulda" (Family), two days.
- Next week (for the weekly review): 5 events, including one early-morning flight.

Keep every number on the artboards derivable from this list.

## Deliverables

- Artboards, light and dark: Today A and Today B, Week, Week review, Month, Settings-Calendars (three access states), iPadWeek with events (incl. drag state), iPadSplitHalf with events, iPhoneToday with the Next event row, iPhoneWidgets, iPhoneLog with the event suggestion, the "states" sheet.
- Components: `EventRow`, `EventBlock` (rail), `AllDayBar`, `FreeTimeFact`, `NextEventRow`, `CalendarDot`. Add them to `design/components.md`.
- Specs: a "Calendar (draft-3)" section in each affected `design/screens/*.md` and a new `design/screens/settings-calendars.md`, same structure as the existing specs (Layout · Data · Behaviour · SwiftUI · Acceptance).
- Copy: new strings in `design/copy.md`, EN and RU.
- `design/README.md`: "Draft-3 changes" and open questions. State your recommendation for Today A vs B and why.
