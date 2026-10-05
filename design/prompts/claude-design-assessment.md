# MoonShine — Claude Design prompt: the owner's weekly take (design draft-4)

Use in the same Claude Design project, new page "My take · draft-4". Re-read first: `design/README.md`, `design/principles.md`, `design/tokens.md`, `design/copy.md`, `design/tone-glossary.md`, `design/demo-data.md`, `design/screens/week.md`, `lines.md`, `line-detail.md`, `quarterly-review.md`, `forecast.md`, `ipad-week.md`, `iphone-line-glance.md`.

---

Add the **owner's weekly take** to MoonShine (draft-4): a qualitative assessment of how a line went this week, set only by the owner.

## Why

Hours and task counts do not show real progress. Two hours of violin instead of six planned can be the week when something finally worked. A work project can take less time than planned because an approach was found that changes everything. Today such a week looks like a decline. The owner needs a way to say what really happened, and the app must show it as his judgement, next to the measured facts and never mixed with them.

## The model (decided)

- A **take** belongs to one **line** and one **ISO week**. Optionally, a take can also be set on a single **project**.
- It has a **direction**, one of four: **Leap** · **Forward** · **Steady** · **Back**, and an optional **note**: one line saying what happened (`Vibrato finally works`). The note matters more than the direction.
- Only the owner sets it. It is never computed, suggested as a value, or averaged.
- **Draft during the week, confirm at the review.** What happened on Monday is hard to recall on Sunday, so a take can be captured **at any moment** as a draft: a dated note, with or without a direction. A line can collect several dated notes in one week. At the weekly review the owner sees the week's drafts for each line and **confirms** the take: a direction and a note, prefilled from the drafts and editable.
- A draft and a confirmed take must look different (for example a dashed mark and a solid one). A draft that is never confirmed stays a draft: nothing expires, nothing reminds, nothing is counted.
- No take is a valid state. A week without a take is blank, not "Steady".
- A confirmed take can still be changed later; the latest value is shown, with the date it was set.
- A take **does not change forecasts**. After a Leap, the app may offer `Re-estimate what is left?`; the owner changes the numbers.
- A line with a take for the week, draft or confirmed, is **not flagged as quiet** that week, even with no tasks done.

Names: propose the user-facing name of the feature in English and Russian (candidates: `My take` / `Моя оценка`) and the four direction words in both languages (candidates: `Leap · Forward · Steady · Back` / `Рывок · Вперёд · Ровно · Назад`). They must pass the tone rules and work in LV, IT and DE later.

## Rules (hard requirements)

- **Three tracks, never one score.** A line now has rhythm (repeated sessions), progress (one-off tasks) and the owner's take. They are shown side by side and are never summed, averaged, ranked or turned into a percentage.
- **Measured and judged must look different.** Rhythm and progress are measured facts; a take is the owner's judgement. A reader must see at a glance which is which (different mark shape, a label such as `my take`).
- **No red.** Amber stays reserved for deadlines. `Back` is the owner's own word about his week: show it as plainly as the other three, with no warning styling.
- **Leap must be findable.** It is the reason the feature exists. Give it a distinct mark that stands out in a row of eight to fourteen weeks without colour alone.
- **No nagging.** Setting a take is always optional and takes one tap. No counters of unassessed lines, no streaks, no reminders.
- **Facts stay facts.** Where hours and a take disagree, show both without a connecting judgement: `2 h of 6 planned · my take: Leap — "Vibrato finally works"`.
- Notes are user data: any language, any script, never translated (`i18n.md`).
- Touch targets ≥ 44 pt on iPad and iPhone. Light and dark for every artboard.

## Screens

### 1. Weekly review (Mac `Week` in review mode, iPad landscape and portrait)

A new section **"How did each line go?"**:

- One row per line: foundation and active lines always; maintenance lines collapsed under "more"; lines paused on purpose are not listed.
- Row: emoji + name · the week's facts (rhythm and progress with their 4-week averages; hours against the budget when time data exists) · a four-segment control for the direction · a one-line note field that grows when focused.
- A row with drafts shows them first, each with its day (`Mon · Bars 9–16 clean at ♩ = 60 · Forward`). The control and the note are prefilled from them: the latest direction, the notes joined. `Confirm` turns the draft into the week's take; the owner can change either part before confirming.
- Keyboard on Mac: arrow keys move between lines, `1`–`4` set the direction, `Return` opens the note, `⌘Return` confirms.
- A row already confirmed shows its take and note; changing it is one tap.
- Propose whether a `Confirm all drafts` action belongs here. It saves taps but invites confirming without reading.
- iPad portrait: the section is one of the swipeable review cards.
- Show how the section sits with the existing review sections (quiet lines, no next action, no plan, due next week, fixed next week). Propose the order; the takes come last if they depend on having looked at the facts first.

### 2. Lines

- Each row's eight-week sparkline gains a third track of **take marks**, aligned to the weeks. Blank weeks stay blank.
- The row shows this week's take as a small chip when set.
- A line whose only sign of life this week is a take reads, for example, `my take: Forward` where "quiet for N days" would otherwise appear.

### 3. Line detail

- The metric cards stay separate: Rhythm, Progress, and a new **My take** card with the take marks for the visible weeks.
- A **journal**: the takes with notes, newest first (`W40 · Leap — Vibrato finally works`). A filter to show Leaps only.
- "Set my take for this week" when none exists.

### 4. Project (optional take)

- From a project row and from the project forecast: `Add my take` opens the same control.
- On the forecast's drift chart, takes appear as marks on the week axis, so a date that moved can be read next to what the owner said about that week.
- After a Leap on a project: one quiet row `Re-estimate what is left?` that opens the plan's estimates. Nothing changes by itself.

### 5. Quarterly review

- In "Lines over the quarter", each line gets its strip of take marks for the quarter's weeks, and its notes listed below when the row is opened. Leaps are easy to find.
- In "Focus outcomes", an artifact's line shows its Leaps of the quarter as supporting notes.

### 6. Capturing a draft at any moment

- **iPhone is the main place**: from the line glance, and from the Log tab next to "Log time" — `Note for my take`: pick a line (recent first), type one line, optionally tap a direction, save. Three taps for the common case, reachable with one thumb.
- **Mac**: a ⌘K command (`My take: Violin…`), and "Add a note" in Line detail.
- **iPad**: the same sheet as the iPhone, from Line detail and from the review.
- A saved draft appears at once as a draft mark on the line's current week and in its journal with the day it was written.
- No widget and no notification for takes in this round.

## States to draw

- No take yet (week in progress) and no take (past week).
- A take without a note; a take with a long note; a note in Russian and in a mixed-script example.
- Low hours with a Leap; high hours with Back; no measured activity with Forward.
- A draft mark next to a confirmed mark, in a sparkline and in the journal.
- A week with two dated draft notes; a draft with a note and no direction; a Monday draft confirmed on Sunday with a different direction.
- A past week whose draft was never confirmed (still a draft, no warning).
- A take changed after the week ended (shows the date it was set).
- A quarter with one Leap among mostly blank weeks.
- Russian UI variant of the weekly review section and of Lines.

## Demo data (invented — add to `design/demo-data.md` as "Draft-4: takes")

Weeks 33–40, today Thu 1 Oct 2026. All takes of W33–W39 are confirmed unless marked as a draft. W40 is in progress and has drafts only:

- W40 drafts: 🎻 Violin — Mon 28 Sep `Bars 9–16 clean at ♩ = 60` (Forward) and Wed 30 Sep `Teacher asked for the Sarabande next` (no direction) · 🤖 AI/ML — Tue 29 Sep `Harness runs end to end` (Forward).
- One unconfirmed past draft: 📐 Math, W38 — `Finally understood change of basis` (Leap, still a draft).

- 🎻 Violin: W35 Forward — `Allemande bars 1–8 from memory` · W36 **Leap** — `Vibrato finally works` (the week with 1 session, the lowest of the eight) · W38 Forward · W39 Steady.
- 🤖 AI/ML: W37 **Leap** — `Found a way to grade answers without a reference set` (a week with fewer tasks done than average) · W39 Forward.
- 🔬 Research: W38 Back — `Section 3 outline does not hold; starting again` · W39 Steady.
- 🇮🇹 Italian: no takes (quiet for 29 days stays as it is).
- 🧘 Core practice: W39 Steady. 💪 Calisthenics: W37 Forward — `First clean set of 8`.
- 👨‍👩‍👧 Family: W39 Forward — `Evening reading every day`.
- One project-level take: Bach Partita No. 2 — Allemande, W36 Leap (same note as the Violin line).

Keep every mark on the artboards derivable from this list.

## Deliverables

- Artboards, light and dark: Week review with the new section (Mac, iPad landscape, iPad portrait card), Lines, Line detail (card + journal), Project forecast with take marks and the re-estimate row, Quarterly review, iPhone line glance, the states sheet, the Russian variants.
- Components: `TakeControl` (four segments + note + confirm), `TakeMark` (four directions + blank, each as draft and confirmed), `TakeChip`, `TakeJournalRow`, `TakeDraftSheet` (the capture sheet). Add them to `design/components.md` with sizes for Mac, iPad and iPhone.
- Specs: a "My take (draft-4)" section in each affected `design/screens/*.md`, same structure as the existing specs (Layout · Data · Behaviour · SwiftUI · Acceptance).
- Copy: the feature name, the four direction words, and every new string in `design/copy.md` (EN and RU); the direction words in `design/tone-glossary.md` for EN, RU, LV, IT and DE.
- `design/README.md`: "Draft-4 changes" and open questions. Include your recommendation for the take mark's shape and for where the weekly-review section goes.
