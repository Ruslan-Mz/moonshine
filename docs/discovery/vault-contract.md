# Vault contract (Obsidian → MoonShine), v0.1

Status: **draft from phase-0 discovery** (see `data-report.md`). Implements ADR-0004: YAML frontmatter is the machine-readable truth; markdown bodies stay human text and are never parsed for data.

Scope: what the phase-1 `ObsidianAdapter` reads. It never writes (no vault writes before phase 6).

## Design choices driven by the data
1. **Existing keys are honoured as-is.** The vault already has `type`, `parent`, `period_start`/`period_end`, `month`, `year`, `horizons` on its horizon notes. The reader derives `scale` and `period` from them, so the owner only has to **add two blocks**: `lines:` (budget note) and `artifacts:` (year note).
2. **Artifacts are list items, not notes.** Year artifacts and quarter focuses live as table rows / headings inside one note each. The contract puts them in a frontmatter list in that note rather than asking for one note per artifact.
3. **New key `scale`, not `horizon`** (decision Q1, 2026-09-30). 18 existing notes use `horizon:` as a human phrase (a year range or duration plus a comment); MoonShine never reads `horizon` and never asks to change it. The machine-readable level of a note is `scale`.

## 1. Lines — the budget note
Identified by `moonshine: budget` in frontmatter, or (fallback) filename `Бюджет_часов_по_линиям.md` anywhere in the vault. Exactly one; more than one → banner, first by path wins.

```yaml
moonshine: budget            # marker; optional if the filename fallback matches
lines:                       # order = display order within a block
  - id: violin               # required. slug [a-z0-9-]+, unique, never renamed (ids survive renames of `name`)
    name: Violin             # required. display name, any script
    emoji: "🎻"              # optional
    block: Creative          # required. free string; blocks are displayed in first-appearance order
    state: active            # required. active | maintenance | paused
    budget_h_week: 6         # optional number ≥ 0; null/absent = no weekly budget ("no schedule")
    parent: "[[Artifacts_2026]]"   # optional wikilink to the note that holds this line's artifact(s)
    omnifocus:               # how OmniFocus items map to this line (see snapshot-contract.md §Mapping)
      tags: [violin]         # tag names, exact match on the tag's own name (not full path)
      folders: []            # top-level folder names; every project inside maps to this line
      projects: []           # project names, for one-off exceptions
```

Rules
- `state: paused` = "paused on purpose" in the UI. It is never shown as missing activity.
- Tasks that match no line belong to **Life ops** (not a line; see `snapshot-contract.md`).
- A task maps to **at most one** line. Precedence: task tag → project tag → project name → folder. Two lines claiming the same tag/folder → banner naming both line ids; first in list wins.
- Hours shown for a line are only `budget_h_week` (vault budget) — CLAUDE.md §8 / ADR-0006.
- The markdown table in the note may stay; the YAML block is authoritative for MoonShine (ADR-0004).

## 2. Horizon and artifact notes
Common frontmatter keys (all notes MoonShine reads as `NoteRef`):

| Key | Type | Meaning |
|---|---|---|
| `type` | string | Required for recognition. Values below. A comma list (`"a, b"`) is read as its first item. |
| `scale` | enum | `week` · `month` · `quarter` · `year` · `years` · `lifetime`. Optional when derivable (table below). |
| `horizon` | — | Not read by MoonShine; stays free text for the owner. |
| `period` | string | `YYYY-Www` · `YYYY-MM` · `YYYY-Qn` · `YYYY` · `YYYY..YYYY` (range) · `YYYY,YYYY,…` (list of target years). Optional when derivable. |
| `parent` | wikilink | Next note up the thread (month → quarter → year → corridor → long horizons). Path-qualified links allowed. |
| `line` | line id | Optional. Ties a note to one line. |
| `status` | string | Passed through; MoonShine maps `active`/`draft`/`living` → current, `archived`/`closed`/`superseded` → past. Unknown values → current. |

Recognised types and derivation of `scale` / `period` when they are absent:

| `type` | Derived `scale` | Derived `period` from | Found in vault |
|---|---|---|---|
| `month_plan` | `month` | `month: YYYY-MM`, else `period_start` | 3 notes, name `Месяц_YYYY-MM` |
| `quarter_focus` | `quarter` | `quarter`, else `period_start` → `YYYY-Qn` | 2 notes, name `Qn_YYYY_focus` |
| `year_artifacts` | `year` | `year: YYYY` | 1 note, name `Артефакты_YYYY` |
| `horizon_corridor` | `years` | `period_start..period_end` (ints or dates), else `horizons: [YYYY,…]` | 2 notes |
| `yearly-goals`, `focus` | `year` | `year`, else 4-digit year in filename | 2 legacy journal notes (read-only, low priority) |
| `lifetime` *(new)* | `lifetime` | — | 0 |

Weekly review notes (`YYYY-Www`, journal) currently have no frontmatter; phase 1 does not need them.

### 2.1 Artifacts inside the year note — new block
```yaml
type: year_artifacts
year: 2026
artifacts:
  - id: a26-01               # required. unique within the vault; stable
    title: First paper draft # required
    line: research           # optional line id (one); use `lines: [a, b]` for shared artifacts
    status: in_progress      # planned | in_progress | done | dropped
    priority: true           # optional; "priority" vs "the rest" group
```
The quarter note may reference them (optional, phase 5 uses it; phase 1 only shows the trace):
```yaml
type: quarter_focus
period_start: 2026-10-01
period_end: 2026-12-31
parent: "[[Artifacts_2026]]"
focus:
  - title: Violin restart as a habit
    line: violin
    artifact: a26-03         # optional artifact id
```

### 2.2 Trace (phase 1)
`task → project → line (via omnifocus mapping) → artifact (the line's artifact in the current year note, else the line's `parent` note)`. A line with no artifact shows the trace up to the line — neutral, no warning.

## 3. Validation
- Invalid YAML or a `lines:` item missing a required key → one calm banner with note path and line number; the rest of the vault still loads. Never a crash.
- Unknown keys are ignored and preserved (future-proof; the vault has 200+ distinct keys).
- `review_cadence` and `review-cadence` both exist in the vault (19 vs 8 notes); MoonShine reads either.

## Open questions
- ~~Q1~~ Decided 2026-09-30: new key `scale`; existing free-text `horizon` is left untouched.
- **Q2** Should the year note's markdown table be generated from `artifacts:` later (phase 6) so the two cannot drift?
- **Q3** Lines with `budget_h_week: null` (e.g. family time) — show in Lines view at all, or only in the Week header?
