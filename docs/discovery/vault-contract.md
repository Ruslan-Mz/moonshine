# Vault contract (Obsidian → MoonShine), v0.7

Status: **draft from phase-0 discovery** (see `data-report.md`). Implements ADR-0004: YAML frontmatter is the machine-readable truth; markdown bodies stay human text and are read for links and tags only, never for values (from the Hub slice; ADR-0014). Two exceptions (v0.4): a memo's two sections are read (§6.1), and an entry note's body is never read (§6.3).

v0.2 (2026-10-01, design draft-2): optional line keys `foundation`, `floor_h_day`, `language`; quarter notes with `scale: quarter` and `artifacts:` (§2.2); R1 keys `done`, `carried_to`, `active_lines` (read from R1 on).

2026-10-05 (S3b): the budget note is found by its key only (§1); the reader's limits for untrusted input (§3).

2026-10-08 (S3b-2b+2c): `lines:` items are validated (§1, "Validation of `lines:`"); any invalid value skips its item.

v0.3 (2026-10-08, ADR-0014, ADR-0015, ADR-0016): project notes (§4) and reserved keys and values (§5), all reserved now and read from the slice or phase named at each; line key `portion_h_day` (§1); note bodies read for links and tags (§3, from the Hub slice); Obsidian's settings files for daily and weekly notes (§3, from the Write phase).

2026-10-10 (S3b-3, owner): artifact identity is `id` + period and carries keep the `id` (§2.1–2.2); the artifact `id` rule and the caps for notes and artifacts (§2, §2.1); the budget note is stored as a note (§2); what is kept when a note cannot be read or is no longer recognised (§3); several notes for one period (§2.1). The reader applies the note rules from S3b-3b and the artifact rules from S3b-3c; the importer's rules are in place since S3b-3a.

2026-10-12 and 2026-10-13 (S3b-3b, owner): the shapes of dates and which key takes which; where a period starts and ends; an explicit `scale` is only checked; the year in a legacy file name; a `focus` note with no year is the current one; a list of target years only on a corridor, at most 20 years, and `period` at most 256 bytes; `horizons` is checked; while the budget marker is ambiguous every marked note is kept as unread; the paths the reader names (§2, "Made precise in S3b-3b").

2026-10-14 (S3b-3c-1, owner): at most 100 `artifacts:` items per note (§2.1); the rules made precise for artifacts: the period key of a year and of a quarter, the problem keys, what "one period" means and which items the duplicate check counts (§2.1, "Made precise in S3b-3c").

2026-10-15 (S3b-3c-2, owner): a line's `parent` is resolved as ADR-0014 says: case ignored, the shortest matching path, an ambiguous link reported as `ambiguousLink` (§2.3).

v0.4 (2026-10-19, ADR-0018, ADR-0019, owner): note kinds by the `moonshine` key and one scanner for them (§6); memo notes (§6.1, read from P1), programme notes (§6.2, kind reserved), entry notes (§6.3, read from Practice lines); the optional line keys `within`, `measure` and `targets` (§1, "Practice lines", read from Practice lines); entry bodies are never read (§3).

v0.5 (2026-10-26, ADR-0020, ADR-0021, owner): the optional line key `quota_emphasis` (§1, "Quota emphasis", read from the Quotas slice); module note kinds found by the owner's own `type` key, the Library module first (§7, read from Library L1).

v0.6 (2026-10-28, ADR-0016, owner, design draft-5): the optional line keys `break_after_min` and `check_after_h` (§1, "Nudge values", read from the Timer slice): a line's own break-nudge minutes and check limit, over the defaults in Settings → Time.

v0.7 (2026-11-01, ADR-0023, ADR-0024, owner): `moonshine: routine` and `moonshine: principle` reserved (§5). The routine note is read from P2-R1, which writes §6.4 (its frontmatter under §3's 64 KiB cap, not §6's 8 KiB); principles from phase 4.

Scope: what the phase-1 `ObsidianAdapter` reads. It never writes (no vault writes before the Write phase; ADR-0015).

## Design choices driven by the data

1. **Existing keys are honoured as-is.** The vault already has `type`, `parent`, `period_start`/`period_end`, `month`, `year`, `horizons` on its horizon notes. The reader derives `scale` and `period` from them, so the owner only has to make **three edits**: the `moonshine: budget` marker and the `lines:` block (budget note), and `artifacts:` (year note).
2. **Artifacts are list items, not notes.** Year artifacts and quarter focuses live as table rows / headings inside one note each. The contract puts them in a frontmatter list in that note rather than asking for one note per artifact.
3. **New key `scale`, not `horizon`** (decision Q1, 2026-09-30). 18 existing notes use `horizon:` as a human phrase (a year range or duration plus a comment); MoonShine never reads `horizon` and never asks to change it. The machine-readable level of a note is `scale`.

## 1. Lines — the budget note

Identified only by `moonshine: budget` at the top level of the frontmatter (no file-name fallback: a file name is the owner's data). Rejected notes count too: a note whose frontmatter failed to parse is searched lexically for a top-level `moonshine: budget` line (quotes around the key or the value and a trailing comment allowed). Exactly one marked note that parsed → the budget note; exactly one that was rejected → lines unavailable, `budgetNoteRejected` on that note next to its own problem, and the live check prints `rejected (<kind>)`; more than one, parsed or not → ambiguous: lines unavailable, `budgetNoteDuplicate` on each, none wins (the owner removes the marker from the copy); none → the vault-wide problem `budgetNoteMissing` (no path). Known gap: a note whose frontmatter cannot be extracted (unreadable, not UTF-8, over the size cap, never closed) cannot be searched.

The reader says whether it could read the lines, not only which ones it read (2026-10-07):

- **Unavailable** — the budget note is missing, rejected or ambiguous (more than one marked note), or its `lines:` is missing, not a list or an empty list. The stored lines stay as they are and keep mapping tasks.
- **Read with skipped items** — the lines read are updated; no stored line is removed.
- **Clean read** — note found, list parsed, no item skipped. Only then does a line missing from the list leave the store (soft delete). More than 3 leaving at once are held until the owner approves exactly that set; a set held once stays held until approved or back (S4-4e; `docs/specs/phase-1-see.md`, the mass-removal rule under S4).

```yaml
moonshine: budget # required marker: the only way the budget note is found
active_lines: { min: 3, max: 5 } # optional (v0.2, read from R1): the "3–5 active lines" rule as data
lines: # order = display order within a block
  - id: violin # required. slug [a-z0-9-]+, unique, never renamed (ids survive renames of `name`)
    name: Violin # required. display name, any script
    emoji: "🎻" # optional
    block: Creative # required. free string; blocks are displayed in first-appearance order
    state: active # required. active | maintenance | paused
    budget_h_week: 6 # optional number ≥ 0; null/absent = no weekly budget ("no schedule")
    foundation: false # optional (v0.2); true = foundation tier (the spine), shown first, never "quiet"
    floor_h_day: null # optional number ≥ 0 (v0.2); daily minimum, on any line
    portion_h_day: null # optional number ≥ 0 (v0.3, reserved; read from the Timer slice, ADR-0016); the day mark's portion when the line's calendar has no events today
    break_after_min: null # optional integer 10…240 (v0.6, reserved; read from the Timer slice, ADR-0016); the break nudge's N for this line
    check_after_h: null # optional number 1…24 (v0.6, reserved; read from the Timer slice, ADR-0016); the check-mark limit for this line
    language: it # optional BCP-47 tag (v0.2); language lines only. Parsed and stored; a content-language detection hint
    parent: "[[Artifacts_2026]]" # optional wikilink to the note that holds this line's artifact(s)
    omnifocus: # how OmniFocus items map to this line (see snapshot-contract.md §Mapping)
      tags: [violin] # tag names, exact match on the tag's own name (not full path)
      folders: [] # top-level folder names; every project inside maps to this line
      projects: [] # project names, for one-off exceptions
```

Rules

- Tier (UI grouping) = `foundation: true` → Foundation, else `state` → Active this season / Maintenance / Paused on purpose. `block` is a secondary label.
- `floor_h_day` is allowed on any line (owner, 2026-10-08); `foundation: true` decides only the tier and the "never quiet" rule. A line may have both `floor_h_day` and `budget_h_week`: a foundation line shows the floor; any other line shows the floor as a daily minimum next to its weekly budget (exact form, decided in design draft-5: `4 h / week` over `floor 20 min/day`, `design/screens/lines.md` § Draft-5).
- `state: paused` = "paused on purpose" in the UI. It is never shown as missing activity.
- Tasks that match no line belong to **Life ops** (not a line; see `snapshot-contract.md`).
- A task maps to **at most one** line. Precedence: task tag → project tag → project name → folder. Two lines claiming the same tag/folder → banner naming both line ids; first in list wins.
- Hours shown for a line come only from real time data or from numbers the owner set himself: the vault values `budget_h_week`, `floor_h_day` and `portion_h_day`, the length of events in the line's calendar (the day portion of ADR-0016; owner, 2026-10-08), and the block durations of the routine template (ADR-0023; owner, 2026-11-01) — CLAUDE.md rule 8 / ADR-0006.
- The markdown table in the note may stay; the YAML block is authoritative for MoonShine (ADR-0004).

Validation of `lines:` (owner, 2026-10-07 and 2026-10-08):

- Numbers match `^[0-9]+(\.[0-9]+)?$` (no sign, exponent, hex, `nan`, `inf` or decimal comma); `budget_h_week` 0…168, `floor_h_day` 0…24.
- `id` `[a-z0-9-]+`, at most 64 characters, unique; `name` 1–120 characters and at most 1 KiB, `block` 1–60 characters and at most 512 bytes, `emoji` 1–8 characters and at most 256 bytes; characters are grapheme clusters (what a limit means to a reader), bytes are UTF-8, and a value over either limit is invalid (owner, 2026-10-08: a cluster can hold any number of combining marks); `state` one of the three values; `foundation` only `true` / `false`; `language` shaped `^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$`, at most 35 characters; each `omnifocus` list at most 100 names of at most 200 characters and 1 KiB; no string value (`name`, `block`, `emoji`, `language`, `parent`, `omnifocus` names) may hold a C0 control character (U+0000–U+001F) or DEL (U+007F): the store's text columns end at a NUL; `parent` is stored as written.
- `null` is the same as an absent key.
- Any missing, invalid or duplicate value skips its item: the stored line stays exactly as it was and the read is incomplete (no stored line is removed). Problems: `missingKey`, `invalidValue`, `duplicateLineId` (every item with that `id`; none wins), each with its key path (`lines.state`, `lines.omnifocus.tags`) and line; every problem of an item is reported.
- `lines:` absent or `null` → `missingKey`; not a list, or an empty list (`lines: []`) → `invalidValue`. Each leaves the lines unavailable: an empty list is more often a broken edit than "no lines", and as a clean read it would remove every stored line.

### Practice lines (v0.4, reserved now; read from the Practice lines slice, ADR-0019)

Three optional keys on a `lines:` item. A budget note without them reads as before.

| Key       | Values                                                 | Meaning                                                  |
| --------- | ------------------------------------------------------ | -------------------------------------------------------- |
| `within`  | the `id` of another line                               | The line is nested; its time belongs to that parent      |
| `measure` | `hours` (default) · `entries`                          | What the line is measured by                             |
| `targets` | list of `{kind, count, per}`, `per` ∈ `week` · `month` | Entry targets, e.g. diary 5 per week, report 1 per month |

```yaml
lines:
  - id: core-study
    name: Core study
    block: Study
    state: active
    budget_h_week: 10
  - id: reflection
    name: Reflection
    block: Study
    state: active
    within: core-study # nested: its time is recorded on core-study
    measure: entries # counted from entry notes (§6.3)
    targets:
      - { kind: diary, count: 5, per: week }
      - { kind: report, count: 1, per: month }
```

Rules

- **One level of nesting.** A parent has no `within`.
- **The parent is measured by hours.**
- **A nested line, and every `measure: entries` line, has no budget.** A budget above 0 is ignored with `lineBudgetIgnored`, nested or not. Such a line is never part of shortfall, forecast or the budget total. A line read as not nested because of a nesting problem keeps the rule of its measure: an entries line's budget is still ignored; an hours line's budget counts.
- **Time goes to the parent, always, from every source** (ADR-0016): timer, task, calendar, manual and workbook. The timer's line picker, the quick log and voice `LogTime` do not offer nested lines. A workbook row mapped to a nested line is recorded on its parent, with the info problem `excelRowMovedToParent` (`excel-contract.md`).
- `measure: entries` without `within` is allowed: a practice with no parent spends no planned time.
- **Targets are per week or per month;** `per: day` is invalid (`invalidValue` on `lines.targets`).
- A line with `measure: entries` shows entries and regularity, never hours (rule 8 of `CLAUDE.md`).

Problems (the other lines still read when one line has a problem):

| Kind                 | When                                                                   | Effect                         |
| -------------------- | ---------------------------------------------------------------------- | ------------------------------ |
| `lineParentMissing`  | `within` names no line                                                 | The line is read as not nested |
| `lineNestedTooDeep`  | the parent has its own `within`                                        | The line is read as not nested |
| `lineParentNotHours` | the parent has `measure: entries`                                      | The line is read as not nested |
| `lineBudgetIgnored`  | a nested line, or a line with `measure: entries`, has a budget above 0 | The budget is ignored          |

### Quota emphasis (v0.5, reserved now; read from the Quotas slice, ADR-0020)

One optional key on a `lines:` item: how loudly a period quota of the line's tasks shows a period that ended short. A budget note without it reads as before.

| Key              | Values                         | Meaning                                                                             |
| ---------------- | ------------------------------ | ----------------------------------------------------------------------------------- |
| `quota_emphasis` | `neutral` (default) · `strong` | The default emphasis of the quotas on this line's tasks; `null` or absent = neutral |

```yaml
lines:
  - id: reading
    name: Reading
    block: Study
    state: active
    quota_emphasis: strong # a period of this line's quotas that ended short shows in amber
```

Rules

- The quotas themselves live in OmniFocus tag names (`snapshot-contract.md` § Quota tags), not in the vault.
- **Precedence:** a trailing `!` on the task's quota tag → the line's `quota_emphasis` → neutral.
- **An invalid value does not skip the line** (unlike the other keys of "Validation of `lines:`"): the line is read, its emphasis is neutral, and the problem `lineQuotaEmphasisInvalid` names the key path `lines.quota_emphasis` and the line.

| Kind                       | When                              | Effect                         |
| -------------------------- | --------------------------------- | ------------------------------ |
| `lineQuotaEmphasisInvalid` | `quota_emphasis` is neither value | The line's emphasis is neutral |

### Nudge values (v0.6, reserved now; read from the Timer slice, ADR-0016)

Two optional keys on a `lines:` item (owner, 2026-10-28). ADR-0016 makes the break nudge's N and the check-mark limit per line; these keys carry the line's own values, over the defaults in Settings → Time (50 min, 4 h). A budget note without them reads as before.

| Key               | Values             | Meaning                                                                                                                                |
| ----------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| `break_after_min` | an integer, 10…240 | Minutes of continuous activity before the break nudge; with several sessions running, the smallest N of their lines applies (ADR-0016) |
| `check_after_h`   | a number, 1…24     | Hours a session of this line may run without a pause before it gets the check mark                                                     |

```yaml
lines:
  - id: research
    name: Research
    block: Profession
    state: active
    break_after_min: 25 # a short break nudge on this line only
    check_after_h: 6 # long writing sessions are normal here
```

Rules

- `null` or absent = the Settings → Time default. Numbers follow "Validation of `lines:`" (`^[0-9]+(\.[0-9]+)?$`); `break_after_min` must also be a whole number.
- **An invalid value does not skip the line** (like `quota_emphasis`): the line is read, the default applies, and the problem `lineNudgeValueInvalid` names the key path (`lines.break_after_min`, `lines.check_after_h`) and the line.
- Life ops categories are not lines: their values are set in Settings → Time (`design/screens/settings.md` § Time).

| Kind                    | When                                                                     | Effect              |
| ----------------------- | ------------------------------------------------------------------------ | ------------------- |
| `lineNudgeValueInvalid` | a value out of range, not a number, or `break_after_min` with a fraction | The default applies |

## 2. Horizon and artifact notes

Common frontmatter keys (all notes MoonShine reads as `NoteRef`):

| Key       | Type     | Meaning                                                                                                                                                                              |
| --------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `type`    | string   | Required for recognition. Values below. A comma list (`"a, b"`) is read as its first item.                                                                                           |
| `scale`   | enum     | `week` · `month` · `quarter` · `year` · `years` · `lifetime`. Optional when derivable (table below).                                                                                 |
| `horizon` | —        | Not read by MoonShine; stays free text for the owner.                                                                                                                                |
| `period`  | string   | `YYYY-Www` · `YYYY-MM` · `YYYY-Qn` · `YYYY` · `YYYY..YYYY` (range) · on a `horizon_corridor` only, `YYYY,YYYY,…` (list of target years). At most 256 bytes. Optional when derivable. |
| `parent`  | wikilink | Next note up the thread (month → quarter → year → corridor → long horizons). Path-qualified links allowed.                                                                           |
| `line`    | line id  | Optional. Ties a note to one line.                                                                                                                                                   |
| `status`  | string   | Passed through; MoonShine maps `active`/`draft`/`living` → current, `archived`/`closed`/`superseded` → past. Unknown values → current.                                               |

Recognised types and derivation of `scale` / `period` when they are absent:

| `type`                  | Derived `scale` | Derived `period` from                                                                                                                   | Found in vault                                   |
| ----------------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `month_plan`            | `month`         | `month: YYYY-MM`, else `period_start`                                                                                                   | 3 notes, name `Месяц_YYYY-MM`                    |
| `quarter_focus`         | `quarter`       | `quarter`, else `period_start` → `YYYY-Qn`                                                                                              | 2 notes, name `Qn_YYYY_focus`                    |
| `year_artifacts`        | `year`          | `year: YYYY`                                                                                                                            | 1 note, name `Артефакты_YYYY`                    |
| `horizon_corridor`      | `years`         | `period_start..period_end` (ints or dates); only `horizons: [YYYY,…]` → no scale or period until the Zoom out phase (owner, 2026-10-05) | 2 notes                                          |
| `yearly-goals`, `focus` | `year`          | `year`, else 4-digit year in filename                                                                                                   | 2 legacy journal notes (read-only, low priority) |
| `lifetime` _(new)_      | `lifetime`      | —                                                                                                                                       | 0                                                |

Weekly review notes (`YYYY-Www`, journal) currently have no frontmatter; phase 1 does not need them.

Rules (owner, 2026-10-10; read from S3b-3b):

- The budget note (§1) is stored as a note too, whatever its `type`. Notes of any other type are not stored.
- `title` is optional: a note without it takes its file name without `.md`. A file name that breaks the title caps skips the note with `invalidValue` on `notes.title`, like any invalid value (owner, 2026-10-10).
- Caps: `title` 1–200 characters and at most 1 KiB; `type` at most 60 characters; `status` 1–60 characters and at most 512 bytes; `parent` at most 1 KiB; `line` by the line `id` rule; years 1900–2199; a range of years at most 200. Characters, bytes and control characters as in §1.
- A week must exist in its ISO year (`2025-W53` is invalid), a day in its month.
- A source key that is present in another shape is `invalidValue`; so is an explicit `scale` that disagrees with the period. Any invalid value skips the note: the stored note stays as it was (§3).
- No period key at all: a `month_plan`, `quarter_focus` or `year_artifacts` note is skipped with `missingKey`; a `yearly-goals` or `focus` note takes the year from its file name (table above) and is read without a period only when it has no `year` key and no year in its file name; a `horizon_corridor` without `period_start` / `period_end` and without `horizons` gets no scale and no period.

Made precise in S3b-3b (owner; each rule accepted or decided on 2026-10-13 unless it names another date):

- Dates are written with ASCII digits in these shapes only: `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, `YYYY-Www`, `YYYY-Qn`. Each source key takes its own shapes: `month` a month; `quarter` a quarter; `year` a year; `period_start` of a month or quarter note a day or a month; `period_start` and `period_end` of a corridor a year, a month or a day. The first source key that is present decides, and a later one is not read. With an explicit `period`, no source key is read. A list of target years (`YYYY,YYYY,…`, spaces after a comma allowed) is a `period` of a `horizon_corridor` only, with at most 20 years: it gives no scale and no period until the Zoom out phase. On a note of any other type, the budget note included, it is `invalidValue` on `notes.period` and the note is skipped (owner, 2026-10-13). A `period` is at most 256 bytes (owner, 2026-10-13).
- A period starts and ends at midnight in the workspace's time zone. A corridor runs from the start of `period_start` to the end of `period_end` (the day after an end date, 1 January after an end year); its scale counts calendar years, the end year minus the start year plus one. An end that is not after the start is `invalidValue` on `period_end`.
- An explicit `scale` is only checked: the stored scale comes from the period, or from the type when there is no period. Where the reader has no scale of its own (a corridor with a list of target years or with `horizons` only, the budget note of another type), a valid `scale` is accepted and not stored: `years` has no count without a period.
- In a legacy file name, the year is the first run of exactly four digits that is a year from 1900 to 2199; other runs of digits are passed over.
- A `focus` note with no `year` key and no year in its file name is the current one, by design: it is read with scale `year`, no period and no problem, like a corridor with only `horizons` (owner, 2026-10-13; this changes the rule of 2026-10-10 for `focus` only).
- Read with a problem, not skipped: a `yearly-goals` note with no year anywhere (scale `year`, no period, `missingKey` on `period`); a corridor with only one of `period_start` / `period_end` (no scale, no period, `missingKey` on the other key), or with neither and no `horizons` (`missingKey` on `period`). `horizons` counts only as a non-empty list of at most 20 years from 1900 to 2199; in any other shape it is `invalidValue` on `notes.horizons` and the note is skipped, with or without period keys (owner, 2026-10-13).
- The reader names the paths it saw and did not store (§3): every Markdown file of another type or without frontmatter is "not recognised"; every rejected, unreadable or skipped note, and every entry the walk skipped or could not enter, is "unread". An invalid `type` on the budget note skips it as a note only; its `lines:` are still read.
- While the budget marker is ambiguous (more than one marked note, §1), none of the marked notes is the budget note and none is read as a note: each is "unread", so its stored note stays as it was, nothing new is stored for it, and `budgetNoteDuplicate` is its only problem. The budget note is stored as a note only when exactly one note is marked and it parsed (owner, 2026-10-13).
- The reader returns notes in path order, and `DemoVault.snapshot.notes` is kept in that order for the golden test (owner, 2026-10-12).
- `moonshine-import vault` reads in the local time zone of the machine: it prints counts only, and no count depends on the zone. The app passes the workspace's time zone from S4.

### 2.1 Artifacts inside the year note — new block

```yaml
type: year_artifacts
year: 2026
artifacts:
  - id: a26-01 # required. stable; unique within its period, and kept when the artifact is carried (below)
    title: First paper draft # required
    line: research # optional line id (one); use `lines: [a, b]` for shared artifacts
    status: in_progress # planned | in_progress | done | dropped
    priority: true # optional; "priority" vs "the rest" group
```

Item rules (owner, 2026-10-10; read from S3b-3c):

- `id`: `[a-z0-9-]`, 1–64 bytes, the line `id` rule. `title`: 1–200 characters, at most 1 KiB. `line` is one line id, `lines` a list of at most 20; both together are invalid, neither is allowed. `status` absent or null is read as `planned`. `priority` only `true` / `false`.
- An item with a missing or invalid value is skipped; the stored artifact stays as it was, in its place (§3).
- `artifacts:` absent, null or empty means the note has no artifacts. `artifacts:` that is not a list is `invalidValue`; the note's stored artifacts stay.
- At most 100 items in one note's `artifacts:` (owner, 2026-10-14). More is `invalidValue` on `notes.artifacts`: no item of that note is read, and its stored artifacts stay.

Made precise in S3b-3c (owner, 2026-10-14):

- An item's period key is `YYYY` for a year period and `YYYY-Qn` for a quarter period. A `year_artifacts` or `quarter_focus` note whose `period` has another scale (a week, a month, a range of years) and a non-empty `artifacts:` gets `invalidValue` on `notes.artifacts`; its stored artifacts stay. Such a note takes no part in "several notes for one period": two of them for the same week are each refused, neither is `duplicatePeriodNote`.
- Problem keys: `artifacts.id`, `artifacts.title`, `artifacts.line`, `artifacts.lines`, `artifacts.status`, `artifacts.priority` for an item; `notes.artifacts` for the list and for an item that is not a mapping; `notes.period` for `duplicatePeriodNote`. `line` and `lines` together is `invalidValue` on `artifacts.lines`, and so is a `lines` list with an id twice; an empty `lines` list means no lines.
- "One period" means the same year or quarter, among the year and quarter notes that are read. The duplicate check counts every item with a valid `id` in a list that is read, an item invalid for another reason included, so every problem is reported in one pass.

**Identity and carries (owner, 2026-10-10).** An artifact is identified by its `id` plus the period of the note it is in (a year or a quarter). An artifact that is not finished in its period is carried: the owner copies the item into the next note with the same `id` and marks the old one with `carried_to`. Each appearance is stored separately, so the history survives: the first appearance, the number of carries, the outcome in each period. Trace and the Quarter focus card use the appearance whose period contains "now".

- The same `id` in two notes whose periods do not overlap is a carry.
- The same `id` twice in one note, or in two notes of different periods that overlap (a year and one of its quarters), is `duplicateArtifactId`: every such item is skipped, none wins.
- Several notes for one period (two quarter notes for the same quarter, two year notes for the same year: a copy not yet changed, a sync conflict copy) are not duplicates of each other: the first by path wins and only its `artifacts:` are read. Each other note gets the problem `duplicatePeriodNote` with its path, and its stored artifacts stay as they were (§3). Read from S3b-3c (owner, 2026-10-10; moved from the Quarter focus card into the reader).
- The duplicate check runs over the lists that were read: every item in them with a valid `id` counts, an item invalid for another reason included, as for `lines:` (owner, 2026-10-15). While a duplicate is in the vault, what is stored can therefore depend on what could be read: if one of the two notes is unreadable during an import, the other note's item is read and stored, and it stays next to the first one when both notes are readable again and both items are skipped. The duplicate is reported on every import in which both notes are read, until the owner removes one of the two.

One carry, from Q3 to Q4:

```yaml
# Q3_2026_focus.md — period 2026-Q3
artifacts:
  - id: recital-programme
    title: Spring recital programme chosen
    line: violin
    status: in_progress
    carried_to: 2026-Q4 # R1
```

```yaml
# Q4_2026_focus.md — period 2026-Q4
artifacts:
  - id: recital-programme
    title: Spring recital programme chosen
    line: violin
    status: done
```

Two carries with a changed title, over three years; the store holds three appearances of `b1-certificate`:

```yaml
# Artifacts_2026.md — year 2026
artifacts:
  - id: b1-certificate
    title: Italian B1 certificate
    line: italian
    status: in_progress
    carried_to: 2027
```

```yaml
# Artifacts_2027.md — year 2027
artifacts:
  - id: b1-certificate
    title: Italian B1 certificate, written part
    line: italian
    status: in_progress
    carried_to: 2028
```

```yaml
# Artifacts_2028.md — year 2028
artifacts:
  - id: b1-certificate
    title: Italian B1 certificate, oral part retaken
    line: italian
    status: done
```

The quarter note may reference them (optional, the Zoom out phase uses it; phase 1 only shows the trace):

```yaml
type: quarter_focus
period_start: 2026-10-01
period_end: 2026-12-31
parent: "[[Artifacts_2026]]"
focus:
  - title: Violin restart as a habit
    line: violin
    artifact: a26-03 # optional artifact id
```

### 2.2 Quarter note with artifacts (v0.2)

A quarter note may carry its own `artifacts:` list, same item shape as the year note (§2.1). Phase 1 shows it in the Today **Quarter focus card** (current quarter; title, line, `status` → done / not done).

```yaml
type: quarter_focus
scale: quarter
period: 2026-Q4 # or derived from `quarter` / `period_start` as for quarter_focus
parent: "[[Artifacts_2026]]"
artifacts:
  - id: q4-recital-programme
    title: Spring recital programme chosen
    line: violin
    status: done # planned | in_progress | done | dropped
    done: 2026-10-12 # optional (R1): date the artifact was finished
  - id: q4-etudes
    title: Six études at tempo
    line: violin
    status: in_progress
    carried_to: 2027-Q1 # optional (R1): set during the quarterly review, on an artifact not finished in its period
```

`done` and `carried_to` (and the budget note's `active_lines`) are read from R1 on (quarterly review); before that the reader ignores them like any unknown key. Several quarter notes for the same period → the first by path wins and the others get `duplicatePeriodNote` (§2.1, from S3b-3c); the card shows the first.

### 2.3 Trace (phase 1)

`task → project → line (via omnifocus mapping) → artifact (the line's artifact in the current year note, else the line's `parent` note)`. A line with no artifact shows the trace up to the line — neutral, no warning.

Resolving a `parent` follows ADR-0014 (owner, 2026-10-15): `[[Name]]`, `[[Name|alias]]` and `[[Name#heading]]` match a note whose file name is `Name`; a path-qualified `[[Folder/Name]]` matches a note whose path equals it or ends with `/Folder/Name` (so `A/Name` never matches `BA/Name`); `[[/Folder/Name]]` matches from the vault root only. Case is ignored in every script (Cyrillic included), and `.md` is optional. Of several matching notes the shortest path wins (then the first by path), and the link is ambiguous: the reader reports `ambiguousLink` on `lines.parent` and still reads the line. The trace resolves a parent against the stored notes (read, or kept while unread, §3); a parent that matches none ends the trace at the line, with no problem. The live check, which has no store, counts the line parents that match no note read, and the ambiguous ones.

## 3. Validation

- Invalid YAML or a `lines:` item with a missing, invalid or duplicate value (§1) → one calm banner with note path and line number; the rest of the vault still loads. Never a crash.
- Problems are typed (`VaultProblem`: a kind and, at most, a contract key name) with the note's vault-relative path and line; they never carry note content. A vault-wide problem (`budgetNoteMissing`) belongs to no note, so it is reported without a path (`ImportIssue.vaultWide`).
- The vault is untrusted input (synced or pasted from elsewhere). One guard per threat:
  - **leaving the vault:** symbolic links are skipped (`symlinkSkipped`); every resolved path must stay under the resolved vault folder (`outsideVault`; defence in depth behind the symlink skip, for a link swapped in during the walk); a folder the walk cannot enter is `unreadable`, never a silent gap;
  - **size:** at most 20,000 notes (more stops the read with a typed error; nothing from the vault is imported, the tasks still are, and the import stores `vaultTooLarge`, S4-4d), frontmatter at most 64 KiB (`frontmatterTooLarge`);
  - **YAML:** checked lexically before parsing, coarse on purpose (quotes are not tracked, so a false positive rejects a note, never lets one through):
    - **anchor with alias** (`yamlAnchor`, counted on its own so false positives show): Yams expands aliases while parsing, before any cap can run, and an alias needs an anchor, so a note is rejected only when its frontmatter has both an anchor candidate and an alias candidate. Anchor candidate: an `&` followed by a non-blank that is not a flow indicator; an `&` right after a letter, combining mark or digit of any script (`R&D`, `Музыка&танец`, `音楽&舞踊`) is plain text, because a YAML token starts only after whitespace or an indicator. Alias candidate: a `*` followed by a non-blank (Markdown `**bold**` counts too). An anchor alone only labels its node and is accepted; the live check counts these notes ("anchor-like text and no alias, accepted"). An alias alone fails in Yams as `malformedYAML`;
    - **directive** (`yamlDirective`): a `%` at the start of the frontmatter or right after any line break libyaml knows (LF, CR, NEL, LS, PS), byte-order marks in between skipped. A `%TAG` prefix is copied into every tag that uses it (228 MB peak from 64 KiB of frontmatter, measured on Yams alone). A quoted scalar's continuation line that starts with `%` is rejected too (accepted false positive);
    - **nesting** at most 32, also before parsing (`yamlTooComplex`): the deepest flow nesting (`[`, `{`) plus a bound on block nesting, two levels for each distinct column where a block collection can open (a line's first token, and the token after each `- `, `? ` or `: `), lines split at every line break libyaml knows, a byte-order mark at a line's start taking a column as libyaml counts it (PR #53 round 1), block-scalar content skipped only as far as libyaml reads it as content (S4-4d; a 64 KiB run of `- - - …` would otherwise reach Yams about 32,000 levels deep). The bound never counts below Yams' depth (a seeded differential test); a false positive rejects a note. After parsing, at most 10,000 nodes and depth 32 per note (`yamlTooComplex`).
  - **owner-only paths:** `moonshine-import vault --paths` prints each problem's kind, vault-relative path and line, nothing from the note. Its help text says it is for the owner's own terminal, and the tool enforces it: it refuses to run unless standard output is a terminal, checked before anything is read. A printed path shows every control and format character and a backslash as an escape (`\u{…}`, `\\`);
  - **line breaks:** the frontmatter ends only at a `---` line after LF. A `---` after CR, NEL, LS or PS is not a delimiter for the reader but starts a second document for libyaml, so the note fails safe as `malformedYAML`.
- **Failed is not empty (owner, 2026-10-10).** A stored note or artifact leaves the store only when the read saw that it is gone:
  - a note that exists and could not be read (rejected, unreadable, skipped for an invalid or missing value, under a folder the walk skipped or could not enter) stays as stored, with its artifacts; its problem is the reader's;
  - a note whose file is still there but is no longer recognised (its `type` changed or is misspelled, a line stands above the opening `---`, the file is empty) stays as stored, with its artifacts, and gets the problem `noteNotRecognised` with its path on every import until it is recognised again or its file is gone;
  - a note whose `artifacts:` list was not read in full (an item skipped, a duplicate, not a list) is updated itself and keeps its stored artifacts that were not read, in their stored positions;
  - a stored artifact kept this way stays while its note is unread, whatever is read elsewhere; only the same appearance (same `id`, same period) read again replaces it, as an update (owner, 2026-10-10);
  - a note that is not the first by path for its period (`duplicatePeriodNote`, §2.1) keeps its stored artifacts as they were;
  - a note whose file is gone is removed (soft delete), with its artifacts; a renamed note is a new note, and its artifacts keep their identity (`id` + period).
- Hidden files and folders (`.obsidian`, `.trash`) are not read. One exception from the Write phase (ADR-0015): Obsidian's named settings files for daily and periodic notes, and from them only the folder, the file-name pattern and the template path; those folders and that path pass the same checks as the walk (inside the vault root, no symbolic links) before anything is read (ADR-0015 write rule 6). A note without frontmatter is skipped for frontmatter reading, not a problem; its body is still indexed from the Hub slice (next item).
- **Bodies (from the Hub slice; ADR-0014):** the body of every note, with or without frontmatter, except entry notes (§6.3; ADR-0019), is read for links and tags only (a memo's two sections are also read and stored, §6.1), never for values; nothing around a link is stored, not its alias or anchor either (owner, 2026-10-09). A body larger than 1 MB is not indexed and gives a typed problem; the walk limits above apply. A note is re-read only when its size or modification time changed.
- Unknown keys are ignored and preserved (future-proof; the vault has 200+ distinct keys).
- `review_cadence` and `review-cadence` both exist in the vault (19 vs 8 notes); MoonShine reads either.

## 4. Project notes (reserved now; read from the Hub slice)

ADR-0014. A note is a **project note** when its frontmatter carries the marker and an id:

```yaml
moonshine: project # marker
id: thesis-ch2 # required. slug [a-z0-9-]+, unique among project notes, never renamed
omnifocus_project: "Chapter 2" # optional: the OmniFocus project's name, exact match
omnifocus_id: # optional: the OmniFocus project's id; wins over the name. Written by MoonShine from the Write phase (ADR-0015)
line: research # optional line id; used only while the project has no OmniFocus project
notes: folder # optional: every note in this note's folder and below belongs to the project
status: active # optional, passed through like on other notes
```

Any other note joins a project with `project: <id>` (one id or a list), or by being linked from the project note.

Rules

- Keys are flat, so that MoonShine can later write `omnifocus_id` by editing one line.
- A project note bound to an OmniFocus project that already is a `Project` attaches to that project; its id and history are kept. Two projects that both have history are never merged automatically.
- Line: from the OmniFocus mapping when the project is bound (§1 precedence); when the note's `line` differs, the mapping wins and a banner names both.
- Two project notes with the same `id`, or claiming the same OmniFocus project → banner naming both paths; first by path wins.
- A binding that names an OmniFocus project the import does not contain is a typed problem; the project is shown as note-only.
- One OmniFocus project per project note.

## 5. Reserved keys and values

- **`moonshine:`** — values `budget` (§1), `project` (§4), `memo`, `programme` and `entry` (§6); `routine` (reserved; read from P2-R1, whose PR writes §6.4; ADR-0023) and `principle` (reserved; read from the first phase-4 slice that uses it, its format in ADR-0024) (owner, 2026-11-01). Until the scanner of §6 ships (P1), a note with any other value is not a problem and gives no banner; from then on it is `noteKindUnknown` (§6).
- **`within`, `measure`, `targets`** on a line (§1, "Practice lines"; read from the Practice lines slice, ADR-0019).
- **`portion_h_day`** on a line (§1; read from the Timer slice, ADR-0016).
- **`break_after_min`, `check_after_h`** on a line (§1, "Nudge values"; read from the Timer slice, ADR-0016; owner, 2026-10-28).
- **`quota_emphasis`** on a line (§1, "Quota emphasis"; read from the Quotas slice, ADR-0020).
- **The owner's `type` values `book`, `academic_book` and `article`** are read by the Library module (§7; from Library L1, ADR-0021). They stay the owner's: MoonShine never writes `type`.
- **`moonshine_ai: false`** on any note (read from the Ask phase, ADR-0015): the assistant never reads the note's body, even inside a folder on its allowlist, and the note is never sent in the standing context pack: it appears in the pack's list as excluded (owner, 2026-10-09).
- **Keys MoonShine owns and may write** (from the Write phase, ADR-0015, through `SetNoteProperty`, one line at a time): `omnifocus_id`, on project notes (§4) and on module notes (§7.1, ADR-0021). On an existing note no other key is written; a note made by `CreateNote` may carry §4's project-note keys and its template's own frontmatter.

## 6. Note kinds by the `moonshine` key (v0.4; ADR-0018, ADR-0019)

- One frontmatter key marks every note kind that MoonShine reads by kind rather than by folder: `moonshine: memo` (§6.1), `moonshine: programme` (§6.2) and `moonshine: entry` (§6.3). The owner's own keys, such as `type`, are never used for this. Module note kinds (§7) are the deliberate exception: they are the owner's own kinds, found by his `type` key.
- **One scanner** finds them across the vault under the rules of §3 (hidden folders, symbolic links, limits). It reads only the frontmatter: at most the first 8 KiB, stopping at the closing `---`. Bytes after it are discarded unparsed. This cap is stricter than the 64 KiB of §3 on purpose.
- **Frontmatter not closed within 8 KiB:** when those 8 KiB hold a top-level `moonshine: memo`, `programme` or `entry` line (the lexical rule of the budget marker, §1), the note gets `frontmatterTooLarge` with its path, whatever its kind, and is not read as that kind. The same holds for a top-level `type:` line whose value is a note kind of an enabled module (§7; owner, 2026-10-27), so a module note with long frontmatter is listed under its problem, never dropped. A `moonshine` key placed after 8 KiB of other keys is not seen (known gap, like §1's).
- An unknown value (a typo such as `memmo`) yields the problem `noteKindUnknown` with the path.
- The scanner arrives with P1, or with the Practice lines slice while P1 is cut from phase 2 (owner, 2026-11-01); entry notes are read from the Practice lines slice, programmes from P4.

### 6.1 Memo notes (read from P1; ADR-0018)

A note with `moonshine: memo` is a memo. Its body is read only to extract its two sections, named in frontmatter, with defaults `До` and `После`. Text outside them is ignored. The exact key shapes are fixed in P1's spec, with fixtures.

| Key       | Meaning                                                                                                                                                                                                                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `match`   | One or more matchers; the memo applies when any matches. **Event matcher:** `calendar`, `title` (exact, or `prefix:` / `contains:`, case-insensitive), `weekdays`, `starts_between` (a local time window), `date` (a one-off event). **Task matcher:** `omnifocus_tag`, `project`.               |
| `moments` | A list of anchors with offsets. Events: `before_start` (e.g. `15m`, `1d`), `at_start`, `after_end`. Tasks: `timer_start`, `timer_stop` (ADR-0016), `defer`, `due`, `completed` (seen at the next import).                                                                                        |
| `private` | `true` keeps the text out of notification banners; they show only the event's or task's title.                                                                                                                                                                                                   |
| `after`   | Optional. `status: true` asks for an outcome; `items: true` turns the checklist of the `После` section into checkboxes; `ritual: <name>` names the ritual to start (ADR-0015); `entry: {line: <id>, kind: <kind>}` names the practice entry (§6.3) that counts as "written" for this occurrence. |

Examples (illustrative; the shapes are P1's): a memo whose matcher has `title: "prefix:Session"` and `weekdays`, with the moments `before_start: 15m` and `after_end`, and `after.entry` naming `{line: reflection, kind: diary}`; a one-off memo whose matcher has `title: Trip` and a `date`, with the moment `before_start: 1d`.

- Tasks match by `omnifocus_tag` or `project` only; links in a task's note bind nothing (the snapshot carries no task-note text, `snapshot-contract.md`).
- **Several memos on one item:** all are shown, ordered by path; no memo hides another. At most 5 are shown; above that, a problem names the item.
- **A memo never shows a note with `moonshine: entry`** (§6.3), however it is named.
- **Sections are stored** on the Mac. The stored and synced copy is at most 2 KiB per section. A longer section is cut at the last line break before the limit, ends with "…" and gives `memoSectionTruncated`; on the Mac the full section opens from the vault. With sync on, sections are synced in encrypted fields (ADR-0010, ADR-0015); a memo with `private: true` is never synced and stays on the Mac.

Problems:

- a memo note that cannot be read as a memo → `memoNotRecognised` with its path;
- a bad matcher or moment is dropped with its own problem, never silently; the memo itself is kept;
- a memo with no valid matcher matches nothing and says so;
- more than 5 memos on one item → a problem naming the item;
- a section over 2 KiB → `memoSectionTruncated` (the stored copy is cut, as above).

Problem texts never carry memo text (§3).

### 6.2 Programme notes (kind reserved; format fixed in P4's spec)

`moonshine: programme` is reserved for a note that describes slots × weekdays → exercises, with variant sets and a `start` date; each set rotates by the number of occurrences of the slot since `start` (ADR-0018). Its format is fixed in the P4 spec, with fixtures. Until then the scanner recognises the kind and reads nothing from it.

### 6.3 Entry notes (read from the Practice lines slice; ADR-0019)

```yaml
---
moonshine: entry
line: reflection # a line with measure: entries (§1)
date: 2026-10-19 # optional when the file name starts with YYYY-MM-DD
kind: diary # free text, at most 40 characters; compared with the line's targets
covers: 2026-10 # optional: an ISO week (2026-W43) or a month (2026-10)
---
```

- The note can be anywhere in the vault. It is found by the `moonshine` key, never by folder.
- **Only the frontmatter is read.** The reader stops at the closing `---`. The body is not parsed, indexed, shown or sent anywhere, and the link index (ADR-0014) skips entry notes. No memo shows an entry note. UI, notifications and logs carry counts only.
- **A rejected entry is still an entry for the index:** when the first 8 KiB hold a top-level `moonshine: entry` line (the lexical rule of §1), the link index skips the note even if its frontmatter failed to parse or is not closed within 8 KiB. A file that cannot be read or is not UTF-8 has no readable body to index. Fixture test: an entry with malformed YAML and a wikilink in its body adds nothing to the index.
- **Date:** `date` when present; otherwise the leading `YYYY-MM-DD` of the file name; otherwise the entry has no date, is reported and is not counted.
- **Period:** for a target, an entry counts in the period its `covers` names when present, otherwise in the period of its `date`. A report for October written on 2 November counts for October. Weeks are ISO weeks starting on Monday; all dates are local.
- **Several entries on one day** all count as entries; the day counts once as a day with an entry.
- **Window:** entries are counted for the current month and the 12 before it (13 months). Older notes are skipped without a problem.
- **Read state:** the counts are **read**, **partly read** (some entries were rejected or unreadable; the counts are a lower bound, shown as "at least") or **unavailable** (the vault could not be read; the last known counts are shown with their date, never as 0, and no streak is broken).

Problems:

| Kind                    | When                                           | Effect                                 |
| ----------------------- | ---------------------------------------------- | -------------------------------------- |
| `entryWithoutDate`      | no `date` and no date in the file name         | The entry is not counted               |
| `entryLineUnknown`      | `line` names no line                           | The entry is not counted               |
| `entryLineNotEntries`   | the line is measured by hours                  | The entry is not counted               |
| `entryInvalid`          | a bad `covers`, `kind` too long                | The entry is not counted               |
| `frontmatterTooLarge`   | the closing `---` is not within 8 KiB (§6)     | The entry is not counted               |
| `entryKindNotInTargets` | `kind` is in none of the line's targets (info) | Counted for the line, not for a target |

## 7. Module note kinds (v0.5; ADR-0021)

A module is a feature set compiled into MoonShine and switched on in Settings (ADR-0021). Its notes are the owner's own note kinds, made from his templates, and they are found **by the owner's own `type` key, on purpose**: MoonShine adapts to the owner's conventions for these domains instead of asking for a marker. The `moonshine` key (§6, ADR-0018) stays for MoonShine's own note kinds (`budget`, `project`, `memo`, `programme`, `entry`).

- The same scanner as §6 finds them, under the rules of §3, reading only the frontmatter (the first 8 KiB, stopping at the closing `---`; frontmatter not closed within them gives `frontmatterTooLarge`, §6). **A module never reads the bodies of its notes**, except a section its own ADR names (none in ADR-0021), and never writes to them before the Write phase.
- Each module declares its note kinds (the `type` values, defaults below, changeable in Settings), a typed field schema, a small set of canonical states with a mapping from the owner's status values, and its problems. Every other key is ignored.
- **Failed is not empty:** a field that does not parse gives its own problem and is never dropped silently; a note whose status has no mapping is listed under "Unknown status", never hidden; a rejected note is listed under its problem, not dropped; when the vault is unavailable, the last known lists are shown with their date, never an empty module.
- In the UI a problem names its note. Logs carry only the kind and a count (§3, rule 5 of `CLAUDE.md`).

### 7.1 The Library module (read from Library L1; ADR-0021)

**Note kinds (defaults, changeable in Settings):**

| Kind    | `type` values           |
| ------- | ----------------------- |
| Book    | `book`, `academic_book` |
| Article | `article`               |

**Fields read** (the exact shapes are fixed in Library L1's spec, with fixtures):

| Key                           | Meaning                                                                                               |
| ----------------------------- | ----------------------------------------------------------------------------------------------------- |
| `title`                       | The title shown in the Library                                                                        |
| `author` or `authors`         | One author or a list                                                                                  |
| `status`                      | The owner's status value, mapped to a canonical state (below)                                         |
| `started`, `finished`         | Dates                                                                                                 |
| `rating`                      | A rating                                                                                              |
| `category` or `discipline`    | A category                                                                                            |
| `pages_total`, `current_page` | Page counts; progress `current_page / pages_total` shows only when both are valid                     |
| `source`                      | Articles: where the article comes from                                                                |
| `omnifocus_id`                | The id of the bound OmniFocus project or task (ADR-0014), typed by hand until the Write phase sets it |

The note's line comes through its binding (the bound project's line); there is no line key on a module note.

```yaml
---
type: book
title: The Quiet Orchard # invented
author: A. Example
status: reading
started: 2026-10-01
pages_total: 320
current_page: 112
omnifocus_id: abc123XYZ # the bound OmniFocus project or task
---
```

**Canonical states:** `someday` · `to buy` · `queue` · `reading` · `paused` · `done`.

**Default status mapping (changeable in Settings):**

| Owner's `status` | Canonical state |
| ---------------- | --------------- |
| `todo`           | queue           |
| `reading`, `wip` | reading         |
| `paused`         | paused          |
| `done`           | done            |
| `someday`        | someday         |
| `buy`            | to buy          |

**Only notes count:** a book that lives only as a line of the owner's hand-kept registry note is not in the module, and that note is not parsed (ADR-0021, option 4 not taken).

Problems:

| Kind                       | When                                                                                                                                                        |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `libraryStatusUnknown`     | a `status` with no mapping; the note is listed under "Unknown status"                                                                                       |
| `libraryFieldInvalid`      | a typed field that does not parse (a date, a page count, a rating)                                                                                          |
| `libraryPagesInconsistent` | `current_page` greater than `pages_total`                                                                                                                   |
| `libraryBindingMissing`    | `omnifocus_id` names no task or project in the snapshot, on a book in state `reading` or `paused`, and the store has never seen that id (owner, 2026-10-27) |

An unbound book (no `omnifocus_id`) has no progress and no problem. A book in another state (a finished book whose project was completed long ago and has left the snapshot), or bound to an id the store has seen before, gives no `libraryBindingMissing`.

**Progress on the book page** (Library L2; owner, 2026-10-27), with real counts (ADR-0020), by what `omnifocus_id` names:

- a task with a quota (`snapshot-contract.md` § Quota tags): that quota's history in its own period (a monthly quota gives monthly bars), with the quota as a line;
- a task without a quota: its completions per week;
- a project: the completions of all its tasks per week, plus the quota line of a quota task inside it if there is one.

`current_page / pages_total` shows next to it when both are valid.

## Open questions

- ~~Q1~~ Decided 2026-09-30: new key `scale`; existing free-text `horizon` is left untouched.
- **Q2** Should the year note's markdown table be generated from `artifacts:` later (the Act phase) so the two cannot drift?
- **Q3** Lines with `budget_h_week: null` (e.g. family time) — show in Lines view at all, or only in the Week header?
