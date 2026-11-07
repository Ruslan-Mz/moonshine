---
title: "0011 — Change-driven import: full snapshots through the bridge, triggered when OmniFocus resigns active"
status: proposed
date: 2026-10-02
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0002-sqlite-engine-document-attributes-change-log]]"
  - "[[0003-omnifocus-adapter-jxa-now-plugin-export-for-sandbox]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0012-calendar-eventkit-read-only-per-device]]"
  - "[[snapshot-contract]]"
---

# 0011 — Change-driven import: full snapshots through the bridge, triggered when OmniFocus resigns active

## Context and Problem Statement

MoonShine is meant to become the owner's main app for time, so its picture of OmniFocus must stay current without pressing a refresh button. OmniFocus offers no change notifications to other apps. The S3a-1 measurements (OmniFocus 4, 6,420 tasks in the database, 1,961 in the snapshot at the time of the two single full-import runs of 2026-10-02 (background, and with OmniFocus frontmost) (1,962 in later runs), release build) show what the bridge costs:

| Measurement                                          | OmniFocus held                   | Total  |
| ---------------------------------------------------- | -------------------------------- | ------ |
| Probe: task count only, OmniFocus in the background  | 6.8 s                            | 7.0 s  |
| Probe: `modified` on every task, background          | 6.9 s (list 6.7 s + loop 0.14 s) | 7.0 s  |
| Probe: `modified` on every task, OmniFocus frontmost | 2.0 s                            | 3.2 s  |
| Full import, background                              | 10.8 s                           | 11.1 s |
| Full import with OmniFocus frontmost                 | 2.7 s                            | 4.0 s  |
| Decode + merge + commit (MoonShine's share)          | —                                | 0.1 s  |

Three facts follow. Building the task list is the whole cost; reading properties is almost free. OmniFocus is unresponsive while a script runs. macOS throttles OmniFocus in the background, making the same script about 3.4× slower. **When and how does MoonShine import, so that data is fresh and the owner never feels OmniFocus freeze?**

## Decision Drivers

- Freshness: a change made in OmniFocus should be visible in MoonShine within seconds of switching to it.
- The owner must not feel OmniFocus freeze while working in it.
- Official, documented interfaces only; no access to other apps' private data (VISION principle 5, ADR-0003).
- One import path to test and trust; MoonShine's own share of an import is already negligible.
- No writes to OmniFocus (CLAUDE.md rule 6).

## Considered Options

1. **Always a full snapshot through the Omni Automation bridge, started by change signals: OmniFocus resigned active, a slow timer while it is in the background, launch and ⌘R. Never while OmniFocus is frontmost.**
2. Poll a cheap change probe every few seconds and import only when it changes.
3. Incremental snapshots (tasks modified since the last import).
4. Read OmniFocus' SQLite cache database and watch the file for changes.
5. OmniFocus' own export to a file that MoonShine parses.
6. Wait for native tasks (phase 7).

## Decision Outcome

**Chosen option: "1"**, because the moment the owner leaves OmniFocus is both when changes have just been made and when OmniFocus is still unthrottled: the time the import holds it then is expected to be close to the frontmost figure because throttling takes time to set in; not measured yet — the real value lies between 2.7 s and 10.8 s. It uses only the documented bridge and keeps a single import path. It replaces ADR-0003's confirmation criterion on incremental refresh.

Rules that follow:

- **`ChangeSignal` port in Core**: a stream of "a source may have changed" events. Mac adapters: OmniFocus resigned active (`NSWorkspace.didDeactivateApplicationNotification` for its bundle id), a timer, app launch, ⌘R. Calendar changes (ADR-0012) use the same port but do not start the importer.
- **Never while OmniFocus is frontmost.** A signal that arrives then is held until OmniFocus resigns active. ⌘R is always allowed: MoonShine is frontmost when it is pressed.
- **Timer**: default 15 min, a setting; runs only while OmniFocus is running and not frontmost; skipped when an import finished within the interval. It exists for changes that arrive through OmniFocus' own sync from other devices.
- **Coalescing**: `ImportService` stays single-flight. A signal during an import schedules exactly one more import after it.
- **Always full snapshots.** The incremental mode of contract v0.2 stays defined and unused. Only a full snapshot may soft-delete (ADR-0002 retention rule unchanged).
- **The UI never waits.** View models observe the store; stored data is shown at once and updates when the import commits. The status bar shows "updated N min ago" and "updating…".
- **Target**: the refresh lands ≤ 5 s after OmniFocus resigns active, measured from the signal to the refresh landing in the store (signal → landing: the wait before the import plus the import total; the import total is shown beside it, and neither is the time OmniFocus is held; owner, 2026-10-28) — provisional until measured with the real trigger in S4 (with OmniFocus frontmost: 4.0 s).
- **`imports` table** (S4): trigger, the wait from the signal, start, end, import total, time OmniFocus was held, outcome, row counts. It feeds the status bar and lets the timings be watched as the database grows.
- **Archiving is the owner's lever.** Moving old completed items to OmniFocus' archive shrinks the task list and the import time roughly in proportion. MoonShine keeps completed tasks in its own store, so no history is lost — provided a full import ran before archiving. MoonShine never archives by itself.
- **OmniFocus not running**: no import; MoonShine shows the last import and says so.

**Amendment (2026-11-04, owner; PR #44 round 1).** A coalesced follow-up records the request that queued it, unless a resign-active request joins it: then it records resign-active, with that request's own signal time, so the target's median keeps every resign-active signal. A request without a signal time is signalled when it reaches `ImportService`, so every recorded import has a measured wait; a Demo launch that starts at once waits 0. When S4-4b adds more signals, its planning ranks each one; until then resign-active is the only signal that outranks the first request.

**Amendment (2026-11-05, owner; S4-4b-1).**

- **Ranking.** Launch, ⌘R and timer each rank below resign-active, and none outranks another: a resign-active request that joins another is recorded with its own signal time; otherwise the first request is recorded (one rule, `ImportRequest.joined(by:)`, for the coordinator and `ImportService`). A pending request that starts only because a joined ⌘R exempts it from the frontmost hold is recorded as ⌘R, with ⌘R's signal time, unless resign-active is in it; then resign-active.
- **Coalescing.** A coordinator in Core takes the signals and holds at most one request behind the running import; it checks OmniFocus' state, and for a timer-only request the interval, when that request is about to start. `ImportService` stays single-flight, and its own follow-up is a guard the coordinator never reaches.
- **Frontmost.** A launch, timer or resign-active signal that arrives while OmniFocus is frontmost is dropped, not held; this supersedes "held" in `:60` and `:99`. Resign-active brings its own request when OmniFocus leaves the front, and ⌘R is still allowed. If OmniFocus quits instead, the model learns it from the coordinator's OmniFocus-state event, and 4c-1 shows the sentence of `:68`.
- **Timer.** A tick is skipped when the last import that committed in this process started less than the interval ago (owner, 2026-10-28: the interval runs from the start, so a background import of about 11 s does not push the next tick a whole interval back); a failed import does not count. This supersedes "finished" in `:61`. The reference is the coordinator's in-process monotonic reading, never seeded from the store: the wall clock can move, and after a relaunch the launch import comes first anyway.
- **The UI never waits** (`:64`). The app's model re-reads the store when the coordinator reports a committed import. The app's import path is the only writer of the app's store; the CLI writes a separate store (from 4c-1). If the CLI ever has to write the app's store, the app would re-read it on `PRAGMA data_version` when it becomes active; that needs a new decision.

**Amendment (2026-11-05, owner; S4-4c-1).**

- **A source switch.** Each source (Demo, Live) has its own coordinator and store for the life of the process. Its first selection starts it with a launch request; a switch back to it in Settings is the owner's action and is recorded as ⌘R (`manual`), with ⌘R's rules: allowed while OmniFocus is frontmost, dropped while it is not running.
- **⌘R in Live, until S4-4b-2.** Live's 4c-1 source gives OmniFocus' state once, at launch. So ⌘R first reads whether OmniFocus runs: a start since a not-running state is sent as background, and a quit as not running. Frontmost → background is never sent, so no ⌘R is recorded as resign-active and the target's median stays clean.
- **OmniFocus not running** (`:68`): with an import stored, the status bar says "OmniFocus is not running — showing the last import"; with none, Today says MoonShine has not read OmniFocus yet, and why. A quit that only a failed ⌘R import sees says the same, and so does a quit while the bridge reads (OSA errors -600 and -609). Since the source gives one state at launch, the sentence can outlast an OmniFocus start until the next ⌘R (S4-4b-2's change signals end this).
- **A new day** (owner, 2026-11-06, PR #46 round 1): when the calendar day changes, or a wake from sleep crosses midnight, Today is rebuilt from the workspace already shown; nothing is imported or written.

**Amendment (2026-11-07, owner; S4-4b-2).**

- **The Mac sources.** Live's source observes `NSWorkspace`'s activate, deactivate, launch and terminate notifications for OmniFocus' bundle id: activate is frontmost, deactivate is background (not running when the app has terminated), launch is background, terminate is not running. It installs its observers and reads OmniFocus' state in one main-actor turn, so the first state is never older than one that follows it. An OmniFocus launch starts no import (the four sources of `:59`): a shown OmniFocus resigns active later, a hidden one gets the next tick.
- **The settle.** Resign-active waits 0.5 s before it joins, timed from the deactivate, so the settle counts in its wait; nothing starts while it is open, and a tick or ⌘R that arrives then joins it and resign-active is recorded. A quit or a return to OmniFocus within the settle drops it silently: it was not a leave. A ⌘R that joined meanwhile is then recorded as ⌘R with its own wait; this narrows "unless resign-active is in it" of the ranking rule (amendment of 2026-11-05) to a resign-active request that outlived its settle. The settle exists because the bridge's `running()` check cannot see an OmniFocus that is quitting.
- **Ranking.** 4b-2 adds no trigger: deactivate is resign-active, and the tick is the timer of the amendment of 2026-11-05. Activate, launch and terminate make no request; they only decide whether a pending one starts.
- **Timer.** It runs for the life of Live's source and ticks every interval plus 1 s: a tick that sleeps exactly the interval can arrive a hair before the interval from the last committed start, which the coordinator reads after the tick crosses to it, and would then be skipped, halving the rate. A tick while OmniFocus is frontmost or not running is dropped, which keeps `:61`'s "runs only while OmniFocus is running and not frontmost" in effect.
- **⌘R keeps its reading** (amendment of 2026-11-05, S4-4c-1): it stays as a resync of the held state, the one in-app correction if a notification was missed. It still never sends frontmost → background.
- **The not-running sentence** (`:68`) ends when OmniFocus is seen running again: a running state clears a not-running failure. Other failures stay until a commit.
- **Live while Demo is shown.** A source not shown imports nothing and keeps tracking OmniFocus' state; the switch back imports as ⌘R. Demo never holds OmniFocus.
- **Quit.** The app's store runs a TRUNCATE checkpoint and closes when the app terminates, so its data is in the main file and no WAL is left behind (the follow-up of PR #46).

### Consequences

- Good — fresh data a few seconds after switching apps, with no perceptible freeze in normal use.
- Good — one import path, documented interfaces, nothing read from OmniFocus' private files.
- Good — the same port serves the calendar signal now and a sync signal later.
- Bad — a timer import holds OmniFocus for about 11 s in the background; if the owner returns to OmniFocus during it, he feels the freeze. A script already running cannot be cancelled.
- Bad — a change made on another device appears only after OmniFocus on the Mac has synced and then up to one timer interval later.
- Bad — "seconds", not "instant". True real-time for tasks needs MoonShine-native tasks (phase 7).
- Bad — the 3.4× background slowdown is undocumented macOS behaviour and may change; the cost grows with the size of the OmniFocus database.
- Neutral — the iPad and iPhone receive provider data from the Mac (ADR-0010), so their freshness is the Mac's plus CloudKit delivery.

### Confirmation

- Core tests with a fake signal source: signals during an import produce exactly one follow-up import; a signal while "OmniFocus frontmost" is held and released on resign-active; the timer is skipped after a recent import.
- The `imports` table shows, on live data, the held time per trigger; the method log records the median after one week of use.
- S4 records per trigger in the `imports` table the wait from the signal, the import total and the time OmniFocus was held; if the median signal → landing (wait plus import total) for the resign-active trigger exceeds 5 s, this ADR is revisited.
- Revisit this ADR if the refresh after resign-active exceeds the 5 s target (same metric: signal → landing), or if OmniFocus gains change notifications or a query that avoids listing every task.

## Pros and Cons of the Options

### 2. Poll a change probe

- Good — would import only when needed.
- Bad — the cheapest possible probe still holds OmniFocus for 2.0–6.8 s, because listing tasks is the cost. Polling would freeze OmniFocus every few seconds.

### 3. Incremental snapshots

- Good — smaller documents.
- Bad — saves nothing: finding the modified tasks needs the full task list (6.7 s of 6.9 s). It adds a second merge path, stale deletions and an equivalence problem for no gain.

### 4. OmniFocus' SQLite cache database

- Good — would be fast, non-blocking and give a file-change signal.
- Bad — not reachable: OmniFocus' group containers are not readable from Terminal.app without Full Disk Access; the app container holds no SQLite files. A sandboxed build could never read them, and the format is undocumented. Rejected; reopened only if option 1 stops meeting its target.

### 5. OmniFocus' own export

- Good — official feature, six writable types.
- Bad — no script path: Omni Automation state does not survive between calls, OmniFocus is sandboxed and cannot write to a folder of ours without a save dialog, and a Save-As would be a write.

### 6. Wait for phase 7

- Bad — leaves phases 1–6 with manual refresh only, which defeats "main app for time".
