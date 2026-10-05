---
title: MoonShine — design hand-off
status: draft-2
date: 2026-10-01
source: Claude Design canvas "MoonShine" (https://claude.ai/code/artifact/7460e302-ab39-4778-93bb-a7a04493b244)
related:
  - "[[VISION]]"
  - "[[phase-1-see]]"
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
---

# MoonShine — design hand-off (draft-2)

> **Status: draft-2** (specs refined against the owner's planning system — where a spec and a mockup differ, **the spec wins**). Draft-1: These are the first design specs for implementing the views. Expect changes. If a spec here conflicts with `docs/VISION.md`, `docs/specs/phase-1-see.md` or an ADR, **those documents win**. Flag the conflict; don't silently pick one.

## What is here

| File                              | Purpose                                                                                                                                                    |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `principles.md`                   | Visual direction, layout grid, tone rules as UI constraints                                                                                                |
| `tokens.md` / `tokens.json`       | Colours (light/dark), type scale, spacing, radii. JSON is machine-readable                                                                                 |
| `copy.md`                         | Wording rules and the canonical strings                                                                                                                    |
| `components.md`                   | Reusable views: task row, trace chip, line header, due badge, sparkline, quiet-line card, states, status bar                                               |
| `screens/*.md`                    | One spec per screen: layout, data, behaviour, SwiftUI mapping, acceptance checks                                                                           |
| `demo-data.md`                    | The invented dataset used in the mockups (a seed for `DemoVault` fixtures)                                                                                 |
| `i18n.md`                         | Languages: UI waves (EN+RU now, 13 later, RTL/CJK-ready), switching, plurals, and multilingual content (rendering, detection, search)                      |
| `screens/settings-calendars.md`   | Draft-3: calendar access, per-calendar settings, day window (see "Draft-3 changes — calendar")                                                             |
| `platforms.md`                    | Mac = hub, iPad = planning studio, iPhone = capture & glance; design rules for touch; sync consequence                                                     |
| `prompts/claude-design-mobile.md` | Prompt for the iPad & iPhone design round (same Claude Design project, new page)                                                                           |
| `tone-glossary.md`                | Tone terms and banned words per language                                                                                                                   |
| `mockups/*.dc.html`               | Exact source of every artboard: values for paddings, sizes and colours. **Reference only.** Design Component format, so it won't render outside the canvas |

## Screens

| Screen                       | Spec                              | Phase                                                    | Artboards                             |
| ---------------------------- | --------------------------------- | -------------------------------------------------------- | ------------------------------------- |
| Today                        | `screens/today.md`                | 1 (S4)                                                   | `Today`, `Today-Dark`                 |
| Lines                        | `screens/lines.md`                | 1 (S4)                                                   | `Lines`, `Lines-Dark`                 |
| Line detail                  | `screens/line-detail.md`          | 1 (S4)                                                   | `LineDetail`, `LineDetail-Dark`       |
| Week                         | `screens/week.md`                 | 1 (S5)                                                   | `Week`, `Week-Dark`                   |
| Month                        | `screens/month.md`                | 1 (S5)                                                   | `Month`, `Month-Dark`                 |
| ⌘K palette                   | `screens/command-palette.md`      | 1 (S5)                                                   | `Palette`, `Palette-Dark`             |
| Settings + status bar        | `screens/settings.md`             | 1 (S4)                                                   | `Settings`, `Settings-Dark`           |
| Project forecast             | `screens/forecast.md`             | **future** (2–3)                                         | `Forecast`, `Forecast-Dark`           |
| Planning board               | `screens/planning-board.md`       | **future** (2–3)                                         | `Board`, `Board-Dark`                 |
| Weekly review (mode of Week) | `screens/week.md` § Weekly review | 1 (S5, first to cut)                                     | `Week-Review`, `Week-Review-Dark`     |
| Quarterly review             | `screens/quarterly-review.md`     | **R1** — own slice, before the Q4 review (by 2026-12-28) | `QuarterReview`, `QuarterReview-Dark` |

Each `*-Dark` artboard is a wrapper that renders the light one with `dark = true`. The real values are in the light file's `theme()` function.

## How to use this (for Claude Code)

1. Read `principles.md`, `copy.md` and `tokens.md` once. They apply to every view.
2. For a slice, read the matching `screens/*.md` and the `components.md` entries it references.
3. Use system semantic colours (`.primary`, `.secondary`, `.separator`, fills) wherever they exist. Custom tokens (due amber, rhythm, progress) live in an asset catalog with light/dark variants.
4. Build views against `DemoVault` first. `demo-data.md` lists the data the mockups assume.
5. Before closing a slice, run the screen's **Acceptance** checklist and the tone review in `copy.md`.

## Decisions taken in the design round

- Direction: **hybrid**. Dense, one-line rows with columns (from option B) inside calm typography and an airy right rail (from option A). Options A and B stay on the canvas page "Today directions" for history.
- Rhythm and progress are two series with two colours (blue / teal, checked for colour-blind separation) and are never summed.
- Month uses a fixed-order **dot strip per day** (one dot slot per line) plus a soft tint for total activity.
- A new line state appears in the data: an active line with no completions shows "no activity yet" (example: 🇯🇵 Japanese).
- Settings: the spec recommends a native `Settings` scene (⌘,). The canvas draws it as a sheet so it is visible next to the window.

## Resolved in draft-2

- Life ops expansion is **remembered** (`@SceneStorage`).
- Week shows **completed tasks on past days, dimmed**.
- Month **opens on the current month**; ⌘← / ⌘→ step months.
- Sidebar line list is **grouped by tier** (Foundation · Active · Maintenance · Paused), collapsible — same order as Lines.

## Draft-2 changes (from the owner's planning system)

1. **Tiers instead of domain blocks** as the primary grouping: Foundation (spine, has a daily floor) → Active this season → Maintenance → Paused on purpose ("Not in focus"). Domain block becomes a secondary label. → `principles.md`, `screens/lines.md`.
2. **Today supports the daily ritual "3 priorities + 5 anchors"**: an Anchors strip (`anchor`-tagged tasks) and a Top 3 section (flagged), foundation lines first. → `screens/today.md`, `components.md`.
3. **Quarter focus card** in the Today rail (current quarter's artifacts). → `screens/today.md`.
4. **Weekly review mode** inside Week (Sunday ritual), first to cut. → `screens/week.md`.
   4b. **Quarterly review** screen (R1, read-only; decisions stay in the quarter note in Obsidian). → `screens/quarterly-review.md`.
5. **Month context chips** slot reserved for the hours tracker's "where I was" rows (phase 2). → `screens/month.md`.
6. **Languages**: UI in waves (EN+RU in phase 1, then LV/IT/DE, up to 13 incl. RTL and CJK), in-app switch; **multilingual content** rendered, detected and searched correctly in any script. → `i18n.md`, `tone-glossary.md`, `copy.md`, `screens/settings.md`, ADR-0009.

## Contract changes these need (vault contract v0.2, `docs/discovery/vault-contract.md`)

- Budget note `lines:` gains optional `foundation: true` and `floor_h_day: <number>` (foundation lines have a floor instead of `budget_h_week`).
- OmniFocus: the meta tag `anchor` (under the work-type group) marks anchors; flagged = priority. Both already exist in the snapshot (tags by id, `flagged`).
- Quarter note with `scale: quarter` and an `artifacts:` list (same shape as the year note) feeds the Quarter focus card.
- Optional `language: <BCP-47>` on a line (language lines) — parsed in S3b; a detection hint and, later, per-language exposure.
- Quarter note `artifacts:` items: optional `done: <date>` and `carried_to: <YYYY-Qn>` (quarterly review outcome) — **parsed from R1**; fixtures may contain them earlier.
- Budget note: optional `active_lines: {min, max}` — the owner's "3–5 active lines" rule as data — **parsed from R1**.

## Follow-up for Claude Design (to bring the mockups to draft-2)

Paste into the same Claude Design project:

```
Update the MoonShine artboards to design draft-2 (read design/README.md "Draft-2 changes", principles.md, i18n.md, screens/today.md, screens/lines.md):
1. Today: add the Anchors strip and the "Top 3 today" section above the line sections; foundation lines (🧘 Core practice, 💪 Calisthenics) first; Quarter focus card at the top of the right rail. Use design/demo-data.md "Draft-2 additions".
2. Lines: group by tier (Foundation · Active this season · Maintenance · Not in focus — on purpose, collapsed); domain block as a small label under the name; foundation rows show "floor 3 h/day" in the Budget column.
3. Sidebar: lines grouped by the same tiers.
4. Settings: add General → Language (System · English · Русский).
5. Add Russian variants of Today and Lines (artboards Today-RU, Lines-RU) using the RU strings in copy.md, to check text length and plurals.
6. Add one artboard Today-Mixed where task titles are in several languages and scripts (Russian, Italian, German, Chinese, Hebrew) to check glyphs, bidi and truncation, and one Today-RTL in a Hebrew UI to check mirroring.
Keep all tone rules. Light and dark.
```

## iPad & iPhone (draft-2)

**Primary iPad: 11″** (landscape 1210 × 834 pt, portrait 834 × 1210 pt); 13″ gets the same layouts with more room. Roles from `platforms.md`: **iPad = planning studio**, **iPhone = capture & glance**, Mac = hub. Same tokens, tone rules, copy and demo data. Every artboard exists in light and dark (`*-Dark`). Canvas pages: "iPad · planning studio" and "iPhone · capture & glance".

| Screen                                 | Spec                               | Artboards                                                                                |
| -------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------- |
| iPad shell + Today                     | `screens/ipad-shell-today.md`      | `iPadToday`, `iPadToday-Mixed` (RU, IT, DE, ZH, HE, LV titles)                           |
| iPad Week — planning + drag            | `screens/ipad-week.md`             | `iPadWeek`, `iPadWeek-RU`                                                                |
| iPad Weekly review                     | `screens/ipad-week.md`             | `iPadWeekReview` (landscape), `iPadWeekReviewPortrait` (swipeable cards)                 |
| iPad Project forecast (future)         | `screens/ipad-forecast.md`         | `iPadForecast` — the effort slider is live in Play mode                                  |
| iPad Planning board (future)           | `screens/ipad-planning-board.md`   | `iPadBoard`                                                                              |
| iPad Quarterly review                  | `screens/ipad-quarterly-review.md` | `iPadQuarter`, `iPadQuarterPortrait` (note as sheet)                                     |
| iPad Split View / compact / 11″        | `screens/ipad-split-view.md`       | `iPadSplitHalf`, `iPadSplitThird`, `iPadSplitThirdForecast`, `iPad11Today`, `iPad11Week` |
| iPad Pencil & pointer                  | `screens/ipad-interactions.md`     | `iPadInteractions`                                                                       |
| iPhone Today                           | `screens/iphone-today.md`          | `iPhoneToday`, `iPhoneToday-RU`, `iPhoneToday-XXL`                                       |
| iPhone Quick log, timer, Live Activity | `screens/iphone-quick-log.md`      | `iPhoneLog`, `iPhoneTimer`, `iPhoneLock`, `iPhoneIsland`                                 |
| iPhone Widgets                         | `screens/iphone-widgets.md`        | `iPhoneWidgets`                                                                          |
| iPhone Line glance                     | `screens/iphone-line-glance.md`    | `iPhoneLine`                                                                             |

Mock conventions: no status bar is drawn (the system draws it). The iPhone XXL artboard approximates Dynamic Type by scaling the content ×1.35 with wrapping on; the real build uses Dynamic Type. The forecast slider uses a stand-in model (p50 = remaining 18 h ÷ h/week), not the engine.

### Open questions (iPad & iPhone)

1. ~~**Sync ADR**~~ **Resolved: ADR-0010** — CloudKit private database via `CKSyncEngine`, the Mac is the only importer, native data multi-writer; sync is opt-in, off by default, with explicit consent in Settings.
2. **Time entries vs the hours tracker** (Excel import, phase 2). **Answer:** keep both entries per (line, day); totals use the larger of the two. Details decided in the phase-2 spec.
3. **Drag before the Act phase.** **Open** — decided in the 3b spec. Preferred: the iPad writes a _planning intent_ (native data), and the Mac applies it to OmniFocus with confirm + undo once writes exist; needs its own ADR.
4. **Plan tab / sidebar item** on iPad. **Answer:** shortcut ⌘5; its landing screen is designed in 3b.
5. **Compact width** for Planning board and the review panel. **Answer:** accepted — a one-line explanation, as specified.
6. **RTL on iPad/iPhone.** **Answer:** an iPhone RTL artboard comes with the HE/AR language wave.
7. **Widgets**: refresh budget, and whether interactive check-off (App Intents) waits for the Act phase.

## Draft-3 changes — calendar

Calendar events (EventKit, read-only, per device) join tasks at every scale. Canvas page: "Calendar · draft-3". Every artboard has a `-Dark` twin.

1. **Events are not tasks.** No checkbox, estimate or trace chip; never amber or red; a past event is dimmed. Calendar colour appears only as an 8 pt dot or a 3 pt bar, desaturated. → `components.md` § Calendar components.
2. **Free time is a fact**, shown next to the task fact and never compared with it: `23 open · ≈ 11 h 15 min est. │ 4 events · 4 h in calendar · 1 h 15 min planned · ≈ 2 h 25 min free until 22:00` (free = what remains of the day window, decided 3 Oct 2026). → `copy.md` § Calendar strings.
3. **Today — decided: the day rail (variant B), owner's choice, 2 Oct 2026.** A **Day** section at the top of the right rail spans the day window and shows events (`EventBlock`), tasks with a planned time (`TimedTaskBlock`: outline + checkbox, height = estimate) and tasks with a due time today (`DueMark`: one amber line). Items outside the window are pinned above or below. The task list stays a list; its When column shows the planned time. Variant A (agenda section in the list) is kept on the canvas for reference only. → `screens/today.md`.
4. **Week**: events above tasks in each column, all-day bars across columns, per-day `2 h 30 min in calendar`; weekly review gains "Fixed next week". **Month**: all-day bars and an outlined count of timed events; the day list shows events first. → `screens/week.md`, `screens/month.md`.
5. **Settings → Calendars**: access state (not connected · connected · denied), per-calendar Show / Counts as busy / Line, day window. → `screens/settings-calendars.md`.
6. **Line mapping**: a calendar mapped to a line adds the line emoji to its events, feeds "Upcoming" in Line detail and the quick-log suggestion on iPhone. → `screens/line-detail.md`, `screens/iphone-quick-log.md`.
7. **iPad**: the same layer in Week; during a drag each day shows its free time as part of the drop target. **iPhone**: a Next event card on Today; widgets with next event + next anchor. → `screens/ipad-week.md`, `screens/iphone-today.md`, `screens/iphone-widgets.md`.
8. **Future (direction only)**: calendar time as a separate neutral segment on the planning board; a trip as a neutral band; `moves +1 week (trip 3–9 Nov)`. → `screens/planning-board.md`.
9. **Week strip averages** in the mockups now match `demo-data.md` (Violin `4 avg 4.0` / `1 avg 1.0`, W36–W39).

| Screen                     | Spec                                                                             | Artboards                                                                                                                                                               |
| -------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Today with events          | `screens/today.md` § Calendar                                                    | `Today-CalB` (chosen), `Today-CalB-RU`, `Today-CalB-Mixed`, `Today-CalConnect`; not chosen: `Today-CalA`, `Today-CalA-RU`, `Today-CalA-Mixed` (page "Today directions") |
| Week with events           | `screens/week.md` § Calendar                                                     | `Week-Cal`, `Week-Cal-RU`, `Week-CalReview`                                                                                                                             |
| Month with events          | `screens/month.md` § Calendar                                                    | `Month-Cal`                                                                                                                                                             |
| Settings → Calendars       | `screens/settings-calendars.md`                                                  | `SettingsCalendars`, `SettingsCalendars-None`, `SettingsCalendars-Denied`                                                                                               |
| Line detail — Upcoming     | `screens/line-detail.md` § Calendar                                              | `LineDetail-Cal`                                                                                                                                                        |
| Planning board (future)    | `screens/planning-board.md` § Calendar                                           | `Board-Cal`                                                                                                                                                             |
| iPad Week + Split View     | `screens/ipad-week.md` § Calendar                                                | `iPadWeek-Cal` (drag state), `iPadSplitHalf-Cal`                                                                                                                        |
| iPhone Today, widgets, log | `screens/iphone-today.md`, `iphone-widgets.md`, `iphone-quick-log.md` § Calendar | `iPhoneToday-Cal`, `iPhoneWidgets-Cal`, `iPhoneLog-Cal`                                                                                                                 |
| States and components      | `components.md` § Calendar components                                            | `CalendarStates`                                                                                                                                                        |

The draft-2 artboards are unchanged in appearance; the calendar variants are the same components with a `cal` property.

### Rules the mockups assume (confirm or change)

- Busy = union of timed events from calendars that count as busy, clipped to the day window; overlaps count once.
- The day window is **configurable** (decided 2 Oct 2026), default 08:00–22:00, in Settings → Calendars.
- **Planned tasks reduce free time** (decided 2 Oct 2026): a task with a planned time **and** an estimate occupies [planned time, planned time + estimate], clipped to the day window. It is reported as its own term (`1 h 15 min planned`), never added to `in calendar`. Overlap counts once: `planned` reports only planned-task time not already covered by a calendar event, and free = window − the union of both (`screens/today.md` § Calendar). Done or open makes no difference. A planned task without an estimate, and a due time, occupy nothing.
- Tentative and all-day events are shown but **not** counted; declined events are hidden.
- Free = day window − calendar − planned. On Today it counts **from now** to the end of the window (decided 3 Oct 2026); a future day in Week uses the whole window.

### Open questions (draft-3) — answered (owner, 3 Oct 2026)

1. **Free time: whole day or remaining?** **Remaining** on Today: `≈ 2 h 25 min free until 22:00` at 16:20. Week shows the whole day window for future days. → `screens/today.md` § Calendar.
2. **Should free time subtract the foundation floor?** **No** — calendar and planned tasks only, as drawn.
3. **All-day events and trips** as busy time: decided in the phase-2 spec.
4. **Calendar vs capacity in forecasts**: decided in the phase-2 spec.
5. **Per-device events vs synced plans**: per ADR-0012 — events never sync; from phase 2 per-day busy minutes (numbers only) are stored and synced as native data.
6. **Line mapping per device or synced?** **Per device**, never synced (ADR-0012): per-calendar Show, Counts as busy and Line stay on the device, keyed by `calendarIdentifier`; calendar and account titles do not leave it.
7. **Events outside the day window** (the 06:40 flight): **yes** — shown, pinned, not counted.
8. **Assistant / MCP (phase 4)**: per ADR-0012 — counts and busy time by default; titles only after an explicit opt-in in Settings.
9. **Quiet connect row**: **yes**, `Not now` hides it for 30 days. On iPhone it lives in Settings only.
10. **Slice and ADR**: ADR-0012; the work is slice **S3c**, before S4 (`docs/specs/phase-1-see.md`).
11. Which OmniFocus time puts a task on the rail: already decided — planned. The bridge exports the planned date-time (OmniFocus ≥ 4.7, `docs/discovery/snapshot-contract.md`).
12. Do tasks with a time reduce free time: already decided — yes, when they have an estimate.
13. **Day window: per device or synced?** **Synced** from 3b (ADR-0012): it is a preference, not calendar data; local in phase 1.
14. **Day rail on iPad and iPhone**: as proposed — the iPad inspector gets the same `DayRail`; the iPhone keeps the Next event card and lists timed tasks in time order. Drawn in the 3b round.

### Contract change for timed tasks

The task model needs the time part of the due date and a planned date-time (`plannedAt`), plus a flag for "date only". **"Date only" = a time equal to OmniFocus' default time** for that date kind (when `defaultTimes` or that key is absent: only 00:00); the bridge exports those defaults (`defaultTimes`, `docs/discovery/snapshot-contract.md` § Default times). Known limit, stated there: a task deliberately planned or due exactly at the default time is indistinguishable from a date-only one and is treated as date-only.

## Draft-4 changes — my take

The owner's weekly take: a qualitative assessment of how a line went this week, set only by the owner. Canvas page: "My take · draft-4". Every artboard has a `-Dark` twin. Prompt of the round: the model below is as decided there.

**Model (decided).** A take belongs to one line (optionally one project, independent of the line take) and one ISO week: a direction (`Leap · Rise · Steady · Dip`) and an optional one-line note. It can be captured at any moment as a dated **draft** note, with or without a direction; at the weekly review the owner **confirms** the week's take, prefilled from the drafts. Never computed, suggested, averaged, counted or reminded. No take is a valid, blank state. A take does not change forecasts. Any take or note resets the line's quiet count from its date (the date the note was written or the take was set, never a future date).

1. **Three tracks, never one score.** Rhythm and progress are measured (coloured bars); the take is judged (ink marks, the label `my take`). They sit side by side and are never combined. → `components.md` § Take components.
2. **Weekly review** gets a second step, `2 · My take`, with the section "How did each line go?": one row per foundation and active line — measured facts · four-segment control · note · Confirm. Drafts are listed with their day and prefill the control. → `screens/week.md`, `screens/ipad-week.md`.
3. **Lines**: a third track of take marks under each sparkline and this week's chip. → `screens/lines.md`.
4. **Line detail**: a third metric card "My take", a journal with a Leaps filter, a take per project. → `screens/line-detail.md`.
5. **Project forecast (future)**: take marks on the drift chart's week axis, one quiet row `Re-estimate what is left?` after a Leap. → `screens/forecast.md`.
6. **Quarterly review**: take strips per line, notes when a row is opened, Leaps as supporting notes under the focus outcomes. → `screens/quarterly-review.md`.
7. **Capture**: iPhone sheet `Note for my take` (Log tab and line glance), Mac ⌘K command and `Add a note`, iPad popover. → `screens/iphone-quick-log.md`, `screens/iphone-line-glance.md`, `screens/command-palette.md`.
8. **Quiet rule**: any take or note resets the quiet count from its date (the date the note was written or the take was set, never a future date) (Today rail, review, Lines). → `screens/today.md`.
9. **Fixed on the way**: Line detail and the iPhone line glance showed `avg 5.5` / `avg 1.3`; they now show `avg 4.0` / `avg 1.0`, as `demo-data.md` gives. The Mac weekly-review artboard is named `Week-Review` (the Screens table said `WeekReview`).

| Screen                         | Spec                                      | Artboards                                                 |
| ------------------------------ | ----------------------------------------- | --------------------------------------------------------- |
| Weekly review — My take (Mac)  | `screens/week.md` § My take               | `Week-Take`, `Week-Take-RU`                               |
| Weekly review — My take (iPad) | `screens/ipad-week.md` § My take          | `iPadWeekTake`, `iPadWeekTake-RU`, `iPadWeekTakePortrait` |
| Lines                          | `screens/lines.md` § My take              | `Lines-Take`, `Lines-Take-RU`                             |
| Line detail                    | `screens/line-detail.md` § My take        | `LineDetail-Take`                                         |
| Project forecast (future)      | `screens/forecast.md` § My take           | `Forecast-Take`                                           |
| Quarterly review               | `screens/quarterly-review.md` § My take   | `QuarterReview-Take`                                      |
| iPhone line glance             | `screens/iphone-line-glance.md` § My take | `iPhoneLine-Take`                                         |
| iPhone capture sheet           | `screens/iphone-quick-log.md` § My take   | `iPhoneTakeSheet`                                         |
| Components and states          | `components.md` § Take components         | `TakeStates`                                              |

The draft-2/3 artboards are unchanged in appearance; Lines, Line detail and the Quarterly review gained a `take` property.

### Recommendation: the take mark

**Shape-only marks in one ink: Leap = four-point spark (1.3× larger, primary text colour), Forward / Back = triangles along the reading direction, Steady = dot. Set = filled, draft = dashed outline.**

| Option                                 | Reads as                                                  | Leap in a row of 8–14                      | Works at 9 pt                     | Verdict                                                  |
| -------------------------------------- | --------------------------------------------------------- | ------------------------------------------ | --------------------------------- | -------------------------------------------------------- |
| Arrows up / down (↑↑ ↗ → ↘)            | a computed trend; up = good, down = bad                   | weak (one more arrow)                      | yes                               | rejected: looks measured, and `Back` becomes a warning   |
| Dot on four levels (a mini line chart) | a measured series                                         | weak                                       | yes                               | rejected: a third chart is exactly what the rule forbids |
| Disc with a glyph inside               | a stamp                                                   | medium                                     | no (glyph unreadable below 12 pt) | rejected for strips                                      |
| Colour per direction                   | a grade                                                   | by colour only                             | yes                               | rejected: colour alone, and it drifts to green / red     |
| **Shapes: ✦ ▶ ● ◀**                    | a mark put by a person; forward and back follow the words | **strong: the only spark, larger, darker** | yes                               | **chosen**                                               |

Why horizontal triangles and not vertical: the words are Forward and Back, not Up and Down; a horizontal mark is not read as "better / worse", so `Back` stays as plain as the other three.

**Superseded in part (owner, 3 Oct 2026):** the directions are now Leap · Rise · Steady · Dip, and Rise and Dip will be redrawn as terrain shapes that are not arrows (next round). The shape-only, one-ink principle above stays.

### Recommendation: where the section goes

**Last, as its own step of the review: `1 · Facts`, then `2 · My take`.** The take is a judgement made after the facts, and the section needs a full-width row per line with a note field, which does not fit next to the three fact columns. On the Mac and iPad landscape the day grid collapses to day pills in step 2; on iPad portrait the section is the last swipeable card. No "Confirm all drafts".

### Open questions (draft-4) — answered (owner, 3 Oct 2026)

1. **RU name.** **«Мой взгляд»**; EN `My take`.
2. **`Back` as a label.** Replaced: the directions are `Leap · Rise · Steady · Dip` / «Рывок · Подъём · Ровно · Спуск». No `My take:` prefix workaround is needed. Rise and Dip get new marks in the next round (below).
3. **Confirmed take without a direction?** No — confirming needs a direction; a note without one stays a draft.
4. **Dated notes on confirm.** Kept as data under the take and shown when the journal row is opened.
5. **A note for a week that is already confirmed.** Stored under that take; the take stays confirmed.
6. **Past drafts in later reviews.** Not listed; reachable from the journal and the quarterly review.
7. **Storage, slice and ADR.** Storage in the first native slice of phase 2; no separate ADR. ADR-0010's conflict rules gain: draft notes merge (append-only); a confirmed take is last-writer-wins per (subject, week). Writing confirmed takes to the vault is decided in the Act phase spec.
8. **Project take vs line take.** Independent; no roll-up.
9. **Hours wording.** `2 h of 6 h budget` / «2 ч из 6 ч бюджета».
10. **Quiet rule detail.** Any take or note resets the quiet count from its date (the date the note was written or the take was set, never a future date).
11. **Re-estimate row.** In the project's forecast after a Leap on that project; in Line detail after a Leap on the line, listing the line's projects that have plans. Dismissed with `Not now`.
12. **One tap vs Confirm.** The place decides, not the day: in the weekly review choosing a direction confirms the take; everywhere else (Line detail, the iPhone sheet, ⌘K) it creates a draft.
13. **Demo data.** Keep the AI/ML Leap in W37 and drop the claim "fewer tasks than average"; the Violin W36 example carries that case.
14. **Not drawn in this round.** Split View, the Today rail, RTL marks and the Mac note popover are drawn in the 3b round. Rule now: take marks mirror with the layout direction.
15. **LV / IT / DE words** are marked "draft — owner review" in `tone-glossary.md`.

Phase 1: the Lines (S4) and weekly review (S5) layouts leave room for the third track; no code for takes in phase 1 (`docs/specs/phase-1-see.md`).

### For the next design round (3b)

The mockups are generated files and are not edited by hand; where a mockup and a spec differ, the spec wins. Items for the designer:

1. **Rise and Dip marks**: redraw as terrain shapes that are not arrows (a rising slope, a falling slope). Until then the triangles stay.
2. **`Lines.dc.html` — Math's block**: the draft-4 mockup shows 📐 Math under the block `Foundation` and has dropped the `Science` / «Наука» block label; `demo-data.md` keeps Math in **Science** (tier unchanged: active). Restore Science.
3. **Names in the mockups**: Forward / Back → Rise / Dip (EN, RU, LV, IT, DE); hours `2 h of 6 h budget`.
4. **Draft-4 items not drawn**: Split View for the take section, the take on the Today rail, RTL marks, the Mac note popover; how a project take is confirmed in the weekly review.
5. **Draft-3 items**: the day rail on iPad and iPhone (open question 14 above); free time on Today as the rest of the window (`≈ 2 h 25 min free until 22:00` at 16:20); the deadline rule (`screens/settings.md` § Deadlines: the setting, and plain `due 20:35` text and neutral day-rail marks for due dates that are not deadlines); read-only checkboxes on the day rail.
