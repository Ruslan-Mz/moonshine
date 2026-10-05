# OmniFocus snapshot contract, v0.2

Status: **draft**. Shared by the phase-1 JXA bridge (`bridge/snapshot.js`), the future Omni Automation plug-in export (ADR-0003) and `fixtures/omnifocus.snapshot.json`. One JSON document, produced read-only.

v0.2 (phase 1 S3a-1, 2026-10-02) adds the export modes (`full`, `incremental`, change probe), dropped tasks in incremental snapshots, OmniFocus' default times and the bridge's runtime rules. A document without `mode` is a v0.1 full snapshot.

Written from the Omni Automation object model and the field set of `kip-d/omnifocus-mcp` v4.1.0, then checked against the live database through that server's read tool (`data-report.md`). Items V1, V3 and V4 are settled; V2 (bridge latency) is open and flagged as a risk.

## Shape

```jsonc
{
  "schemaVersion": 1,
  "source": "omnifocus",
  "mode": "full",                                // "full" | "incremental" (v0.2; absent = full)
  "modifiedSince": null,                         // set iff mode == "incremental"
  "generatedAt": "2026-09-30T21:04:11+03:00",   // ISO 8601 with local offset
  "timeZone": "Europe/Moscow",                   // IANA zone of the Mac at export time
  "defaultTimes": { "due": "17:00", "defer": "00:00", "planned": "09:00" }, // see §Default times
  "window": { "completedSince": "2026-07-06" },   // Monday of ISO week (now − 12 weeks); dropped items are excluded
  "folders":  [ Folder ],
  "tags":     [ Tag ],
  "projects": [ Project ],
  "tasks":    [ Task ]
}
```

### Folder

| Field      | Type                      | Notes                                                                 |
| ---------- | ------------------------- | --------------------------------------------------------------------- |
| `id`       | string                    | OmniFocus primary key                                                 |
| `name`     | string                    |                                                                       |
| `parentId` | string \| null            | null = top level. Depth is derived.                                   |
| `status`   | `"active"` \| `"dropped"` | dropped folders are omitted unless they contain in-window completions |

### Tag

| Field      | Type                                    | Notes                                                    |
| ---------- | --------------------------------------- | -------------------------------------------------------- |
| `id`       | string                                  |                                                          |
| `name`     | string                                  | leaf name only, e.g. `Высокая`, not `Энергия : Высокая`  |
| `parentId` | string \| null                          | hierarchy for meta-tag groups (`Энергия`, `Контекст`, …) |
| `status`   | `"active"` \| `"onHold"` \| `"dropped"` |                                                          |

Tasks reference tags **by id**. Leaf names are not unique (e.g. `Низкая` can exist under both `Энергия` and `Время`); the MCP server returns only leaf names on tasks, the bridge must not.

### Project

| Field                                 | Type                                                | Notes                                            |
| ------------------------------------- | --------------------------------------------------- | ------------------------------------------------ |
| `id`                                  | string                                              |                                                  |
| `name`                                | string                                              |                                                  |
| `folderId`                            | string \| null                                      |                                                  |
| `status`                              | `"active"` \| `"onHold"` \| `"done"` \| `"dropped"` | done/dropped only if completed inside the window |
| `sequential`                          | bool                                                |                                                  |
| `singleActions`                       | bool                                                | single-action list                               |
| `tagIds`                              | string[]                                            | project's own tags                               |
| `deferDate`, `dueDate`, `plannedDate` | string \| null                                      | ISO 8601 with offset                             |
| `completionDate`                      | string \| null                                      |                                                  |
| `nextReviewDate`                      | string \| null                                      | informative only                                 |

### Task

| Field                                                            | Type                                                         | Notes                                                                                                                                                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                                                             | string                                                       |                                                                                                                                                                                                                             |
| `name`                                                           | string                                                       |                                                                                                                                                                                                                             |
| `projectId`                                                      | string \| null                                               | null = inbox                                                                                                                                                                                                                |
| `parentTaskId`                                                   | string \| null                                               | action groups; the project root task is **not** emitted as a task                                                                                                                                                           |
| `tagIds`                                                         | string[]                                                     |                                                                                                                                                                                                                             |
| `status`                                                         | `"available"` \| `"blocked"` \| `"completed"` \| `"dropped"` | `available` covers OmniFocus Available/Next/DueSoon/Overdue                                                                                                                                                                 |
| `flagged`                                                        | bool                                                         | own flag (not inherited)                                                                                                                                                                                                    |
| `effectiveFlagged`                                               | bool                                                         |                                                                                                                                                                                                                             |
| `deferDate`, `plannedDate`, `dueDate`                            | string \| null                                               | own values. `plannedDate` needs OmniFocus 4.7+; absent key = older OF, null = not set                                                                                                                                       |
| `effectiveDeferDate`, `effectiveDueDate`, `effectivePlannedDate` | string \| null                                               | inherited from project/parent (Omni Automation, read-only; `effectivePlannedDate` needs OmniFocus 4.7.1+, absent key = older OF). **Consumers place and colour tasks by these, not by the own dates** (decision 2026-09-30) |
| `estimatedMinutes`                                               | int \| null                                                  |                                                                                                                                                                                                                             |
| `completionDate`                                                 | string \| null                                               | set iff `status == "completed"`                                                                                                                                                                                             |
| `added`, `modified`                                              | string                                                       |                                                                                                                                                                                                                             |
| `repetition`                                                     | Repetition \| null                                           | on the live repeating task **and** copied onto each completed occurrence (observed)                                                                                                                                         |
| `repeatOf`                                                       | string \| null                                               | id of the live task a completed occurrence came from. Derived by the bridge from the OmniFocus id pattern `<liveId>.<n>` (observed on 86 % of completed tasks); null for one-off tasks                                      |
| `noteLength`                                                     | int                                                          | characters; **note text is never exported**                                                                                                                                                                                 |

### Repetition

| Field                  | Type                                            | Notes                                                                                                                               |
| ---------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ruleString`           | string                                          | RFC 5545 RRULE as OmniFocus stores it, e.g. `FREQ=DAILY`                                                                            |
| `scheduleType`         | `"regularly"` \| `"fromCompletion"` \| `"none"` | the bridge must read the enum's name; the MCP server serialises it as `"[object Task.RepetitionScheduleType]"` (bug, 100 % of rows) |
| `anchorDateKey`        | `"deferDate"` \| `"dueDate"` \| `"plannedDate"` | same serialisation caveat                                                                                                           |
| `catchUpAutomatically` | bool                                            | observed field                                                                                                                      |

## Selection

- **All** remaining (not completed, not dropped) tasks whose project is `active` or `onHold` and whose folder chain is not dropped. Observed: ~13 % of "not completed" tasks live inside done/dropped projects (children of cloned repeating groups), and ~60 projects with status `active` sit inside a dropped archive folder with 0 remaining tasks — both are excluded.
- All projects with status `active`/`onHold` outside dropped folders.
- Completed tasks and projects with `completionDate ≥ window.completedSince`.
- Dropped tasks are not exported in a full snapshot; an incremental snapshot reports those changed since its cutoff (§Modes). A dropped project appears only as the container of exported tasks.

## Modes (v0.2)

- **Full** (`mode: "full"`): the selection above. Only a full snapshot may make the store soft-delete what it no longer contains.
- **Incremental** — **not used** (S3a-1 measurement, §Findings 2026-10-02: building the task list dominates, so a change-only snapshot saves nothing; imports are always full). Kept in the contract and the bridge. (`mode: "incremental"`, `modifiedSince` = the cutoff): all folders, tags and projects (as in a full snapshot: cheap, and line mapping needs them), and only the tasks that a full snapshot would contain **or that are dropped**, and that changed since the cutoff: the task's own `modified`, or that of a parent task or its project's root task, is ≥ the cutoff. The parent/project rule exists because effective dates are inherited: changing a project's due date does not touch its tasks' `modified`.
  - **Dropped tasks** changed since the cutoff are emitted with `status: "dropped"`, so a consumer can retire them without waiting for a full snapshot. A task counts as dropped when OmniFocus says so, when it has an effective drop date, or when its project or a folder above it is dropped. Projects reached through such a task may carry `status: "dropped"`.
  - **True deletions** are invisible here (a deleted task has no record to report); only the next full snapshot reveals them.
  - `parentTaskId` and `repeatOf` may point to tasks that are not in the document (they came with an earlier import).
- **Change probe** — **not used as a change signal** (it pays the same listing cost as a full read, §Findings 2026-10-02). (`mode: "probe"`): a separate, title-free document for change detection:

  ```jsonc
  {
    "schemaVersion": 1,
    "source": "omnifocus",
    "mode": "probe",
    "generatedAt": "2026-10-02T12:00:00+03:00",
    "taskCount": 12345, // flattened tasks, incl. completed and project root tasks
    "latestModified": "2026-10-02T11:58:41+03:00",
  } // latest task `modified`; null if none
  ```

  A changed `latestModified` means something was edited; a lower `taskCount` with the same `latestModified` means something was deleted.

## Default times (v0.2)

OmniFocus stores a time on every date; a date picked without a time gets the user's default time. `defaultTimes` exports those settings as `HH:mm` (24 h, local): `due` and `defer` always; `planned` only when the OmniFocus version has that setting (absent key otherwise). If the settings cannot be read, `defaultTimes` is absent. **Fallback (owner decision 2026-10-05):** when `defaultTimes` or the key for a date kind is absent, only 00:00 counts as "date only" for that kind. Consumers may treat a date at the default time as "a day, no particular time" — not used before a spec asks for it.

**Known limit of that rule:** a task deliberately planned or due exactly at the default time is indistinguishable from a date-only one and is treated as date-only. On the live data (2026-10-02) one-off tasks are mostly at the default time (planned 35 of 39, due 34 of 49), repeating ones mostly at other times (planned 142 of 973 at the default, due 78 of 251).

## Bridge (v0.2)

`bridge/snapshot.js`, run as `osascript -l JavaScript bridge/snapshot.js full | incremental <ISO 8601 cutoff> | probe`. The JXA wrapper hands one Omni Automation script to OmniFocus (`evaluateJavascript`), which builds the whole document inside OmniFocus and returns it as one string.

- **Never launches OmniFocus.** If it is not running, stdout is `{"error":"notRunning"}` and the adapter throws a typed `notRunning`.
- **Timeout.** After 30 s the adapter sends `osascript` SIGTERM, then SIGKILL after a 2 s grace period, and throws a typed `timedOut` without waiting further. Worst case, the call returns after timeout + two grace periods (30 + 2 + 2 = 34 s); after a normal exit, reading the pipes is bounded by one grace period. **Killing `osascript` does not stop the script inside OmniFocus:** OmniFocus finishes it; MoonShine only stops waiting.
- **stdout** carries the document, which contains task titles: never log or paste it. **stderr** carries `moonshine-bridge omnifocus_ms=<n>`, the time the script spent inside OmniFocus. Omni's documentation does not say on which thread Omni Automation runs; forum reports of long scripts freezing OmniFocus suggest its main thread, so this time is treated as how long OmniFocus is unresponsive (checked by hand during the live measurement).
- **Requirements:** OmniFocus **Pro** (scripting is a Pro feature); OmniFocus ≥ 3.8 for `evaluateJavascript`, 4.7 for `plannedDate`, 4.7.1 for `effectivePlannedDate`. OmniFocus 4 is addressed by bundle id `com.omnigroup.OmniFocus4`. macOS **Automation** permission for the calling app to control OmniFocus (Terminal for `moonshine-import`; the app in S4 needs `NSAppleEventsUsageDescription` and, under hardened runtime, the `com.apple.security.automation.apple-events` entitlement); denied → osascript error -1743. OmniFocus' own "external scripts" approval is documented for script URLs, not for Apple Events; whether it applies here is checked on the first live run.
- Read-only: the script calls no setter and no write API.
- **Errors carry no values.** Decoding, validation and mapping errors name a JSON path (array indices, not ids) and a rule; bridge failures report the exit status and the OSA error number. The document holds titles and ids, and errors may reach logs.

## Invariants (tested on fixtures in phase 1 S1/S3)

1. Every `projectId`, `parentTaskId`, `folderId`, `parentId`, `tagIds[*]`, `repeatOf` resolves inside the same document — except, in an incremental snapshot, `parentTaskId` and `repeatOf`.
2. `status == "completed"` ⇔ `completionDate != null`; completed dates are within the window.
3. Ids are stable across exports (they are OmniFocus primary keys) → `ExternalRef(provider: "omnifocus", externalId: id)`.
4. All dates carry an offset; consumers compute ISO weeks in `timeZone`.
5. `effectiveX` is exported as OmniFocus computes it, never recomputed by MoonShine. When the own date is null it equals the nearest parent task's or the project's value. On the live data (2026-10-02) no task's own due date differs from its effective one, and 51 tasks inherit a due date they do not set themselves. The fixture uses own ?? nearest container.
6. No field carries note text or attachments.
7. `status == "dropped"` on a task appears only in an incremental snapshot.
8. `defaultTimes` values match `HH:mm`.

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

- **Rhythm** = completed occurrences of repeating tasks (`repeatOf != null`), shown as _sessions_.
- **Progress** = completed one-off tasks (`repeatOf == null`).
  Both are counted from completed task records; the same split applies to Life ops.
  Meta tags (children of `Тип работы`, `Контекст`, `Время`, `Энергия`, `Цикл`, `Локация`) are never line tags; they are kept as task attributes (`attrs.meta`) for later filters.

## Findings from live data (2026-09-30)

- **V1 — repeating tasks (settled).** Completing a repeating task leaves the live task with its id and creates a completed copy with id `<liveId>.<n>`, its own `completionDate`, `added` ≈ completion time, and the same repetition rule. Completing a repeating _action group_ also clones its children as `<childId>.<n>` with parent `<groupId>.<n>`. Consequence: stats must be able to separate habit occurrences (86 % of completions) from one-off completions.
- **V2 — latency (target revised 2026-09-30).** Through the MCP server: any count that scans all tasks takes ~8 s; a 250-row page ~8–9 s (the server halves oversized pages, so a full export needs ≥ 17 pages ≈ 2.5 min). Decision: the UI reads only from the store (< 1 s); the full import runs in the background (≤ 20 s) and later refreshes are incremental (`modified` since the last import). Measured in phase 1 S3 (ADR-0003, phase-1 spec).
- **V3 — field use (settled, sample of 500 remaining tasks).** `estimatedMinutes` 23 %, `plannedDate` 10 % (128 of 1 079 by count), `dueDate` 7 % (83 by count), `deferDate` 5 % (44 by count), repetition 14 %, note 7 %, flagged 2 %.
- **V4 — tags (settled).** Hierarchy depth is exactly 2. Meta groups (`Время`, `Тип работы`, `Контекст`, `Энергия`, `Цикл`, `Локация`) are top-level tags whose children have short English leaf names (`15min`, `deepwork`, `phone`, `low-energy`, `cycle-ai`…); everything else is flat. 31 % of remaining tasks have no tags, 17 % only meta tags.

## Findings from live data (2026-10-02, phase 1 S3a-1)

Measured with `moonshine-import` (release build; counts and timings only): 6 420 tasks in the database, 1 962 in a full snapshot.

- **V2 — latency (settled).** A full import takes **11.1 s** with OmniFocus in the background (OmniFocus held 10.8 s) and **4.0 s** with OmniFocus frontmost (held 2.7 s; the total includes a 1 s pause after activation). Decode, validation, import and commit together take ≈ 0.1 s. Within the 20 s target.
- **Listing dominates.** Building `flattenedTasks` costs 6.7–6.8 s in the background; reading `modified` on every task afterwards costs 0.14 s. Only tasks of active/on-hold projects plus the inbox (5 915 tasks) cost the same. Hence: no incremental snapshot (it would list the same tasks) and no cheap change probe (7 s, held 6.9 s).
- **Background throttling.** OmniFocus answers about **3.4× slower in the background** (probe held 6.9 s vs 2.0 s when frontmost). A script holds OmniFocus while it runs (owner's observation since phase 0: OmniFocus lags noticeably). ADR-0011 decides from this: import when OmniFocus resigns active, plus a timer while it is in the background; never while it is frontmost.
- **C — cache database (closed).** OmniFocus 4's app container (`com.omnigroup.OmniFocus4`) is readable but holds no SQLite database; its group containers (`34YW5XSRB7.com.omnigroup.OmniFocus4`, `34YW5XSRB7.com.omnigroup.OmniFocus`) are not readable even from Terminal without Full Disk Access. Rejected for now: it would need Full Disk Access-level consent, is impossible in a sandboxed build and relies on an undocumented format. Reopened only if the refresh after OmniFocus resigns active exceeds the ADR-0011 target.
- **D — OmniFocus' own export (closed).** `document.writableTypes` offers the database and backup package, plain text, HTML and two CSV variants, but no script path exists: `makeFileWrapper` is asynchronous and Omni Automation keeps no state between `evaluateJavascript` calls, so its result cannot be collected; OmniFocus is sandboxed and cannot write into a folder we own without a save dialog; an AppleScript Save-As would be a write.
- **Default times.** All three default times (defer, planned, due) are set; their values are the owner's preferences and stay out of the repo (the fixture's are invented). See §Default times for the distribution.

## Open items

- ~~V2~~ Measured 2026-10-02 (S3a-1): full import 11.1 s in the background, 4.0 s with OmniFocus frontmost — see §Findings 2026-10-02.
- ~~O1~~ Decided 2026-09-30: no weighting. Each line gets two separate metrics — see §Line metrics.
