# Phase 2 — Plan (until ~2027-01-27)

Revision 2 of 2026-11-01, decided by the owner on 2026-11-01 (§ Decided). Every example is invented (CLAUDE.md rule 5). Revision 2 takes the owner's decisions of 2026-11-01: time capture first, DC inside the phase after TM2, F6 and N1 cut for P2-R1 and P2-R2, the Health bridge H, no iPhone capture before 3b; and the new requirements: the routine template (ADR-0023) and the evidence base (ADR-0024).

The slice plans drafted with this revision are not committed: each slice's plan is written and critiqued when the slice starts (CLAUDE.md § Plans), and the raw estimates below are those drafts' estimates.

**Goal:** MoonShine knows where the owner's time actually goes, from what he says, a timer, his watch and his workbook. It compares the days with the routine he set himself, and turns the result into plans with steps, effort levels and honest forecasts. During the day it tells him, in facts and only a few times, what is still open. Keyboard-first and calm, as in phase 1.

**Gate:** phase 2 starts after phase 1 has been used for real for ≥ 2 weeks and its "done" link exists (`docs/ROADMAP.md:3`). With phase 1 ending ~2026-11-20 (`docs/specs/phase-1-see.md:3`), that is **not before ~2026-12-04**. R1 Quarterly review (deadline 2026-12-28) and the Month view are built in that usage period (`docs/ROADMAP.md:11`, `docs/specs/phase-1-see.md:28`); they are not this spec's P2-R1 and P2-R2, which are the routine slices. No phase-2 slice starts before this spec is merged into `docs/specs/` (CLAUDE.md rule 1).

## Timebox (re-baselined from `docs/method/forecast.md`, on the order of question 1)

The ROADMAP gave phase 2 "3 weekends" until this spec; a phase's timebox is re-baselined from the forecast when its spec is written (`docs/ROADMAP.md:3`). Inputs:

- **Size factor 1.49** (`docs/method/forecast.md:9`).
- **Pace about 250 production lines a day** (`docs/method/forecast.md` § Basis).
  - Checked against the latest merged code slices, dated 2026-10-20 to 2026-10-30 in `docs/method/log/2026-10.md`, net lines at their final heads: S4-1a 829, S4-1b-1 401, S4-1b-2 363, S4-3a 104 (its only head in the log), S4-DD 472, H1a 270, H1b 160.
  - That is 2,599 lines in 11 days ≈ 236 a day, so 250 holds within 6 %.
- **Slow scenario:** 0.6 of the pace from January, 150 a day (`docs/method/forecast.md` § Basis).

Raw estimates by group, from the slice rows below:

| Group                 | Slices              | Raw lines |
| --------------------- | ------------------- | --------- |
| Time capture          | X2, LT1–LT4         | 1,545     |
| Timer and checkpoints | TM1, TM2, DC, TM3   | 1,330     |
| Routine               | P2-R1, P2-R2, P2-RV | 1,149     |
| Health                | H                   | 492       |
| Workbook              | X1, X3, X4, X5      | 1,055     |
| Timer, the rest       | TM4–TM6             | 1,250     |
| Plans and forecast    | F1–F5               | 1,500     |
| Charts                | P2-RC               | 300       |
| Vault-backed          | P1, PL, Q           | 1,050     |
| **Total**             |                     | **9,671** |

Time reconcile (300) is a slice outside the phase, built right after it.

| Scope                                        | Estimate (raw) | × 1.49 | Days at 250 | Ends (base, from 12-04) | Ends (slow from January) |
| -------------------------------------------- | -------------- | ------ | ----------- | ----------------------- | ------------------------ |
| Every phase-2 slice                          | 9,671          | 14,410 | 57.6 → 58   | 2027-01-31              | 2027-02-20               |
| After cut candidates 1–2 (P2-RC, P1: 700)    | 8,971          | 13,367 | 53.5 → 54   | **2027-01-27**          | 2027-02-13               |
| Then TR, outside the phase                   | 300            | 447    | 1.8 → 2     | + 2 days                | + 3 days                 |
| After the cuts, with AP2 (owner, 2026-11-01) | 9,091          | 13,546 | 54.2 → 55   | 2027-01-28              | 2027-02-14               |

Both columns count the same way: the end is the start + N days, so 12-04 + 54 days is 01-27. The slow column works like this: December's 28 days (12-04 to 12-31, ending on 01-01) carry 28 × 250 = 7,000 lines, and the rest goes at 150 a day from 01-01.

- After the cuts: (13,367 − 7,000) / 150 = 42.4 → 43 days → 02-13.
- Full scope: (14,410 − 7,000) / 150 = 49.4 → 50 days → 02-20.
- After the cuts, with AP2: (13,546 − 7,000) / 150 = 43.6 → 44 days → 02-14.

**Timebox: until ~2027-01-27, with cut candidates 1–2 taken now** (owner, 2026-11-01; questions 1 and 2).

- Revision 1 proposed ~01-15. The difference is real scope: the Health bridge, P2-R1, P2-R2 and P2-RV, and DC moving into the phase. F6, N1 and X6 come out. The four critic runs of revision 2 grew P2-R1, P2-R2 and H by about 220 raw lines.
- **AP2 and LT3's configurability** (owner, 2026-11-01, § Decided) came after the arithmetic above: AP2 is about 120 raw lines, one day at the base pace; LT3's provider list, per-feature models and eval command are sized at LT3's planning. The timebox stays ~2027-01-27; the timebox review after LT4 decides whether that day comes from the cut list.
- The ROADMAP's "3 weekends" and the forecast's stage row "Phase 2 Plan, Timer (Mac) last · 11-17 to 12-22" were replaced with this spec's PR (`docs/method/forecast.md` § Stages).
- **Timebox review** after LT4 merges (the first usable slice, the 7th PR), with the measured pace, as phase 1 had one after S4-1b.

## Scope

What the ROADMAP's phase-2 row asks for (`docs/ROADMAP.md:9`), the Time reconcile row (`docs/ROADMAP.md:10`), and the owner's additions:

1. **Log by text** (owner, 2026-11-01), the first model-backed feature and the first usable slice.
   - The owner dictates (macOS dictation) or pastes a sentence about what he did.
   - The model only extracts, as literal spans: activities; start, duration or end; "then" links.
   - Code computes the times from the anchor and the local date, maps activities through the owner's alias file, and checks overlaps and gaps.
   - The owner confirms a list with inline edits: one `confirm` command (ADR-0013) with undo, source `dictation`.
   - **Provider and model are configurable** (owner, 2026-11-01; ADR-0005, amendment 2026-11-01): other users will want other models. The `AIProvider` port is provider-neutral, Settings → Assistant keeps a model per feature, and LT3 ships the Claude adapter, AP2 an OpenAI-compatible one (§ Decided, Q8).
2. **Time entries** with the ADR-0016 fields that phase-2 sources fill, from their first slice (X2): day, optional clock times with the time zone at capture, minutes, subject, source, edited. `session` comes with TM1 and `step` with F2 (question 17).
   - Sources:
     - `timer` · `excel` · `dictation` (stated);
     - `manual` and `calendar` stay reserved source values, not built in phase 2 (owner, 2026-11-01; Non-goals);
     - **`health`** (measured; owner, 2026-11-01);
     - `omnifocusEstimate` (derived, computed, never stored).
   - The ADR-0016 amendments land with this spec's PR.
   - ADR-0016's two-sources rule is in the hours ledger from X2. Within the tolerance the native entries stand; beyond it they count and the cell is marked; the two are never summed. The owner's choice comes with Time reconcile.
3. **The `CommandBus` and the activity log with undo** for native writes (ADR-0013), from LT2b. The ROADMAP's first native slice was My take until this spec; it is Log by text now, and My take is cut from phase 2.
4. **Timer (Mac)** (ADR-0016, `design/screens/timer-mac.md`, `design/screens/time.md`, `design/screens/today.md` § Time), in two groups:
   - the sessions, the notifier and the menu bar (TM1–TM3) early;
   - the Today time lane, the Day view and Settings → Time (TM4–TM6) after the workbook.
     With the notification planner and the `Notifier` (ADR-0017: whichever of Timer (Mac) or Reminders (Mac) ships first brings them).
5. **Day checkpoints, L1** (owner requirement 2026-10-30; ADR-0022, proposed), **inside the phase, right after TM2** (owner, 2026-11-01). They work like this:
   - at set times, plan and fact are compared;
   - each checkpoint sends one notification with one or two items, at most 3 a day;
   - rules only, on the device;
   - the kind `routineBlockOpen` joins from P2-R2.
6. **Routine template, adherence and progression** (owner, 2026-11-01; ADR-0023, proposed):
   - **the routine note**: a vault note `moonshine: routine` (P2-R1), with versions stored;
   - **adherence per block, and ladders** that suggest advancing or stepping back, by rules, in Core (P2-R2);
   - **the views**: ghosts on the day rail and a week adherence table (P2-RV);
   - **line charts** of plan, template and fact on one axis (P2-RC, cut from phase 2 on 2026-11-01);
   - **the move into a native entity**: after phase 2 (question 27).
7. **The Health bridge** (owner, 2026-11-01; slice H).
   - An iOS Shortcuts automation overwrites a fixed set of CSV files in iCloud Drive with a rolling window, so nothing accumulates there (owner, 2026-11-04); the Mac reads them read-only, under the same kind of guards as the workbook.
   - H1's setup doc says the files are end-to-end encrypted only with Advanced Data Protection, and that this is the owner's choice.
   - Sleep gives the day's wake and bed boundaries.
   - Workouts become entries with source `health`; steps become a `Measurement`.
   - The CSV format is open until the owner tests the shortcut (question 12). Whether HealthKit replaces the bridge is an open item for 3b's planning (open question 38); the bridge stays until it is decided.
8. **Workbook hours import with label mapping** ("decision 2026-10-01: forecast calibration needs the hours"; `docs/discovery/excel-contract.md`), now after the Health bridge, still before the forecast engine that needs the hours.
   - "Column mapping" in the ROADMAP means two things. The day columns are found by structure (layout A or B) and checked against the sheet's month. Item labels map to lines through a mapping file in the data folder.
   - The time view's week table (X5) shows its hours with the other sources.
9. **Plans with steps** of any kind (`effort`, `sessions`, `quantity`, `metric`, `checkpoint`), three-point estimates, `minDuration`, `maxRate`, prerequisites (ADR-0006).
   - **Effort levels** min / normal / max per project. Normal comes from the vault budget (ADR-0006); a routine's template minutes are shown beside it (question 28) and seed the Board's capacity in phase 3 (ADR-0023).
   - Capacity per week.
   - Native measurements for `metric` steps.
10. **Forecast engine:** calibration (bias, adherence per line) and Monte Carlo (p10 / p50 / p90), modes Actual pace and Scenario (Inverse is phase 3, `docs/ROADMAP.md:18`), and weekly snapshots (F5). **The project forecast view with the drift chart (F6) is cut** (owner, 2026-11-01). F5's snapshots keep the history for it.
11. **Practice lines, then Quotas**, last in the phase. The ROADMAP placed Memos on Today (P1) before them; P1 is cut from phase 2 (owner, 2026-11-01), so Practice lines brings the `moonshine` scanner itself (`docs/ROADMAP.md:9`). Quotas use Practice lines' period, streak and read-state code (ADR-0019, amendment of 2026-10-26).
12. **Time reconcile** (`docs/ROADMAP.md:10`): a slice outside the phase, right after it.

## Non-goals

- **Cut from phase 2** (owner, 2026-11-01): F6, the forecast view with the drift chart; N1, My take, with the weekly review mode it needs. X6, the workbook's indicator rows, is not in the order either: steps now come from Health (question 29).
- **Later phases:**
  - the Planning board, scenarios A/B and the inverse mode (phase 3);
  - the iPad and iPhone apps and sync (3b);
  - **a minimal iPhone capture before 3b: no** (owner, 2026-11-01; question 13);
  - HealthKit on the iPhone (3b planning decides it, open question 38; the bridge stays until then).
- **The assistant** beyond Log by text's extraction: read tools, "what if", plan drafting, voice `auto` commands, MCP (phase 4). Day checkpoints L2 (phase 4) and L3 (phase 5); P2-R3, the assistant's routine ladders (phase 4); the evidence base's use (ADR-0024, phase 4).
- **Writes:** any write to OmniFocus, the vault or a calendar (CLAUDE.md rule 6). Time entries, measurements, boundaries, routine versions, day marks, plans and captures are MoonShine-native and never written out.
- **Not built:**
  - an editor for the routine (ADR-0023: the vault note until the import);
  - editors for the mapping and alias files (hand-edited YAML in the data folder);
  - native reminders and P2–P4; the Hub and Library slices;
  - capacity exceptions from the workbook's context rows;
  - idle detection, a watch, standalone countdown timers;
  - **`manual` and `calendar` entries** (owner, 2026-11-01): the quick log and a time entry confirmed from an ended event, and with them the calendar-based nudges and the day portion from a line's calendar (ADR-0016), which need the calendar's line mapping cut in phase 1. Both stay reserved source values; Log by text replaces the quick log in phase 2;
  - **the data rules of ADR-0024's catalogue** (owner, 2026-11-01): built in phase 4; nothing from the catalogue lands inside a phase-2 slice;
  - **a session kind captured by dictation** (owner, 2026-11-01; open question 37).

## Rules this phase adds

- **Hours shown** stay as rule 8 says: next to real time data (entries) or owner-set numbers only (the template's block minutes are owner-set). Derived `omnifocusEstimate` minutes are not shown in the week table in phase 2; they feed the forecast's calibration only.
- **Failed is not empty, for time, health and the routine:**
  - a source that cannot be read (the workbook, the Health folder, the routine note) keeps everything stored from it;
  - a month sheet or a Health day that cannot be read, or that is absent from a read, keeps its rows;
  - a read with a skipped row removes nothing of that month or day;
  - only a clean read removes what it no longer has;
  - a mapping or alias file that cannot be read leaves its import unavailable (an absent alias file is an empty mapping: § Precedence below);
  - a row the read recognises and ignores on purpose (the workbook's context and indicator rows, X3) is not a skipped row;
  - a routine block without tracking evidence is "no data", never "no time".
- **The model never supplies a time or a target on its own.**
  - Every value it returns is a span of the text, checked by code.
  - A value only the model could read is shown as such (question 19).
  - Times on the clock are computed by code.
  - A subject comes from the alias file or a line or category name. Only when none matches is the model's proposal used, and it is shown as a proposal (ADR-0013 § Conditions for `auto`, applied to a `confirm` command).
  - **What guards the data is the owner's confirmation** (owner, 2026-11-01). Every value is a checked span, shown beside its span highlighted in the owner's text; spans out of order against their activities are flagged (`spansOutOfOrder`); nothing is stored without the owner's confirmation. A weaker model costs more corrections, whatever the provider. LT1's checks do not prove that a value belongs to its activity: swapped minutes between two activities pass the span check, and the confirmation is the guard.
- **Provider-neutral Core** (owner, 2026-11-01): nothing in Core names an AI vendor or a model id; the network API is allowed only in the AI adapter target. LT3 builds both CI checks (LT3, the last bullet).
- **The endpoint rule** (owner, 2026-11-04; review round 1), for every AI provider (LT3, AP2):
  - The host is parsed from the base URL each time a request is built, never looked up in DNS.
  - Loopback is only the literal `localhost`, an IPv4 literal in `127.0.0.0/8`, or `::1`. Plain HTTP is allowed for loopback only.
  - A loopback endpoint is labelled "Sent to a server on this Mac (`host:port`). MoonShine can't see where that server sends it."
  - Every other host must use HTTPS and is labelled with its host name.
  - Every provider, local ones included, asks the same one-time consent when it is configured. There is no consent per request.
- **Precedence** (owner, 2026-11-04; review round 1):
  - **Mapping:** an alias overrides the line mapping, and the line mapping overrides the category default.
  - **The alias file:** an absent file is an empty mapping. A file that exists but cannot be read or parsed fails closed: nothing that needs it is imported, and the problem is shown to the owner.
  - **Two wakes on one day:** the wake confirmed most recently wins; the earlier one stays stored and reachable through undo. The same holds for two beds.
- **Logs, problems, live checks and PRs** carry kinds and counts only: no label, mapping key, sheet name, month, date, dictated word, block name, workout name, step count, id or entry (CLAUDE.md rule 5; `docs/discovery/excel-contract.md` header). Health data is the most sensitive of these.

## Slices (one PR each), in the order of question 1

The owner's order, with the architect's two additions: P2-RV right after P2-R2, so the routine is visible (question 24), and P2-RC after F5, as a cut candidate.

**Naming:** in the repository, the routine slices are written P2-R1, P2-R2, P2-RV, P2-RC and P2-R3. The bare "R1" stays the Quarterly review (`docs/ROADMAP.md:11`; the vault contract's "read from R1").

X2 → LT1 → LT2 → LT3 → LT4 → AP2 → TM1 → TM2 → DC → TM3 → P2-R1 → P2-R2 → P2-RV → H → X1 → X3 → X4 → X5 → TM4 → TM5 → TM6 → F1 … F5 → PL → Q (P2-RC and P1 cut, owner 2026-11-01); then TR, outside the phase.

LT4, the first usable slice, is the 7th PR. Sizes are each plan's raw estimate × 1.49; a plan re-sizes and splits before coding (CLAUDE.md rule 2). The limits are about 400 for a risky slice and about 800 for a plain one.

**Time capture**

- [ ] **X2 — Time entries in Core** (plain: Core types and rules; ~225 × 1.49 ≈ 335). **The first slice; it creates `TimeEntry`.**
  - The types:
    - `TimeEntry` and its validation (clock bounds on whole minutes);
    - `LocalDay`, `CalendarMonth`, `TimeSubject` (`.unmapped` for the workbook and Health);
    - `TimeEntrySource`, with `dictation` and `health`, and its evidence class;
    - the eight default Life ops category keys;
    - `SourceKey` (the workbook's key now, Health's from H).
  - The hours ledger per unit and day with ADR-0016's source rule; the Life ops unit is per category (question 16).
  - Derived entries from completed tasks, an action group counting only when no descendant carries an estimate (question 18).
  - The workbook's port moves to X3.
- [ ] **LT1 — Log by text: the reading, in Core** (risky: the assistant; ~315, two PRs). No model, no store, no UI.
  - [ ] **LT1a — The extraction, spans, readers and wall time** (~177 × 1.49 ≈ 264).
  - [ ] **LT1b — The chain, subjects and checks** (~138 × 1.49 ≈ 206).
- [ ] **LT2 — Native time storage, the command bus and `LogEntries`** (risky: storage and a command; ~380, two PRs). It brings the `time_entry` table, split out of X4.
  - [ ] **LT2a — `time_entry` and `day_boundary` in the store** (~170 × 1.49 ≈ 253).
    - A numbered migration after phase 1's: `time_entry` (core columns, an indexed `source_key`, `attrs`; the `changes` log of ADR-0002) and `day_boundary` (wake or bed, instant, the stored day, source, `source_key`).
    - `Store` methods for the entries and boundaries of a range, and one transaction that inserts or removes the rows of one command.
    - Both stores, the contract suite.
  - [ ] **LT2b — `CommandBus`, activity log, `Capture`, `LogEntries`** (~210 × 1.49 ≈ 313).
    - The `CommandBus` in Core (ADR-0013: the id as idempotency key, origin, class, state, undo data) and the activity log table.
    - `Capture`: the text as dictated, stored on the Mac before any network call.
    - `LogEntries`: a `confirm` command for the confirmed list; its undo removes exactly the rows it inserted: its entries and the day boundaries dictated in the same confirmation. Dictated wake and bed are stored as day boundaries (question 9).
  - **The boundary-day function** (Core): a bed before 06:00 belongs to the day before. Every writer of boundaries uses it (LT2b, H2).
  - **`DayBoundaries.resolve`** (Core, LT2b), the first slice that stores boundaries; DC, TM4 and P2-R2 reuse it. ADR-0022 § The day and ADR-0023 § Adherence state it in the same words: The day's wake and bed come from one Core rule, `DayBoundaries.resolve` (spec slice LT2b): Health's boundary first (measured), then the dictated one confirmed most recently (stated), then a Sleep entry with clock times, for the wake the end of the first one that ends after local midnight, so a nap later in the day never moves it; with none of these, the day starts at the day window's start. A bed before 06:00 belongs to the day before; the writer stores the day, and readers take it as stored.
- [ ] **LT3 — The model call** (risky: the assistant, network, a secret, outside data; ~265 × 1.49 ≈ 395 before the configurability of Q8, re-sized and likely split at its planning; the cut and the eval command may change then, the configurability may not).
  - The `AIProvider` port in Core (`docs/ARCHITECTURE.md:24`), provider-neutral: a request with a JSON-schema output, and a typed reply. Nothing in Core names a vendor.
  - A Claude adapter over `POST /v1/messages` with URLSession (there is no official Swift SDK), with a JSON-schema output (`output_config.format`; for the cheaper model, open question 39). The only adapter this slice ships.
  - **Settings → Assistant** lists the providers and keeps a model id per feature: Log by text now; checkpoints L2 and the routine assistant in phase 4. Each provider has its own key in the Mac's Keychain (not synchronizable) and its own consent text; consent for cloud AI is off by default. The endpoint rule applies (§ Rules this phase adds). What is sent per question 7.
  - **Default models** per question 8: `claude-opus-5-5` at low effort, with `claude-haiku-5-5` as the cheaper choice. LT3 runs them on an eval of about 20 invented dictations (accuracy against cost) and records the result in its PR; if they don't do well, the default changes.
  - **The eval set and `moonshine-import eval-dictation --provider … --model …`** (counts only) run against any configured model, so a user can check his choice.
  - The alias file reader: bounded YAML with the vault's pre-parse guards. It also maps Health workout names, from H.
  - **Two CI checks**, added by this slice and run in CI beside `scripts/check-core-imports.sh`:
    - the network check fails on a network API outside the AI adapter target: at least `URLSession`, `URLRequest`, `import Network`, CFNetwork and the `contentsOf:` initialisers of `Data` and `String`; LT3's plan fixes the list. A `Process` is outside it (the OmniFocus adapter starts `osascript`) and is left to review;
    - the vendor check fails on an AI vendor's name or a model id in `MoonShineCore`.
- [ ] **LT4 — Log by text window** (plain; ~360 × 1.49 ≈ 536). **First usable slice.** It needs a design round.
  - A text field (system dictation works in it) and `Read`.
  - The list with inline edits, which go through LT1's `recheck`.
  - `Confirm` (⌘↩), undo (⌘Z).
  - For an activity with no alias, the YAML line to add.
- [ ] **AP2 — An OpenAI-compatible provider** (owner, 2026-11-01; risky: the assistant, network, a secret; ~120 × 1.49 ≈ 179, sized at its planning). Right after LT4.
  - An adapter for the OpenAI-compatible chat API with a configurable base URL, in the AI adapter target, behind the same `AIProvider` port. It also covers local servers such as Ollama or LM Studio. The endpoint rule applies (§ Rules this phase adds).
  - Its own key in the Keychain and its own consent text in Settings → Assistant.
  - `eval-dictation` runs against it like any configured model.

**Timer, the first part, and day checkpoints**

- [ ] **TM1 — Sessions and the timer commands** (risky; ~280).
  - `TimerSession`; `StartTimer`, `PauseTimer`, `ResumeTimer` and `StopTimer` with undo.
  - Up to three running; `Keep running`; the check mark.
  - Bounds floored to the minute; `session` on `TimeEntry`.
- [ ] **TM2 — Notification planner, `Notifier`, nudges, login item** (risky: permissions, a process at login; ~300). The planner in Core, as ADR-0017 § Notifications describes it; the Mac adapter on `UserNotifications`.
- [ ] **DC — Day checkpoints, L1** (risky: notifications, timed evaluation, stored counters; ~300 × 1.49 ≈ 447, two PRs: the rules in Core, then delivery and settings). It follows ADR-0022:
  - the kinds offered from DC: `deadlineDue`, `top3NotStarted` and `floorOpen`;
  - `routineBlockOpen` from P2-R2, `workShare` from TM3's work lines, `quotaTime` from Q;
  - times per question 3, kinds per question 4, the limit per question 5.
    It needs a design round.
- [ ] **TM3 — Menu bar popover, activity palette, the system-wide shortcut, the work lines** (plain; Carbon `RegisterEventHotKey` behind an adapter in the app target, `design/README.md` § Draft-5, A7; ~450).

**Routine**

- [ ] **P2-R1 — The routine reader** (risky: parses vault notes, then storage and a command; ~439, two PRs).
  - [ ] **P2-R1a — The template in Core and the note reader** (~262 × 1.49 ≈ 390).
    - The `moonshine: routine` note, found by the budget note's identity rule. A note rejected before extraction is searched in its head bytes. "No note" counts only on a read that saw every note.
    - The frontmatter, under §3's 64 KiB cap (question 25).
    - Variants, blocks and ladders, validated per item: unknown keys, cross-variant block keys, ladder stages against their block; zero valid variants → unavailable.
    - The live check's routine line; vault contract §6.4.
  - [ ] **P2-R1b — Metrics, versions, away days, unknown lines** (~177 × 1.49 ≈ 264).
    - Metrics, and the collision check.
    - `routineLineUnknown`.
    - `RoutineHistory` in Core: append when (hash, partial) differs from the latest or the latest has ended; end only after a clean read, from the next day; a canonical hash that is the same in every process.
    - `routine_version` (no deletes, by trigger), and `capacity_exception` of kind `away` (question 26).
    - `AddCapacityException` and `RemoveCapacityException` with undo, back to the previous ISO week (question 34).
- [ ] **P2-R2 — Adherence in Core** (plain; ~310 × 1.49 ≈ 462).
  - The day's template: version, variant order (away without an away variant, a version with a skipped variant: not judged), ladders applied.
  - LT2b's `DayBoundaries.resolve`, reused; the second-source mark, computed when read.
  - Per block and day:
    - the states;
    - tolerances, with minutes claimed by one block only (question 32);
    - the counted class of the ledger, so native and workbook are never added;
    - running sessions;
    - the evidence rule (question 31);
    - paused lines from today on (question 33).
  - Week shares and metrics on judged days. Ladder suggestions on weeks under the current stage and the ladder's own variants. The "revise" fact.
  - DC's kind `routineBlockOpen`.
- [ ] **P2-RV — Routine views** (plain; ~400 × 1.49 ≈ 596; question 24). It needs a design round.
  - The Time view's shell (sidebar ⌘6) with a **Routine** week table: blocks by days, states as facts, metrics against their targets, ladder suggestions.
  - Ghost blocks under the facts on Today's day rail.
  - The away toggle (⌘K and the day's menu).
  - The Demo routine (invented, in `fixtures/vault/` and `DemoVault`).

**Health**

- [ ] **H — The Health bridge** (risky: outside data and storage; ~492, two PRs).
  - [ ] **H1 — The reader, the shared file guard, the live check** (~262 × 1.49 ≈ 390).
    - `InputGuards` (`BoundedFile` with a bounded read and `fileUnreadable`; `BoundedText`), shared with X1a.
    - The folder: `.notConfigured` without a bookmark, symlinks skipped, iCloud download status, near names and conflict copies counted, the newest 400 files.
    - The strict CSV, with the covered days on line 1 and one steps row per covered day (question 12).
    - Rows floored to the minute and split at midnight.
    - `moonshine-import health`, which prints counts only.
    - The setup doc for the shortcut: the fixed files and their rolling window, and that iCloud Drive keeps them end-to-end encrypted only with Advanced Data Protection, the owner's choice (owner, 2026-11-04).
  - [ ] **H2 — Sleep, storage and the import** (~230 × 1.49 ≈ 343).
    - The main sleep → wake and bed through LT2b's boundary-day function.
    - `Measurement` in ARCHITECTURE's shape.
    - Keys that survive duplicates.
    - Retention by day: a day is read only when every file covering it is readable (owner, 2026-11-01). A covered day with steps 0, no sleep rows and no workouts is `notRead(emptyDay)` and deletes nothing: a run on a locked phone looks exactly like that.
    - Workout labels stored and re-resolved when the alias file changes; an unavailable alias file keeps everything.
    - The ledger's Health rule (question 11).
    - Settings → Sources → Health; its own 60-minute timer.

**Workbook**

- [ ] **X1 — Workbook reader** (risky: parses outside data; ~305, two PRs). New target `ExcelAdapter` on CoreXLSX (pre-approved, rule 7), with ZIPFoundation as a direct dependency for a bounded pre-read (question 14). It reuses H1's file guard.
  - [ ] **X1a — Guards and the sheet list** (~139 × 1.49 ≈ 207).
  - [ ] **X1b — The grid, layouts and the live check** (~166 × 1.49 ≈ 247). With it, `docs/discovery/excel-contract.md` gains "Reader limits" (question 21).
- [ ] **X3 — Workbook rows: the mapping file, row kinds and the port** (risky: parses outside data; ~200 × 1.49 ≈ 298).
  - The `TimeSource` port and its typed read (`WorkbookSnapshot`, moved from X2).
  - The mapping file (bounded YAML; versions by first month; a label, optionally within a section and a group, to a line key, Life ops with an optional category, or `ignore`).
  - Row kinds by label; minute cells through `SourceTimeEntry`'s checks.
  - Context and indicator rows are recognised and ignored (owner, 2026-11-04). Ignoring them does not make the month partial, and a recognised row that is not imported does not count as skipped under the retention rule. `docs/discovery/excel-contract.md` says so from this spec's PR.
  - `unmapped` entries (question 15); `moonshine-import workbook <file> <mapping>`.
- [ ] **X4 — The workbook in the store and the import** (risky: changes what is stored; ~150 × 1.49 ≈ 224).
  - Replacing `excel` entries by key, in LT2a's table, under the retention rule.
  - `ImportService` reads again when the workbook or the mapping file changed; the cache is keyed on both (modification time and size of each). The trigger state is recorded only after a successful read, so a read that fails mid-save is retried.
  - Paths from the data folder (S4-4c).
- [ ] **X5 — Time view: the week of hours** (plain; ~400 × 1.49 ≈ 596). It needs a small design round.
  - The Week mode of `design/screens/time.md` § Week, beside P2-RV's Routine mode, over every stored source.
  - Lines by days, the Week and Budget columns, Life ops by category, Not mapped.
  - By the clock and In parallel from the timer, dictation and Health entries.
  - The two-sources mark, without choices.

**Timer, the rest**

- [ ] **TM4 — Today: the Tracked lane and Today so far** (plain; `DayBalance`, its "since" from the day's wake boundary; ~400).
- [ ] **TM5 — Time view: Day with editing** (~500). `EditTimeEntry`, `SplitTimeEntry`, `DeleteTimeEntry` and the overlap choice; the commands are risky, the view is plain.
- [ ] **TM6 — Settings → Time, Life ops categories, and the budget-note keys** `portion_h_day`, `break_after_min`, `check_after_h` (vault contract §1; ~350; risky for the keys).

**Plans and forecast**

- [ ] **F1 — Plans in Core** (plain; ~260 × 1.49 ≈ 387). Steps, estimates, effort levels (normal from the budget, ADR-0006; the line's template minutes shown beside it, question 28), capacity.
- [ ] **F2 — Plans in the store, with commands; measurements for metric steps** (risky; ~240 × 1.49 ≈ 358).
- [ ] **F3 — Plan editor** (plain; ~450 × 1.49 ≈ 670). It needs a design round.
- [ ] **F4 — Forecast engine: calibration and Monte Carlo** (plain, Core; ~400 × 1.49 ≈ 596). ADR-0006 § The engine and § Confirmation.
- [ ] **F5 — Forecast snapshots, weekly** (risky: storage; ~150 × 1.49 ≈ 224).
- [ ] **P2-RC — Line charts: plan, template and fact** (plain; ~300 × 1.49 ≈ 447; cut candidate 1, cut on 2026-11-01). One axis per line and week (ADR-0023 § Views).

**Vault-backed, last**

- [ ] **P1 — Memos on Today** (risky: parses vault notes; ~400 × 1.49 ≈ 596, two PRs; ADR-0018; cut candidate 2, cut on 2026-11-01). Cut, so Practice lines brings the `moonshine` scanner itself.
- [ ] **PL — Practice lines** (risky; ~350 × 1.49 ≈ 522, two PRs; ADR-0019). These paths follow nested lines to their parent:
  - a workbook row, an alias or a Health workout mapped to a nested line is recorded on its parent, with `excelRowMovedToParent` for the workbook (ADR-0019);
  - the line lists of Log by text, the timer and the routine skip nested lines;
  - `floorOpen` skips nested lines and lines measured by entries.
- [ ] **Q — Quotas** (risky; ~300 × 1.49 ≈ 447, two PRs; ADR-0020). With it, DC's `quotaTime` is offered.

**Outside the phase**

- [ ] **TR — Time reconcile** (ROADMAP row; risky: changes what is stored; ~300 × 1.49 ≈ 447).
  - The four choices, the stored decision per unit, the reconcile list and `Two sources · N` (`design/screens/time.md` § Two sources).
  - Nothing is lost while it waits: the native entries count and the pairs stay open (ADR-0016, amendment 2026-10-28).

## Cut list (first to cut first)

**A cut item is out of phase 2** (owner, 2026-11-01). It comes back only through phase 3's planning, or through the timebox review if there is room.

1. **P2-RC, line charts of plan, template and fact** (raw 300). The week adherence table (P2-RV) and the hours table (X5) already show the facts.
2. **P1, Memos on Today** (raw 400). Practice lines then brings the scanner.

Next if the timebox review needs more: 3. Q (300), then PL (350), to after the phase. 4. TM5's editing beyond `Change` and `Delete`.

## Pending design rounds (each before its slice)

- **Before LT4:** the Log by text window: the text field, the confirm list, every problem LT1 defines, the wake and bed rows; copy in EN and RU.
- **Before DC:** the checkpoint notification (one or two items, `Not today`, `Later`), the card, the in-app "turn it off?" row, Settings → Checkpoints; copy under the tone rule.
- **Before P2-RV:** the routine week table (states as facts: `6:52 · 22 min after 6:30`, `30 of 45 min`, no time, no data), ghost blocks on the day rail, ladder suggestions and the "revise" fact, the away toggle; copy in EN and RU; no "skipped" or "missed" in either.
- **Before X5:** the week table with workbook and Health entries: Not mapped, the unmapped list.
- **Before F3:** the plan editor.
- **Before P2-RC** (cut from phase 2): the charts of plan, template and fact.
- The existing items of `design/README.md` § Pending design rounds, "Before phase 2" (`design/README.md:331-336`; its items 1 and 2 are My take's, cut from phase 2) and "Before the Practice lines and Quotas slices" (`:344-346`).

## Changes to other documents, made with this spec's PR (dated 2026-11-01)

- **ADR-0005:** a dated amendment: provider and model are configurable; the port is provider-neutral; a model per feature; a key and a consent text per provider; the CI network rule per AI adapter target (§ Decided, Q8).
- **`docs/ROADMAP.md`, phase 2's row:** the timebox and the order; Log by text first and the first native slice; DC in the phase; the routine, Health and P2-RV slices; F6 and N1 cut; the iPhone capture question (`docs/ROADMAP.md:31`) answered.
- **`docs/method/forecast.md`:** phase 2's row in § Stages and the arithmetic above in § Basis.
- **ADR-0016:** dated amendments:
  - the sources `dictation` (stated) and `health` (measured);
  - wake and bed as day boundaries, with Health first;
  - `session` from TM1.
- **ADR-0013:** a dated amendment. A capture is interpreted before the Ask phase as a `confirm` command, with consent for cloud AI from LT3.
- **ADR-0006:** a dated amendment: the Board's capacity seeded from the routine template (phase 3).
- **`docs/ARCHITECTURE.md`:**
  - the ports gain `HealthSource` (question 36);
  - the domain table gains `Routine`, `RoutineVersion`, `CapacityException`, `DayBoundary` and `Measurement`, in ARCHITECTURE's shape.
- **CLAUDE.md rule 8:** the routine's block durations join the numbers the owner sets himself (question 35).
- **`design/tone-glossary.md`:** "skipped / пропущено" among the banned words, with P2-RV.
- **New ADRs:** ADR-0022, ADR-0023 and ADR-0024 added as proposed, with their rows in `docs/adr/README.md`.
- **Vault contract:** `routine` and `principle` reserved in §5, §6.4 in P2-R1a, the principle format reserved for phase 4.
- **Review round 1** (owner, 2026-11-04): `docs/discovery/excel-contract.md` (context and indicator rows ignored, X3); ADR-0017 (checkpoints in the notification planner, ADR-0022); ADR-0005 and `docs/ARCHITECTURE.md` (the endpoint rule); the screens and design notes that still called Timer (Mac) the last slice or My take the first native slice.

## Acceptance

- **Demo:** fresh clone → `scripts/xcbuild.sh build` → run → Demo mode works without OmniFocus, a vault, a workbook, a Health folder or an API key. Demo shows invented hours, an invented dictation, an invented routine with its adherence, and invented plans.
- **Log by text:**
  - an invented dictation gives the times the code computes;
  - no value only the model read goes unmarked;
  - nothing reaches the model before consent;
  - the capture is stored before the request;
  - undo removes exactly the confirmed entries and the day boundaries dictated with them.
- **The routine:**
  - the owner's routine note reads with no problems;
  - four weeks of adherence in the week table match what he remembers of those days, checked by him on his screen;
  - a day without data reads as "no data", never as a lapse.
- **Health:**
  - a week of the owner's day files reads;
  - the owner runs the shortcut once with the phone locked, and the result changes nothing that is stored (H's live check; owner, 2026-11-01);
  - wake and bed match his phone's sleep view for those days;
  - a second import writes no `changes` row.
- **The workbook:**
  - for two months the owner picks, each line's monthly total equals his workbook's own sum for the mapped labels;
  - a second import changes nothing;
  - a month that fails keeps its entries.
- **Plans and forecast:** ADR-0006 § Confirmation.
- **Timer (Mac):** of ADR-0016 § Confirmation, the Core tests, the nudge tests, the check-mark tests and the timer-slice acceptance. The rest is tested later: the reconcile tests with Time reconcile (TR, right after the phase), the assistant tests in the Ask phase (phase 4), the calendar tests with the slice that builds `calendar` entries (reserved, § Non-goals). Also the acceptance lists of `design/screens/timer-mac.md` and `time.md`; one working week tracked and compared by the owner with his workbook.
- **Day checkpoints:** ADR-0022 § Confirmation.
- **Speed:** the UI renders from the local store, any view in < 1 s.
- **Write and import checks:**
  - no write API to OmniFocus, the vault or EventKit (`scripts/check-vault-writes.mjs`);
  - the network API only in the AI adapter target, and nothing in Core names an AI vendor or a model id (LT3's two CI checks; AP2 passes them);
  - Core imports none of CoreXLSX, ZIPFoundation, XMLCoder, Security or UserNotifications (`scripts/check-core-imports.sh` gains them).
- **Tone:** the rules of CLAUDE.md rule 8 pass a copy review in English and Russian.

## Decided (owner, 2026-11-01)

The 36 questions below are accepted as proposed, with these exceptions:

- **Q8, the model.**
  - **Defaults.** The proposed models are the starting defaults. LT3 runs them on an eval of about 20 invented dictations (accuracy against cost) and records the result in its PR. If they don't do well, the default changes.
  - **The main requirement is that provider and model are configurable**, because other users will want other models (ADR-0005, amendment 2026-11-01). The cut and the eval command may change at LT3's planning; the configurability may not.
    - The `AIProvider` port in Core is provider-neutral: a request with a JSON-schema output, and a typed reply. Nothing in Core names a vendor.
    - Settings → Assistant lists the providers and keeps a model id per **feature** (Log by text now; checkpoints L2 and the routine assistant in phase 4). Each provider has its own key in the Keychain, and its own consent text. The endpoint's label and URL rule decided here were changed in review round 1 (owner, 2026-11-04): § Rules this phase adds, the endpoint rule.
    - LT3 ships one adapter, the Claude API. A small slice right after LT4, **AP2**, adds an OpenAI-compatible adapter with a configurable base URL. That also covers local servers such as Ollama or LM Studio.
    - Not "a weaker model never gives wrong data": swapped minutes between two activities pass the span check (critic, 2026-11-01). Every value is a checked span, shown beside its span highlighted in the owner's text; spans out of order against their activities are flagged (`spansOutOfOrder`); nothing is stored without the owner's confirmation. A weaker model costs more corrections, whatever the provider. LT1's checks do not prove that a value belongs to its activity: swapped minutes between two activities pass the span check, and the confirmation is the guard.
    - The eval set and a CLI command (`moonshine-import eval-dictation --provider … --model …`, counts only) run against any configured model, so a user can check his choice.
    - CI's network rule allows the network API in the AI adapter target only, not in one file.
- **Q30, the evidence base:** ADR-0024 takes the owner's revised format.
  - Evidence with design, status, level and outcome replaces the single grade; claim and conditions stay in frontmatter; citations are structured and verified only by the owner's date.
  - The rule catalogue (ADR-0024 § The data-rule catalogue) is built in phase 4. Its "after H", "after X2" mean the earliest a rule can be built, not when it is built; nothing from the catalogue lands inside a phase-2 slice.
  - The session kind is a new open question (37, below), decided at TM1's planning; dictation does not capture it in phase 2.
- **The critic's owner items (2026-11-01):**
  - Health on a locked phone: a day is read only when every file covering it is readable; a covered day with steps 0, no sleep rows and no workouts is `notRead(emptyDay)` and deletes nothing; H's live checks include one run with the phone locked, which changes nothing stored.
  - `manual` and `calendar`: out of phase 2, kept as reserved source values, with the calendar-based nudges (Non-goals).
  - ADR-0024's data rules: phase 4.
  - The session kind: decided at TM1's planning; dictation does not capture it in phase 2, so LT1a's schema stays as planned.
  - HealthKit: open item 38.
  - AP2 and the timebox: the timebox stays ~2027-01-27; the review after LT4 decides.
- **Q1, Q2, Q13: confirmed.** The order "time capture first" stands. The timebox runs until ~2027-01-27, with cuts P2-RC and P1. No iPhone capture before 3b.

## Open questions

37. **A session kind on time entries** (retrieval, reading, struggle; owner, 2026-11-01). Two of the owner's principles need it (ADR-0024 § The data-rule catalogue: `retrieval_share`, `hard_block_reading_share`). Should the timer and the dictation capture it? It could be a field on `TimeEntry`, a tag, or left out. Decided at TM1's planning, and left out of X2. Dictation does not capture it in phase 2, so LT1a's extraction schema stays as planned (owner, 2026-11-01).
38. **HealthKit in 3b** (owner, 2026-11-01). In 3b the iPhone app reads HealthKit, and its records sync to the Mac. That makes Health the first source imported on a device other than the Mac, against ADR-0010's "the Mac is the only importer". An open item for 3b's planning, with an ADR-0010 amendment then; the Health bridge stays until it is decided.
39. **`output_config.format` for the Haiku model** (review round 1, 2026-11-04). The default model ids match Anthropic's current model list; whether the cheaper one takes the JSON-schema output field is checked when the assistant's provider slices are planned (LT3, AP2). If it does not, its default changes.

## The questions of revision 2, with their proposals

All decided on 2026-11-01 as proposed, except as § Decided says.

1. **The order** — proposed: the owner's order above, plus P2-RV right after P2-R2 and P2-RC after F5, with TR after the phase. Confirm.
2. **The timebox** — proposed: until ~2027-01-27 with cuts P2-RC and P1; TR after the phase.
3. **Checkpoint times** — proposed: fixed 13:00 and 16:00; on a late day a checkpoint moves to the day's start + 3 h (ADR-0022, question 1).
4. **Checkpoint kinds** — proposed: all six (with `routineBlockOpen`), each with its own switch; `workShare` only once the owner sets its share (ADR-0022, question 2).
5. **What L2 may send to the model** — proposed: the delivered checkpoint's facts and the line names, under consent (ADR-0022, question 3). ADR-0024 adds the principle corpus.
6. **Checkpoint daily limit** — proposed: 3, settable 0–3; from 3b one limit across devices (ADR-0022, question 4).
7. **What Log by text sends to the model** — proposed: the dictated text, and the keys and names of the lines (not nested) and of the Life ops categories; nothing else.
8. **Which model** (changed: § Decided) — proposed: the Claude API, with the key in the Mac's Keychain; `claude-opus-5-5` at low effort, with `claude-haiku-5-5` as the owner's cheaper choice.
9. **Wake and bed on days without Health data** — proposed:
   - a dictated wake or bed is a day boundary;
   - a Sleep entry with clock times is the last source;
   - one Core function (LT2b) sets every boundary's day, so a bed before 06:00 belongs to the evening before.
10. **Health and dictation disagree on a boundary** — proposed:
    - Health (measured) is used;
    - a dictated one more than 15 min away is marked, and the mark is computed when read, never stored;
    - neither is deleted.
11. **How Health minutes count** — proposed (the H critic's recommendation):
    - a Health entry counts only outside the union of the owner's own clock intervals that day, whatever their unit;
    - against his own minutes-only capture of the same unit, the larger counts, never the sum;
    - against the workbook, ADR-0016's two-sources rule applies, with Health on the native side.
12. **The Health CSV** — proposed format (open until the owner tests his shortcut):
    - a fixed set of files that each run overwrites with a rolling window, so nothing accumulates in iCloud Drive (owner, 2026-11-04; was: one file per run, named after the last day it covers);
    - line 1 declares the format, its version and the covered days (up to 7; a 3-day window for late watch data);
    - exactly one steps row per covered day, so a locked-phone run deletes nothing;
    - sleep segments belong to the day of waking, by the window [D−1 18:00, D 18:00);
    - ISO 8601 times with offsets.
13. **A minimal iPhone capture before 3b** — proposed by the owner: no. Confirm.
14. **ZIPFoundation as a direct dependency** — proposed: yes (CoreXLSX already depends on it; it is not in `Adapters/Package.resolved` until X1). X1's plan states a version range compatible with CoreXLSX's.
15. **Unmapped workbook labels and workout names** — proposed: kept as `unmapped` entries with their minutes, shown as Not mapped.
16. **The Life ops reconcile unit** — proposed: (day, category); uncategorised workbook minutes form their own unit.
17. **`session` and `step` on `TimeEntry`** — proposed: added with TM1 and F2, by an ADR-0016 amendment.
18. **Derived time from action groups** — proposed: a group's estimate counts only when no descendant has one.
19. **Values only the model reads** — proposed: a fixed word table in code; any other model-read value is shown as such.
20. **Code and model disagree on a value** — proposed: blocking; the owner picks.
21. **The workbook contract** — proposed: amend it in X1b (reader limits; layout checked against the sheet's month). Its row kinds were amended with this spec's PR (owner, 2026-11-04; X3).
22. **Starting before the spec and the gate** — proposed: no; this spec merges first, and the gate holds.
23. **A dictation after midnight about the evening, without "yesterday"** — proposed: today's date, blocked by `endsAfterNow`.
24. **P2-RV** — proposed: the routine views right after P2-R2, so the routine is visible early; P2-RC (charts) as cut candidate 1.
25. **The routine note's frontmatter cap** — proposed: §3's 64 KiB. §6's 8 KiB is for kinds whose bodies are private; a routine's content is its frontmatter.
26. **"Away" days** — proposed:
    - a capacity exception of kind `away` that the owner sets (`AddCapacityException`, ADR-0013);
    - one record with F2's capacity exceptions;
    - not read from calendar events.
27. **The routine's move into MoonShine** — proposed: after phase 2, after P2-RV and a design round for the editor (ADR-0023 § The move to MoonShine).
28. **Template and budget** — proposed:
    - the budget stays the default `normal` level (ADR-0006);
    - the template's weekly minutes are shown beside it as a fact and seed the Board's capacity;
    - never reconciled automatically.
29. **X6, the workbook's indicator rows** — proposed: out of phase 2. Steps come from Health; historical wake and bed from the workbook are not imported.
30. **The evidence base** (ADR-0024; changed: § Decided) — proposed:
    - the grade scale is a list the owner keeps in Settings;
    - a citation counts as verified only with the owner's date;
    - data rules come from a fixed catalogue in code;
    - principles are read from the first phase-4 slice that uses them.
31. **Tracking evidence for "not tracked"** — proposed:
    - only what the owner records himself counts: timer, manual, dictation, a confirmed calendar entry, the workbook;
    - never a Health workout or an estimate.
32. **"Shifted" for flexible and protected blocks** — proposed:
    - shifted is the share reached only with minutes outside the window or span, with N the distance;
    - a line's clock minutes are claimed by one block only: anchors, then protected, then flexible.
33. **A paused line in the past** — proposed: it is not judged from today on; its past days keep their states until pause history exists.
34. **How far back an away mark may go** — proposed:
    - today and up to 400 days ahead;
    - plus the running and the previous ISO week, to fix a forgotten mark without re-grading older weeks.
35. **Rule 8 and the template's hours** — proposed: rule 8 names the routine's block durations among the numbers the owner sets himself, so `template 4 h / week` may be shown.
36. **A new port, `HealthSource`** — proposed: its own port in `docs/ARCHITECTURE.md`, which HealthKit implements in 3b, added with the spec's PR.
