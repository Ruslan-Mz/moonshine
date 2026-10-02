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

MoonShine is meant to become the owner's main app for time, so its picture of OmniFocus must stay current without pressing a refresh button. OmniFocus offers no change notifications to other apps. The S3a-1 measurements (OmniFocus 4, 6,420 tasks in the database, 1,961 in the snapshot, release build) show what the bridge costs:

| Measurement                                          | OmniFocus held                   | Total  |
| ---------------------------------------------------- | -------------------------------- | ------ |
| Probe: task count only, OmniFocus in the background  | 6.8 s                            | 7.0 s  |
| Probe: `modified` on every task, background          | 6.9 s (list 6.7 s + loop 0.14 s) | 7.0 s  |
| Probe: `modified` on every task, OmniFocus frontmost | 2.0 s                            | 3.2 s  |
| Full import, background                              | 10.8 s                           | 11.1 s |
| Full import right after OmniFocus was frontmost      | 2.7 s                            | 4.0 s  |
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

**Chosen option: "1"**, because the moment the owner leaves OmniFocus is both when changes have just been made and when OmniFocus is still unthrottled: the import holds it for 2.7 s while nobody is looking at it. It uses only the documented bridge and keeps a single import path.

Rules that follow:

- **`ChangeSignal` port in Core**: a stream of "a source may have changed" events. Mac adapters: OmniFocus resigned active (`NSWorkspace.didDeactivateApplicationNotification` for its bundle id), a timer, app launch, ⌘R. Calendar changes (ADR-0012) use the same port but do not start the importer.
- **Never while OmniFocus is frontmost.** A signal that arrives then is held until OmniFocus resigns active. ⌘R is always allowed: MoonShine is frontmost when it is pressed.
- **Timer**: default 15 min, a setting; runs only while OmniFocus is running and not frontmost; skipped when an import finished within the interval. It exists for changes that arrive through OmniFocus' own sync from other devices.
- **Coalescing**: `ImportService` stays single-flight. A signal during an import schedules exactly one more import after it.
- **Always full snapshots.** The incremental mode of contract v0.2 stays defined and unused. Only a full snapshot may soft-delete (ADR-0002 retention rule unchanged).
- **The UI never waits.** View models observe the store; stored data is shown at once and updates when the import commits. The status bar shows "updated N min ago" and "updating…".
- **Target**: the refresh lands ≤ 5 s after OmniFocus resigns active (measured: 4.0 s).
- **`imports` table** (S4): trigger, start, duration, time OmniFocus was held, row counts. It feeds the status bar and lets the timings be watched as the database grows.
- **Archiving is the owner's lever.** Moving old completed items to OmniFocus' archive shrinks the task list and the import time roughly in proportion. MoonShine keeps completed tasks in its own store, so no history is lost — provided a full import ran before archiving. MoonShine never archives by itself.
- **OmniFocus not running**: no import; MoonShine shows the last import and says so.

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
- Revisit this ADR if the import after resign-active exceeds 5 s, or if OmniFocus gains change notifications or a query that avoids listing every task.

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
