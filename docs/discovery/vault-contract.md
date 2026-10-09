# Vault contract (Obsidian → MoonShine), v0.3

Status: **draft from phase-0 discovery** (see `data-report.md`). Implements ADR-0004: YAML frontmatter is the machine-readable truth; markdown bodies stay human text and are read for links and tags only, never for values (from the Hub slice; ADR-0014).

v0.2 (2026-10-01, design draft-2): optional line keys `foundation`, `floor_h_day`, `language`; quarter notes with `scale: quarter` and `artifacts:` (§2.2); R1 keys `done`, `carried_to`, `active_lines` (read from R1 on).

2026-10-05 (S3b): the budget note is found by its key only (§1); the reader's limits for untrusted input (§3).

2026-10-08 (S3b-2b+2c): `lines:` items are validated (§1, "Validation of `lines:`"); any invalid value skips its item.

v0.3 (2026-10-08, ADR-0014, ADR-0015, ADR-0016): project notes (§4) and reserved keys and values (§5), all reserved now and read from the slice or phase named at each; line key `portion_h_day` (§1); note bodies read for links and tags (§3, from the Hub slice); Obsidian's settings files for daily and weekly notes (§3, from the Write phase).

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
- **Clean read** — note found, list parsed, no item skipped. Only then does a line missing from the list leave the store (soft delete).

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
    language: it # optional BCP-47 tag (v0.2); language lines only. Parsed and stored; a content-language detection hint
    parent: "[[Artifacts_2026]]" # optional wikilink to the note that holds this line's artifact(s)
    omnifocus: # how OmniFocus items map to this line (see snapshot-contract.md §Mapping)
      tags: [violin] # tag names, exact match on the tag's own name (not full path)
      folders: [] # top-level folder names; every project inside maps to this line
      projects: [] # project names, for one-off exceptions
```

Rules

- Tier (UI grouping) = `foundation: true` → Foundation, else `state` → Active this season / Maintenance / Paused on purpose. `block` is a secondary label.
- `floor_h_day` is allowed on any line (owner, 2026-10-08); `foundation: true` decides only the tier and the "never quiet" rule. A line may have both `floor_h_day` and `budget_h_week`: a foundation line shows the floor; any other line shows the floor as a daily minimum next to its weekly budget (exact form: the screen spec or the next design round).
- `state: paused` = "paused on purpose" in the UI. It is never shown as missing activity.
- Tasks that match no line belong to **Life ops** (not a line; see `snapshot-contract.md`).
- A task maps to **at most one** line. Precedence: task tag → project tag → project name → folder. Two lines claiming the same tag/folder → banner naming both line ids; first in list wins.
- Hours shown for a line come only from real time data or from numbers the owner set himself: the vault values `budget_h_week`, `floor_h_day` and `portion_h_day`, and the length of events in the line's calendar (the day portion of ADR-0016; owner, 2026-10-08) — CLAUDE.md rule 8 / ADR-0006.
- The markdown table in the note may stay; the YAML block is authoritative for MoonShine (ADR-0004).

Validation of `lines:` (owner, 2026-10-07 and 2026-10-08):

- Numbers match `^[0-9]+(\.[0-9]+)?$` (no sign, exponent, hex, `nan`, `inf` or decimal comma); `budget_h_week` 0…168, `floor_h_day` 0…24.
- `id` `[a-z0-9-]+`, at most 64 characters, unique; `name` 1–120 characters and at most 1 KiB, `block` 1–60 characters and at most 512 bytes, `emoji` 1–8 characters and at most 256 bytes; characters are grapheme clusters (what a limit means to a reader), bytes are UTF-8, and a value over either limit is invalid (owner, 2026-10-08: a cluster can hold any number of combining marks); `state` one of the three values; `foundation` only `true` / `false`; `language` shaped `^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$`, at most 35 characters; each `omnifocus` list at most 100 names of at most 200 characters and 1 KiB; no string value (`name`, `block`, `emoji`, `language`, `parent`, `omnifocus` names) may hold a C0 control character (U+0000–U+001F) or DEL (U+007F): the store's text columns end at a NUL; `parent` is stored as written.
- `null` is the same as an absent key.
- Any missing, invalid or duplicate value skips its item: the stored line stays exactly as it was and the read is incomplete (no stored line is removed). Problems: `missingKey`, `invalidValue`, `duplicateLineId` (every item with that `id`; none wins), each with its key path (`lines.state`, `lines.omnifocus.tags`) and line; every problem of an item is reported.
- `lines:` absent or `null` → `missingKey`; not a list, or an empty list (`lines: []`) → `invalidValue`. Each leaves the lines unavailable: an empty list is more often a broken edit than "no lines", and as a clean read it would remove every stored line.

## 2. Horizon and artifact notes

Common frontmatter keys (all notes MoonShine reads as `NoteRef`):

| Key       | Type     | Meaning                                                                                                                                |
| --------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `type`    | string   | Required for recognition. Values below. A comma list (`"a, b"`) is read as its first item.                                             |
| `scale`   | enum     | `week` · `month` · `quarter` · `year` · `years` · `lifetime`. Optional when derivable (table below).                                   |
| `horizon` | —        | Not read by MoonShine; stays free text for the owner.                                                                                  |
| `period`  | string   | `YYYY-Www` · `YYYY-MM` · `YYYY-Qn` · `YYYY` · `YYYY..YYYY` (range) · `YYYY,YYYY,…` (list of target years). Optional when derivable.    |
| `parent`  | wikilink | Next note up the thread (month → quarter → year → corridor → long horizons). Path-qualified links allowed.                             |
| `line`    | line id  | Optional. Ties a note to one line.                                                                                                     |
| `status`  | string   | Passed through; MoonShine maps `active`/`draft`/`living` → current, `archived`/`closed`/`superseded` → past. Unknown values → current. |

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

### 2.1 Artifacts inside the year note — new block

```yaml
type: year_artifacts
year: 2026
artifacts:
  - id: a26-01 # required. unique within the vault; stable
    title: First paper draft # required
    line: research # optional line id (one); use `lines: [a, b]` for shared artifacts
    status: in_progress # planned | in_progress | done | dropped
    priority: true # optional; "priority" vs "the rest" group
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
    carried_to: 2027-Q1 # optional (R1): set during the quarterly review
```

`done` and `carried_to` (and the budget note's `active_lines`) are read from R1 on (quarterly review); before that the reader ignores them like any unknown key. Several quarter notes for the same period → banner, first by path wins.

### 2.3 Trace (phase 1)

`task → project → line (via omnifocus mapping) → artifact (the line's artifact in the current year note, else the line's `parent` note)`. A line with no artifact shows the trace up to the line — neutral, no warning.

## 3. Validation

- Invalid YAML or a `lines:` item with a missing, invalid or duplicate value (§1) → one calm banner with note path and line number; the rest of the vault still loads. Never a crash.
- Problems are typed (`VaultProblem`: a kind and, at most, a contract key name) with the note's vault-relative path and line; they never carry note content. A vault-wide problem (`budgetNoteMissing`) belongs to no note, so it is reported without a path (`ImportIssue.vaultWide`).
- The vault is untrusted input (synced or pasted from elsewhere). One guard per threat:
  - **leaving the vault:** symbolic links are skipped (`symlinkSkipped`); every resolved path must stay under the resolved vault folder (`outsideVault`; defence in depth behind the symlink skip, for a link swapped in during the walk); a folder the walk cannot enter is `unreadable`, never a silent gap;
  - **size:** at most 20,000 notes (more stops the read with a typed error; nothing is imported), frontmatter at most 64 KiB (`frontmatterTooLarge`);
  - **YAML:** checked lexically before parsing, coarse on purpose (quotes are not tracked, so a false positive rejects a note, never lets one through):
    - **anchor with alias** (`yamlAnchor`, counted on its own so false positives show): Yams expands aliases while parsing, before any cap can run, and an alias needs an anchor, so a note is rejected only when its frontmatter has both an anchor candidate and an alias candidate. Anchor candidate: an `&` followed by a non-blank that is not a flow indicator; an `&` right after a letter, combining mark or digit of any script (`R&D`, `Музыка&танец`, `音楽&舞踊`) is plain text, because a YAML token starts only after whitespace or an indicator. Alias candidate: a `*` followed by a non-blank (Markdown `**bold**` counts too). An anchor alone only labels its node and is accepted; the live check counts these notes ("anchor-like text and no alias, accepted"). An alias alone fails in Yams as `malformedYAML`;
    - **directive** (`yamlDirective`): a `%` at the start of the frontmatter or right after any line break libyaml knows (LF, CR, NEL, LS, PS), byte-order marks in between skipped. A `%TAG` prefix is copied into every tag that uses it (228 MB peak from 64 KiB of frontmatter, measured on Yams alone). A quoted scalar's continuation line that starts with `%` is rejected too (accepted false positive);
    - **flow nesting** (`[`, `{`) at most 32, also before parsing; after parsing, at most 10,000 nodes and depth 32 per note (`yamlTooComplex`).
  - **owner-only paths:** `moonshine-import vault --paths` prints each problem's kind, vault-relative path and line, nothing from the note. Its help text says it is for the owner's own terminal, and the tool enforces it: it refuses to run unless standard output is a terminal, checked before anything is read. A printed path shows every control and format character and a backslash as an escape (`\u{…}`, `\\`);
  - **line breaks:** the frontmatter ends only at a `---` line after LF. A `---` after CR, NEL, LS or PS is not a delimiter for the reader but starts a second document for libyaml, so the note fails safe as `malformedYAML`.
- Hidden files and folders (`.obsidian`, `.trash`) are not read. One exception from the Write phase (ADR-0015): Obsidian's named settings files for daily and periodic notes, and from them only the folder, the file-name pattern and the template path; those folders and that path pass the same checks as the walk (inside the vault root, no symbolic links) before anything is read (ADR-0015 write rule 6). A note without frontmatter is skipped for frontmatter reading, not a problem; its body is still indexed from the Hub slice (next item).
- **Bodies (from the Hub slice; ADR-0014):** the body of every note, with or without frontmatter, is read for links and tags only, never for values; nothing around a link is stored, not its alias or anchor either (owner, 2026-10-09). A body larger than 1 MB is not indexed and gives a typed problem; the walk limits above apply. A note is re-read only when its size or modification time changed.
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

- **`moonshine:`** — reserved values `budget` (§1) and `project` (§4). A note with any other value is not a problem and gives no banner.
- **`portion_h_day`** on a line (§1; read from the Timer slice, ADR-0016).
- **`moonshine_ai: false`** on any note (read from the Ask phase, ADR-0015): the assistant never reads the note's body, even inside a folder on its allowlist, and the note is never sent in the standing context pack: it appears in the pack's list as excluded (owner, 2026-10-09).
- **Keys MoonShine owns and may write** (from the Write phase, ADR-0015, through `SetNoteProperty`, one line at a time): `omnifocus_id` (§4). On an existing note no other key is written; a note made by `CreateNote` may carry §4's project-note keys and its template's own frontmatter.

## Open questions

- ~~Q1~~ Decided 2026-09-30: new key `scale`; existing free-text `horizon` is left untouched.
- **Q2** Should the year note's markdown table be generated from `artifacts:` later (the Act phase) so the two cannot drift?
- **Q3** Lines with `budget_h_week: null` (e.g. family time) — show in Lines view at all, or only in the Week header?
