# OmniFocus snapshot contract, v0.1

Status: **draft**. Shared by the phase-1 JXA bridge (`bridge/snapshot.js`), the future Omni Automation plug-in export (ADR-0003) and `fixtures/omnifocus.snapshot.json`. One JSON document, produced read-only.

Written from the Omni Automation object model and the field set of `kip-d/omnifocus-mcp` v4.1.0, then checked against the live database through that server's read tool (`data-report.md`). Items V1, V3 and V4 are settled; V2 (bridge latency) is open and flagged as a risk.

## Shape
```jsonc
{
  "schemaVersion": 1,
  "source": "omnifocus",
  "generatedAt": "2026-09-30T21:04:11+03:00",   // ISO 8601 with local offset
  "timeZone": "Europe/Moscow",                   // IANA zone of the Mac at export time
  "window": { "completedSince": "2026-07-06" },   // Monday of ISO week (now − 12 weeks); dropped items are excluded
  "folders":  [ Folder ],
  "tags":     [ Tag ],
  "projects": [ Project ],
  "tasks":    [ Task ]
}
```

### Folder
| Field | Type | Notes |
|---|---|---|
| `id` | string | OmniFocus primary key |
| `name` | string | |
| `parentId` | string \| null | null = top level. Depth is derived. |
| `status` | `"active"` \| `"dropped"` | dropped folders are omitted unless they contain in-window completions |

### Tag
| Field | Type | Notes |
|---|---|---|
| `id` | string | |
| `name` | string | leaf name only, e.g. `Высокая`, not `Энергия : Высокая` |
| `parentId` | string \| null | hierarchy for meta-tag groups (`Энергия`, `Контекст`, …) |
| `status` | `"active"` \| `"onHold"` \| `"dropped"` | |

Tasks reference tags **by id**. Leaf names are not unique (e.g. `Низкая` can exist under both `Энергия` and `Время`); the MCP server returns only leaf names on tasks, the bridge must not.

### Project
| Field | Type | Notes |
|---|---|---|
| `id` | string | |
| `name` | string | |
| `folderId` | string \| null | |
| `status` | `"active"` \| `"onHold"` \| `"done"` \| `"dropped"` | done/dropped only if completed inside the window |
| `sequential` | bool | |
| `singleActions` | bool | single-action list |
| `tagIds` | string[] | project's own tags |
| `deferDate`, `dueDate`, `plannedDate` | string \| null | ISO 8601 with offset |
| `completionDate` | string \| null | |
| `nextReviewDate` | string \| null | informative only |

### Task
| Field | Type | Notes |
|---|---|---|
| `id` | string | |
| `name` | string | |
| `projectId` | string \| null | null = inbox |
| `parentTaskId` | string \| null | action groups; the project root task is **not** emitted as a task |
| `tagIds` | string[] | |
| `status` | `"available"` \| `"blocked"` \| `"completed"` \| `"dropped"` | `available` covers OmniFocus Available/Next/DueSoon/Overdue |
| `flagged` | bool | own flag (not inherited) |
| `effectiveFlagged` | bool | |
| `deferDate`, `plannedDate`, `dueDate` | string \| null | own values. `plannedDate` needs OmniFocus 4.7+; absent key = older OF, null = not set |
| `effectiveDeferDate`, `effectiveDueDate` | string \| null | inherited from project/parent |
| `estimatedMinutes` | int \| null | |
| `completionDate` | string \| null | set iff `status == "completed"` |
| `added`, `modified` | string | |
| `repetition` | Repetition \| null | on the live repeating task **and** copied onto each completed occurrence (observed) |
| `repeatOf` | string \| null | id of the live task a completed occurrence came from. Derived by the bridge from the OmniFocus id pattern `<liveId>.<n>` (observed on 86 % of completed tasks); null for one-off tasks |
| `noteLength` | int | characters; **note text is never exported** |

### Repetition
| Field | Type | Notes |
|---|---|---|
| `ruleString` | string | RFC 5545 RRULE as OmniFocus stores it, e.g. `FREQ=DAILY` |
| `scheduleType` | `"regularly"` \| `"fromCompletion"` \| `"none"` | the bridge must read the enum's name; the MCP server serialises it as `"[object Task.RepetitionScheduleType]"` (bug, 100 % of rows) |
| `anchorDateKey` | `"deferDate"` \| `"dueDate"` \| `"plannedDate"` | same serialisation caveat |
| `catchUpAutomatically` | bool | observed field |

## Selection
- **All** remaining (not completed, not dropped) tasks whose project is `active` or `onHold` and whose folder chain is not dropped. Observed: ~13 % of "not completed" tasks live inside done/dropped projects (children of cloned repeating groups), and ~60 projects with status `active` sit inside a dropped archive folder with 0 remaining tasks — both are excluded.
- All projects with status `active`/`onHold` outside dropped folders.
- Completed tasks and projects with `completionDate ≥ window.completedSince`.
- Dropped items are not exported (phase 1 has no use for them).

## Invariants (tested on fixtures in phase 1 S1/S3)
1. Every `projectId`, `parentTaskId`, `folderId`, `parentId`, `tagIds[*]`, `repeatOf` resolves inside the same document.
2. `status == "completed"` ⇔ `completionDate != null`; completed dates are within the window.
3. Ids are stable across exports (they are OmniFocus primary keys) → `ExternalRef(provider: "omnifocus", externalId: id)`.
4. All dates carry an offset; consumers compute ISO weeks in `timeZone`.
5. No field carries note text or attachments.

## Mapping to MoonShine lines
Mapping rules live in the vault (`lines[*].omnifocus`, see `vault-contract.md`), not in the snapshot. Per task, first match wins:
1. a task tag listed in a line's `omnifocus.tags`;
2. a tag of its project;
3. the project name in `omnifocus.projects`;
4. the project's **top-level** folder in `omnifocus.folders`.

In the real data lines follow folders and projects far more than tags: line tags exist for only a few lines (e.g. one instrument), and 6 of 15 used top-level folders hold several lines each, so project-name mapping (rule 3) carries most of the weight.
No match → the task belongs to **Life ops**: a fixed bucket for household, admin, system routines and the inbox. It is not a line (no budget, no artifact, never "quiet") and is shown separately with neutral wording (decision 2026-09-30).

## Line metrics (decision O1, 2026-09-30)
Completions are never weighted or mixed. Per line, per ISO week:
- **Rhythm** = completed occurrences of repeating tasks (`repeatOf != null`), shown as *sessions*.
- **Progress** = completed one-off tasks (`repeatOf == null`).
Both are counted from completed task records; the same split applies to Life ops.
Meta tags (children of `Тип работы`, `Контекст`, `Время`, `Энергия`, `Цикл`, `Локация`) are never line tags; they are kept as task attributes (`attrs.meta`) for later filters.

## Findings from live data (2026-09-30)
- **V1 — repeating tasks (settled).** Completing a repeating task leaves the live task with its id and creates a completed copy with id `<liveId>.<n>`, its own `completionDate`, `added` ≈ completion time, and the same repetition rule. Completing a repeating *action group* also clones its children as `<childId>.<n>` with parent `<groupId>.<n>`. Consequence: stats must be able to separate habit occurrences (86 % of completions) from one-off completions.
- **V2 — latency (target revised 2026-09-30).** Through the MCP server: any count that scans all tasks takes ~8 s; a 250-row page ~8–9 s (the server halves oversized pages, so a full export needs ≥ 17 pages ≈ 2.5 min). Decision: the UI reads only from the store (< 1 s); the full import runs in the background (≤ 20 s) and later refreshes are incremental (`modified` since the last import). Measured in phase 1 S3 (ADR-0003, phase-1 spec).
- **V3 — field use (settled, sample of 500 remaining tasks).** `estimatedMinutes` 23 %, `plannedDate` 10 % (128 of 1 079 by count), `dueDate` 7 % (83 by count), `deferDate` 5 % (44 by count), repetition 14 %, note 7 %, flagged 2 %.
- **V4 — tags (settled).** Hierarchy depth is exactly 2. Meta groups (`Время`, `Тип работы`, `Контекст`, `Энергия`, `Цикл`, `Локация`) are top-level tags whose children have short English leaf names (`15min`, `deepwork`, `phone`, `low-energy`, `cycle-ai`…); everything else is flat. 31 % of remaining tasks have no tags, 17 % only meta tags.

## Open items
- **V2** Measure full (≤ 20 s) and incremental import on the real database (phase 1 S3).
- ~~O1~~ Decided 2026-09-30: no weighting. Each line gets two separate metrics — see §Line metrics.
