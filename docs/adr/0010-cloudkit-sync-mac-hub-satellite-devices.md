---
title: "0010 — Sync for iPad/iPhone: CloudKit private database, Mac as the only importer, native data multi-writer"
status: proposed
date: 2026-10-01
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0002-sqlite-engine-document-attributes-change-log]]"
  - "[[0003-omnifocus-adapter-jxa-now-plugin-export-for-sandbox]]"
  - "[[0007-native-swift-macos-first-multiplatform]]"
  - "[[platforms]]"
---

# 0010 — Sync for iPad/iPhone: CloudKit private database, Mac as the only importer, native data multi-writer

## Context and Problem Statement

Phase 3b brings an iPad "planning studio" (and an iPhone capture app). OmniFocus can be imported only on the Mac (JXA, ADR-0003); the vault and the hours workbook are also read there. The iPad must show the same workspace and let the owner edit **MoonShine-native** data (plans, steps, effort levels, scenarios, review "seen" marks, time entries from the iPhone timer). **How do devices share the store, and who may write what?**

## Decision Drivers

- Single user, several Apple devices; private by default (ADR principle 5); no own server before phase 8.
- Imported provider data must have exactly one writer to avoid divergent truths.
- Native planning data is edited on iPad and Mac — conflicts are possible but rare.
- Reuse the store and change log from ADR-0002; offline-first on every device.

## Considered Options

1. **CloudKit private database via `CKSyncEngine`**: Mac pushes imported records (single writer); all devices push native records; per-field last-writer-wins with a conflict log.
2. Ship the ADR-0002 change log as files through iCloud Drive; each device replays.
3. CRDT documents (Automerge) for native data, synced through iCloud Drive.
4. Own sync server (phase 8 material).

## Decision Outcome

**Chosen option: "1"**, because `CKSyncEngine` handles change tracking, retries and account changes, keeps data in the owner's iCloud (sensitive fields via `encryptedValues`), and needs no server. Splitting ownership — **provider-sourced records are written only by the Mac importer; native records are multi-writer** — removes most conflicts by construction. Option 3 is revisited if real conflicts on plans appear in the conflict log.

### Consequences

- Good — iPad and iPhone work offline and converge; no server; data stays in the owner's iCloud.
- Good — the importer stays on the Mac, matching ADR-0003; iPad shows provider data read-only until phase 6 writes.
- Bad — requires the paid Apple Developer Program (CloudKit entitlement, device builds beyond 7-day provisioning).
- Bad — per-field LWW can drop one of two near-simultaneous edits to the same field; mitigated by the conflict log (shown in Settings) and by the rarity of single-user conflicts.
- Bad — CloudKit ties sync to Apple; an own backend (phase 8) would need a second sync adapter behind the same port.
- Neutral — a `SyncEngine` port in Core; the CloudKit implementation is an adapter (ADR-0001).

### Confirmation

- Contract tests: a provider-sourced record written on a non-Mac device is rejected; native edits on two simulated devices converge; conflicting edits produce a conflict-log entry, never a silent loss without a record.
- 3b acceptance: airplane-mode edits on iPad sync after reconnect; first sync of the full demo store < 30 s.

## Pros and Cons of the Options

### 2. Change log over iCloud Drive

- Good — reuses ADR-0002 directly. Bad — we own ordering, compaction, partial-file races and iCloud Drive eviction.

### 3. Automerge

- Good — conflict-free merges. Bad — a second data model beside SQLite; heavy for the expected conflict rate.

### 4. Own server

- Bad — infrastructure before any audience; against the phase-8 gate.
