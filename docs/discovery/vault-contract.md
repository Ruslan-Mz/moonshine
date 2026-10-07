# Vault contract (Obsidian → MoonShine), v0.2

Status: **draft from phase-0 discovery** (see `data-report.md`). Implements ADR-0004: YAML frontmatter is the machine-readable truth; markdown bodies stay human text and are never parsed for data.

v0.2 (2026-10-01, design draft-2): optional line keys `foundation`, `floor_h_day`, `language`; quarter notes with `scale: quarter` and `artifacts:` (§2.2); R1 keys `done`, `carried_to`, `active_lines` (read from R1 on).

2026-10-05 (S3b): the budget note is found by its key only (§1); the reader's limits for untrusted input (§3).

Scope: what the phase-1 `ObsidianAdapter` reads. It never writes (no vault writes before the Act phase).

## Design choices driven by the data

1. **Existing keys are honoured as-is.** The vault already has `type`, `parent`, `period_start`/`period_end`, `month`, `year`, `horizons` on its horizon notes. The reader derives `scale` and `period` from them, so the owner only has to make **three edits**: the `moonshine: budget` marker and the `lines:` block (budget note), and `artifacts:` (year note).
2. **Artifacts are list items, not notes.** Year artifacts and quarter focuses live as table rows / headings inside one note each. The contract puts them in a frontmatter list in that note rather than asking for one note per artifact.
3. **New key `scale`, not `horizon`** (decision Q1, 2026-09-30). 18 existing notes use `horizon:` as a human phrase (a year range or duration plus a comment); MoonShine never reads `horizon` and never asks to change it. The machine-readable level of a note is `scale`.

## 1. Lines — the budget note

Identified only by `moonshine: budget` at the top level of the frontmatter (no file-name fallback: a file name is the owner's data). Rejected notes count too: a note whose frontmatter failed to parse is searched lexically for a top-level `moonshine: budget` line (quotes around the key or the value and a trailing comment allowed). Exactly one marked note that parsed → the budget note; exactly one that was rejected → lines unavailable, `budgetNoteRejected` on that note next to its own problem, and the live check prints `rejected (<kind>)`; more than one, parsed or not → ambiguous: lines unavailable, `budgetNoteDuplicate` on each, none wins (the owner removes the marker from the copy); none → the vault-wide problem `budgetNoteMissing` (no path). Known gap: a note whose frontmatter cannot be extracted (unreadable, not UTF-8, over the size cap, never closed) cannot be searched.

The reader says whether it could read the lines, not only which ones it read (2026-10-07):

- **Unavailable** — the budget note is missing or rejected, or its `lines:` is missing or not a list. The stored lines stay as they are and keep mapping tasks.
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
    floor_h_day: null # optional number ≥ 0 (v0.2); daily floor of a foundation line, shown instead of budget_h_week
    language: it # optional BCP-47 tag (v0.2); language lines only. Parsed and stored; a content-language detection hint
    parent: "[[Artifacts_2026]]" # optional wikilink to the note that holds this line's artifact(s)
    omnifocus: # how OmniFocus items map to this line (see snapshot-contract.md §Mapping)
      tags: [violin] # tag names, exact match on the tag's own name (not full path)
      folders: [] # top-level folder names; every project inside maps to this line
      projects: [] # project names, for one-off exceptions
```

Rules

- Tier (UI grouping) = `foundation: true` → Foundation, else `state` → Active this season / Maintenance / Paused on purpose. `block` is a secondary label.
- `floor_h_day` without `foundation: true` → ignored with a banner; a foundation line with `budget_h_week` keeps both, the UI shows the floor.
- `state: paused` = "paused on purpose" in the UI. It is never shown as missing activity.
- Tasks that match no line belong to **Life ops** (not a line; see `snapshot-contract.md`).
- A task maps to **at most one** line. Precedence: task tag → project tag → project name → folder. Two lines claiming the same tag/folder → banner naming both line ids; first in list wins.
- Hours shown for a line are only `budget_h_week` (vault budget) — CLAUDE.md §8 / ADR-0006.
- The markdown table in the note may stay; the YAML block is authoritative for MoonShine (ADR-0004).

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

- Invalid YAML or a `lines:` item missing a required key → one calm banner with note path and line number; the rest of the vault still loads. Never a crash.
- Problems are typed (`VaultProblem`: a kind and, at most, a contract key name) with the note's vault-relative path and line; they never carry note content. A vault-wide problem (`budgetNoteMissing`) belongs to no note, so it is reported without a path (`ImportIssue.vaultWide`).
- The vault is untrusted input (synced or pasted from elsewhere). One guard per threat:
  - **leaving the vault:** symbolic links are skipped (`symlinkSkipped`); every resolved path must stay under the resolved vault folder (`outsideVault`; defence in depth behind the symlink skip, for a link swapped in during the walk); a folder the walk cannot enter is `unreadable`, never a silent gap;
  - **size:** at most 20,000 notes (more stops the read with a typed error; nothing is imported), frontmatter at most 64 KiB (`frontmatterTooLarge`);
  - **YAML:** checked lexically before parsing, coarse on purpose (quotes are not tracked, so a false positive rejects a note, never lets one through):
    - **anchor with alias** (`yamlAnchor`, counted on its own so false positives show): Yams expands aliases while parsing, before any cap can run, and an alias needs an anchor, so a note is rejected only when its frontmatter has both an anchor candidate and an alias candidate. Anchor candidate: an `&` followed by a non-blank that is not a flow indicator; an `&` right after a letter, combining mark or digit of any script (`R&D`, `Музыка&танец`, `音楽&舞踊`) is plain text, because a YAML token starts only after whitespace or an indicator. Alias candidate: a `*` followed by a non-blank (Markdown `**bold**` counts too). An anchor alone only labels its node and is accepted; the live check counts these notes ("anchor-like text and no alias, accepted"). An alias alone fails in Yams as `malformedYAML`;
    - **directive** (`yamlDirective`): a `%` at the start of the frontmatter or right after any line break libyaml knows (LF, CR, NEL, LS, PS), byte-order marks in between skipped. A `%TAG` prefix is copied into every tag that uses it (228 MB peak from 64 KiB of frontmatter, measured on Yams alone). A quoted scalar's continuation line that starts with `%` is rejected too (accepted false positive);
    - **flow nesting** (`[`, `{`) at most 32, also before parsing; after parsing, at most 10,000 nodes and depth 32 per note (`yamlTooComplex`).
  - **line breaks:** the frontmatter ends only at a `---` line after LF. A `---` after CR, NEL, LS or PS is not a delimiter for the reader but starts a second document for libyaml, so the note fails safe as `malformedYAML`.
- Hidden files and folders (`.obsidian`, `.trash`) are not read. A note without frontmatter is skipped, not a problem.
- Unknown keys are ignored and preserved (future-proof; the vault has 200+ distinct keys).
- `review_cadence` and `review-cadence` both exist in the vault (19 vs 8 notes); MoonShine reads either.

## Open questions

- ~~Q1~~ Decided 2026-09-30: new key `scale`; existing free-text `horizon` is left untouched.
- **Q2** Should the year note's markdown table be generated from `artifacts:` later (the Act phase) so the two cannot drift?
- **Q3** Lines with `budget_h_week: null` (e.g. family time) — show in Lines view at all, or only in the Week header?
