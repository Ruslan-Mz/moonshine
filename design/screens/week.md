---
title: Week
status: draft-2
date: 2026-10-01
slice: S5
artboards: [mockups/Week.dc.html, mockups/Week-Dark.dc.html]
---

# Week (draft-2)

## Layout

Toolbar: `Week 40`, subtitle `28 September – 4 October 2026 · ISO week`; ‹ Today › buttons. No right rail.

1. **Line strip** (top): legend (rhythm / progress swatches, "Week in progress — Mon to Thu"), then one cell per line in a 9-column grid. Each cell shows emoji + name, `■ 4  avg 4.0` (rhythm) and `■ 1  avg 1.0` (progress) — Violin, W40; averages over the previous 4 full weeks (W36–W39), derived from `demo-data.md`. Plain numbers, no colour for up or down. "—" where a series doesn't apply (a line without repeating tasks has no rhythm).
2. **Days**: 7 equal columns Mon–Sun. Header: weekday + date (today: filled accent circle, column tinted with `selection`) + a summary (`5 done` for past days, `≈ 2 h 50 min` estimated for future days). Cards: checkbox + title (2 lines max), then line emoji + name, estimate and a due badge when the task is a deadline (deadline rule, `settings.md` § Deadlines) due in this week; a due date in this week that is not a deadline is plain secondary text (`due Fri 12:00`). More than ~6 → `+ N more` link (opens Today-style list of that day).
3. **No plan tray** (bottom, 188 high): `No plan` + caption + count; a 4-column grid of compact cards (emoji, title, estimate). Caption on the right: "Drag onto a day to plan — comes with the Act phase".

## Data

- Placement: effective planned ?? defer ?? due. Each task appears once.
- Past days show completed tasks (checked, **dimmed**) and tasks still open from that day (resolved open question, draft-2).
- No plan: available tasks in **active** lines with no planned, defer or due date (mirrors the "Без плана" perspective).
- Strip: per line, this week's rhythm and progress vs the mean of the previous 4 ISO weeks (Stats service).
- Tasks with the reminder tag (ADR-0017, S4 bridge) are in no day column, no tray and no strip count (`today.md` § Reminders).

## Weekly review mode (draft-2, S5, first to cut)

**Cut from phase 1 (owner, 2026-10-30;** `docs/specs/phase-1-see.md`, Goal**).** Kept here as the design for a later phase.

The owner's Sunday review, inside Week. Toggle `Weekly review` (toolbar, ⇧⌘R). The day grid shrinks to the top half; the bottom half becomes a checklist of facts, each with "Open":

1. Quiet lines (active, ≥ 14 days) — with the suggested next step.
2. No plan tray (already on this screen).
3. Projects in active lines with **no next action** (`no next action`).
4. Next week's real due dates.
5. Links: month note, quarter note.

Each section has a "seen" circle (draft-2 mockup). **Phase 1: the state is ephemeral** — view state for the current window session (`@SceneStorage`, keyed by ISO week), not in the store; no new entity or `Store` API in S5. Stored "seen" marks are MoonShine-native data and arrive with the phase-2 native tables (synced in 3b, ADR-0010). No counter (`3 of 5`), no scores, no completion percentage for the review itself.

## SwiftUI

`VStack { LineStrip; HStack(spacing: 0) { ForEach(days) { DayColumn } }; NoPlanTray }`. DayColumn = `ScrollView` + `LazyVStack`. Tray = `LazyVGrid(columns: 4 flexible)`. Use `VSplitView` if the tray should be resizable.

## Acceptance

- [ ] ISO week, Monday first, local time zone.
- [ ] Due badge only for deadlines due inside the week; amber only there. A due date that is not a deadline is plain secondary text.
- [ ] With the rule `due date + tag`, the untagged demo task due Fri 12:00 shows `due Fri 12:00` in plain text and no amber.
- [ ] Averages shown as numbers with "avg"; no red or green, no arrows.
- [ ] Tray lists only active lines' undated available tasks.

## Calendar (draft-3)

Artboards: `Week-Cal`, `Week-Cal-RU`, `Week-CalReview` (+ `-Dark`).

- **Toolbar subtitle** adds `17 events · 15 h in calendar`.
- **All-day and multi-day events**: `AllDayBar`s in a row above the day columns, spanning their days (`Weekend in Sigulda · all day · Family` across Sat–Sun).
- **Per-day caption** under the day header: `2 h 30 min in calendar`.
- **Events in each column, above the task cards**, lighter than tasks: no card, a 3 pt calendar bar, time (11 pt, tertiary) and title (12 pt); the line emoji for mapped calendars. Past events dimmed; the next one carries `in 40 min`; `overlap` and `tentative` tags; a tentative event has a dashed, hatched outline. A hairline separates events from tasks. With events on, a column shows at most 4 task cards, then `+ N more`.
- **No access**: one quiet row above the columns (same wording as Today).
- **Weekly review**: a section **Fixed next week** (events of the next ISO week: day · time · title · calendar) in the third column under "Real due dates next week"; Notes move under No plan. It has its own "seen" circle; no counter.

**Data.** Same busy rule as Today, per day. Week total = sum of the days' busy time; the event count includes each multi-day event once. Where Week shows free time (the iPad drop target), a future day uses its whole day window; today uses what remains of it, the same number as Today.

**SwiftUI.** All-day row: a `Grid` row with `gridCellColumns(span)`. Day column: `ForEach(events) { EventRow(.compact) }` before the task cards.

**Acceptance.**

- [ ] Events are visually lighter than task cards and never draggable.
- [ ] Tue shows three events, two tagged `overlap`, and `2 h 30 min in calendar`.
- [ ] Fri's tentative event is hatched and not counted (`2 h 30 min`).
- [ ] The Sat–Sun bar spans exactly two columns.

## My take (draft-4)

Artboards: `Week-Take`, `Week-Take-RU` (+ `-Dark`). iPad: `ipad-week.md` § My take. The model, the names and the open questions are in `README.md` § Draft-4; components in `components.md` § Take components; strings in `copy.md` § My take strings.

The weekly review gains a section **How did each line go?** where the owner sets his take per line: a direction (`Leap · Rise · Steady · Dip`) and a one-line note. It is his judgement, shown next to the measured facts and never mixed with them.

### Layout

- **The review has two steps**, a segmented control in the review bar: `1 · Facts` (the existing sections, in this order: quiet lines, no next action, no plan, real due dates next week, fixed next week, notes) and `2 · My take`. The takes come last: they are a judgement made after looking at the facts. Caption next to the control: `Nothing here is scored.`
- In step 2 the day grid collapses to one row of **day pills** (`Mon 28 · 5 done`, today tinted), the line strip and the facts panel are hidden, and the section fills the window.
- Section header: `How did each line go?` 15 bold + `My take · set only by you · optional` + the legend (four marks with their words, `dashed = draft`).
- Columns: Line 160 · This week, measured 270 · My take 298 · Note flex (≈ 280 at 1440) · action 100. Row 40.
- **Rows**: Foundation first, then Active this season, both in vault order. Maintenance lines are collapsed under `Maintenance · 1 line`. Lines paused on purpose are not listed.
- **Line**: emoji + name; a foundation line carries its floor (`floor 3 h/day`) under the name.
- **This week, measured**: rhythm and progress as two separate items, each with its colour square and 4-week average: `■ 4 sessions · avg 4.0   ■ 1 task · avg 1.0`. A series that does not apply to the line is left out, not shown as zero: 🧘 Core practice reads `■ 8 sessions · avg 12.0`, 🤖 AI/ML reads `■ 3 tasks · avg 3.0`. Quiet line: moon + `quiet for 29 days`. New line: `no activity yet`. With time data (phase 2) a third item is added: hours against the weekly budget.
- **My take**: `TakeControl`, four segments (mark + word), 72 × 24 each. Nothing selected = no take.
- **Note**: a one-line field, placeholder `What happened? One line, optional`. The focused row gets the selection tint and an accent ring; its note field grows to fit the text.
- **A row with drafts has two lines.** First line: the drafts, each with its day — `Mon 28 Sep · Bars 9–16 clean at ♩ = 60 · Rise`, `Wed 30 Sep · Teacher asked for the Sarabande next · no direction yet` — with dashed marks. Second line: `prefilled from 2 drafts →`, then the control and the note prefilled from them (the latest direction that was given; the notes joined with `·`) and the button `Confirm`. The prefilled segment has a dashed outline until it is confirmed.
- **A confirmed row** shows the segment raised, the note, and `✓ set Sun 4 Oct` in the action column. Changing it is the same tap; the date updates.
- Bottom line: `↑↓ line · 1–4 direction · ↩ note · ⌘↩ confirm`.

### Data

- `Take` (confirmed): line (or project) · ISO week · direction (`leap | rise | steady | dip`) · note? · `setAt`. One per (line, week); the latest value wins and is shown with its date.
- `TakeNote` (draft): line (or project) · ISO week · `writtenAt` · text · direction?. Any number per (line, week). On confirm the dated notes are **kept as data under the take** and shown when its take-history row is opened. A note added to a week that is already confirmed is stored under that take; the take stays confirmed.
- A confirmed take needs a direction; a note without one stays a draft.
- **Set only by the owner** means the content comes from the owner's own words. The assistant (phase 4) may file a dictated note as a draft; it never chooses a direction the owner did not say, and never confirms (ADR-0013).
- A project take is independent of the line take: it never rolls up to the line and never replaces it.
- Both are MoonShine-native data (not OmniFocus, not the vault) and sync like other native data (ADR-0010: draft notes merge append-only; a confirmed take is last-writer-wins per (subject, week)). Storage arrives with My take's own slice, cut from phase 2 (owner, 2026-11-01); phase 1 has no code for takes. They are never computed, suggested, averaged or counted.
- A week has no take, drafts only, or one confirmed take. No take is a valid state and stays blank.
- Rows come from the line list (tier, vault order); facts from the Stats service (this week and the mean of the previous four ISO weeks).

### Behaviour

- **The place decides, not the day.** In the weekly review, choosing a direction (one tap or `1`–`4`) confirms the week's take at once, on any day of the week and on a row with or without drafts; the note is optional and saved on blur or `↩`. Everywhere else (Line detail, the iPhone and iPad capture sheet, ⌘K) the same action saves a draft.
- On a row with drafts, `Confirm` (`⌘↩`) accepts the prefilled direction and note as they are; the owner can edit the note first. A row whose drafts carry no direction cannot be confirmed until a direction is chosen. The dated drafts stay under the confirmed take.
- Keyboard: `↑` `↓` move between lines, `1`–`4` set the direction, `↩` opens the note, `⌘↩` confirms, `⌫` on a selected segment clears the take.
- **No "Confirm all drafts".** It would save two or three taps a week and invites confirming without reading; `⌘↩` then `↓` already confirms a row in two keys.
- **Nothing reminds.** No counter of lines without a take, no badge on the review toggle, no "seen" circle for this section. Drafts of earlier weeks are not listed in later reviews; they stay drafts and are reachable from the line's take history and the quarterly review, or by stepping back to their week (`‹`).
- Stepping to a past week shows that week's takes in the same list; rows are editable there too.
- Any take or note **resets the quiet count** from its date (the date the note was written or the take was set, never a future date), so a line with a take for the week is not listed under "Quiet lines" in step 1.

### SwiftUI

`Picker`-like custom control: `HStack` of four `Button`s inside a `.accessibilityRepresentation { Picker }` so VoiceOver reads "My take, Violin: Rise, draft". Rows in a `List`/`Table` with `.onKeyPress` for `1`–`4`; note field `TextField(axis: .vertical)` with `.lineLimit(1...4)`. Marks: SF Symbols `sparkle` / `arrowtriangle.forward.fill` / `circle.fill` / `arrowtriangle.backward.fill` (outline variants with a dashed stroke for drafts) or the custom paths from the mockups.

### Acceptance

- [ ] Rhythm, progress and the take are three separate things in a row; no sum, average, rank or percentage of takes exists anywhere.
- [ ] A foundation line with no one-off tasks reads well with rhythm + take only (no `0 tasks`, no `—`).
- [ ] `Dip` looks exactly like the other three segments; no red, no amber, no warning symbol.
- [ ] A draft and a confirmed take are distinguishable without colour (dashed vs solid).
- [ ] No take → nothing is drawn and nothing is asked. The section has no counter and no reminder.
- [ ] Setting a take is one tap or one key; the note is never required.
- [ ] Notes show as written in any script; checked with a Russian and a mixed-script note. The section is checked in Russian.
