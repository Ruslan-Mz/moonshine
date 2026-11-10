# OmniFocus snapshot contract, v0.3

Status: **draft**. Shared by the phase-1 JXA bridge (`bridge/snapshot.js`), the future Omni Automation plug-in export (ADR-0003) and `fixtures/omnifocus.snapshot.json`. One JSON document, produced read-only.

v0.2 (phase 1 S3a-1, 2026-10-02) adds the export modes (`full`, `incremental`, change probe), dropped tasks in incremental snapshots, OmniFocus' default times and the bridge's runtime rules. A document without `mode` is a v0.1 full snapshot.

v0.3 (2026-10-26, ADR-0020, owner) reads quota tags on repeating tasks (§Quota tags) and states the completion window that quotas need. The document's shape does not change.

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

| Field      | Type                                    | Notes                                                  |
| ---------- | --------------------------------------- | ------------------------------------------------------ |
| `id`       | string                                  |                                                        |
| `name`     | string                                  | leaf name only, e.g. `Low`, not `Effort : Low`         |
| `parentId` | string \| null                          | hierarchy for meta-tag groups (`Effort`, `Setting`, …) |
| `status`   | `"active"` \| `"onHold"` \| `"dropped"` |                                                        |

Tasks reference tags **by id**. Leaf names are not unique (e.g. `Low` can exist under both `Effort` and `Pace`); the MCP server returns only leaf names on tasks, the bridge must not.

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
| `estimatedMinutes`                                               | int \| null                                                  | 0 to 525,600 (one year); a value outside makes the snapshot invalid (S4-1a, PR #30 round 1)                                                                                                                                 |
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

**Stored and used (S4-3a; owner, 2026-10-28):** the mapper carries `defaultTimes` into the task source, the importer into the workspace and the store keeps them (minutes from midnight in the `workspace` row, read in the workspace's time zone). An absent `defaultTimes` object is a failed read, not "no settings": the stored times stay, and the import reports `defaultTimesNotRead` (no value in it); with nothing stored yet, the 00:00 fallback above applies, with the same issue. A missing `planned` key alone (an older OmniFocus) is taken as it is, with no issue. `HH:mm` takes ASCII digits only. The Day rail and Today's due times (S4-3b) are the first readers.

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
9. `window.completedSince` is a `YYYY-MM-DD` date that exists (ASCII digits; `2026-02-30` is none). MoonShine stores the start of that day in `timeZone` as the window start (S4-4c-3).

## Mapping to MoonShine lines

Mapping rules live in the vault (`lines[*].omnifocus`, see `vault-contract.md`), not in the snapshot. Per task, first match wins:

1. a task tag listed in a line's `omnifocus.tags`;
2. a tag of its project;
3. the project name in `omnifocus.projects`;
4. the project's **top-level** folder in `omnifocus.folders`.

In the real data lines follow folders and projects far more than tags: line tags exist for only a few lines (e.g. one instrument), and 6 of 15 used top-level folders hold several lines each, so project-name mapping (rule 3) carries most of the weight.
No match → the task belongs to **Life ops**: a fixed bucket for household, admin, system routines and the inbox. It is not a line (no budget, no artifact, never "quiet") and is shown separately with neutral wording (decision 2026-09-30).

## Reminder tag (ADR-0017, 2026-10-16)

One tag name is read as "reminder": a task carrying it (a setting, default `напоминание`, matched by leaf name like the deadline tag) is a reminder, not a task. MoonShine shows it in Today's Reminders strip and leaves it out of every task count, statistic, forecast and load, Rhythm and Progress below included (from S4). The snapshot itself does not change: the tag arrives in `tags` and `tagIds` like any other.

## Quota tags (ADR-0020, 2026-10-26; read from the Quotas slice)

A tag whose leaf name has the quota form declares a period quota on a repeating task: "done N times per week or per month". The snapshot itself does not change: the tag arrives in `tags` and `tagIds` like any other, and the count comes from completed copies already in the document.

**Grammar.** The leaf name, trimmed, matched without case:

| Form                 | N       | Period                       |
| -------------------- | ------- | ---------------------------- |
| `N/нед` or `N/week`  | 1 to 7  | ISO week, starting on Monday |
| `N/мес` or `N/month` | 1 to 31 | calendar month               |

followed by optional suffixes, each at most once, in either order:

- `!` — strong emphasis for this task (overrides the line's `quota_emphasis`, `vault-contract.md` §1);
- `+` — carry-over: the surplus of a period counts toward the next period only, up to N.

Examples (invented): `2/нед`, `1/month`, `2/мес!`, `2/мес+!`, `3/week!+`.

**Quota-like and valid** (owner, 2026-10-27). A tag is **quota-like** when its leaf name is a number, `/`, letters, then any run of `!` and `+`. It is **valid** when the unit is one of the four above, N is in range and each suffix appears at most once. A quota-like tag that is not valid gives `quotaInvalid` and is ignored: `2/нед!!`, `9/нед` and `2/день` are `quotaInvalid`.

**Rules**

- Counted: the completed copies of the task's repeat series (the live task and its completed occurrences, whose `repeatOf` is the live task's id) whose `completionDate`, in the document's `timeZone`, falls in the period.
- **Checks on a task's valid quota tags, in this order** (owner, 2026-10-27); the first that applies decides, so a task gets one of these problems at most:
  1. the task is a reminder (§Reminder tag), repeating or not → `quotaOnReminder`;
  2. the task does not repeat (`repetition == null`) → `quotaNotRepeating`;
  3. two or more valid quota tags → `quotaAmbiguous`. `quotaInvalid` tags do not count: `2/нед` with `9/нед` applies `2/нед`, and `9/нед` gives `quotaInvalid`.
- In the UI a problem names its task; the OmniFocus id identifies the task in the store. Logs carry only the kind and a count (rule 5 of `CLAUDE.md`; ADR-0020).

| Kind                | When                                                                              | Effect                             |
| ------------------- | --------------------------------------------------------------------------------- | ---------------------------------- |
| `quotaInvalid`      | a quota-like tag that is not valid (unknown unit, N out of range, a suffix twice) | The tag is ignored                 |
| `quotaOnReminder`   | a valid quota tag on a reminder, repeating or not                                 | Ignored; reminders carry no quota  |
| `quotaNotRepeating` | a valid quota tag on a non-repeating task                                         | Ignored; the task behaves as usual |
| `quotaAmbiguous`    | two or more valid quota tags on one task                                          | All are ignored; none wins         |

**Completion window.** For quotas, the completions must cover the current and the previous period, up to 62 days (from the first day of the previous month). A `+` quota also needs the period before the previous one, up to 92 days, because the previous period's carried surplus comes from it. When the completions do not reach that far, a count is **partly read**, shown as "at least N", and no period is reported short; for a `+` quota, the previous period is then partly read and not reported short.

The current window, `completedSince` = the Monday of the ISO week that holds the day 84 days ago (`bridge/snapshot.js`), reaches 84 to 90 days back. It **already covers quotas without `+`**: no bridge change is needed. For a `+` quota it does not always reach the period before the previous one. The store keeps completed tasks after they leave the window (`docs/ARCHITECTURE.md`, Sync-in), so a store that has run that long usually holds it; a fresh or rebuilt store may not, and then the rule above applies.

## Line metrics (decision O1, 2026-09-30)

Completions are never weighted or mixed. Per line, per ISO week:

- **Rhythm** = completed occurrences of repeating tasks (`repeatOf != null`), shown as _sessions_.
- **Progress** = completed one-off tasks (`repeatOf == null`).
  Both are counted from completed task records; the same split applies to Life ops.
  Meta tags (the top-level groups `mapping.yaml` names, and their children; § Meta tag groups) are never line tags; they are kept as task attributes (`attrs.meta`) for later filters.

## Meta tag groups: `mapping.yaml` (S4-4c-2)

The group names are the owner's labels, so they are not in the code, the fixtures or these documents: they live in `mapping.yaml` in the data folder (`~/Library/Application Support/MoonShine/`), read by the app at Live's first selection and by `moonshine-import full` before anything else (`Adapters/Sources/ObsidianAdapter/MappingFile.swift`). Demo has its own invented set (`MoonShineCore/Sources/MoonShineFixtures/DemoMapping.swift`).

- **Shape:** one root key, `meta_tag_groups`, a list of 0–20 distinct names; each name by the line `name` rule (1–120 characters, at most 1 KiB, no C0 or DEL; `vault-contract.md` §1). Any other key, a second key, a null value or a list item that is not such a name makes the file invalid. At most 64 KiB, UTF-8, and the vault reader's YAML guards (no directive, no anchor with an alias, the depth and node caps).
- **Missing** (no entry at the path): no group is meta, and Settings says so.
- **Invalid or unreadable** (a folder or a link at the path, dangling or not; an empty or comment-only file, which has no `meta_tag_groups`): the whole file is refused, never one name dropped. The app keeps the stored workspace and refuses every import until it is quit (⌘Q) and opened again with a valid file; the CLI stops before it reads OmniFocus. Errors name a kind and a fixed key (`root` or `meta_tag_groups`), never a value.
- **Found:** Settings (`groups found: n of m`) and the CLI (`mapping: n of m groups found · meta tags k`, or `mapping: missing (no group is meta)`) count the current file's names among the top-level tag names of the workspace shown, whatever groups it was imported under: a misspelt name is not found, and n never exceeds m (PR #50 round 1).

## Findings from live data (2026-09-30)

- **V1 — repeating tasks (settled).** Completing a repeating task leaves the live task with its id and creates a completed copy with id `<liveId>.<n>`, its own `completionDate`, `added` ≈ completion time, and the same repetition rule. Completing a repeating _action group_ also clones its children as `<childId>.<n>` with parent `<groupId>.<n>`. Consequence: stats must be able to separate habit occurrences (86 % of completions) from one-off completions.
- **V2 — latency (target revised 2026-09-30).** Through the MCP server: any count that scans all tasks takes ~8 s; a 250-row page ~8–9 s (the server halves oversized pages, so a full export needs ≥ 17 pages ≈ 2.5 min). Decision: the UI reads only from the store (< 1 s); the full import runs in the background (≤ 20 s) and later refreshes are incremental (`modified` since the last import). Measured in phase 1 S3 (ADR-0003, phase-1 spec).
- **V3 — field use (settled, sample of 500 remaining tasks).** `estimatedMinutes` 23 %, `plannedDate` 10 % (128 of 1 079 by count), `dueDate` 7 % (83 by count), `deferDate` 5 % (44 by count), repetition 14 %, note 7 %, flagged 2 %.
- **V4 — tags (settled).** Hierarchy depth is exactly 2. Meta groups (six; their names are in `mapping.yaml`, § Meta tag groups) are top-level tags whose children have short English leaf names (a time box, a work type, a context, an energy level, a cycle; `data-report.md`); everything else is flat. 31 % of remaining tasks have no tags, 17 % only meta tags.

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
