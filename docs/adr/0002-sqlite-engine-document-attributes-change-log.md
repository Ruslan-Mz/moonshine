---
title: "0002 — SQLite (GRDB) as the engine, document-style attributes, append-only change log"
status: accepted
date: 2026-09-30
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0001-own-domain-model-with-ports-and-adapters]]"
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
---

# 0002 — SQLite (GRDB) as the engine, document-style attributes, append-only change log

## Context and Problem Statement

MoonShine keeps a local cache of provider data (OmniFocus, Obsidian) and native data that providers don't have (plans, scenarios, time entries, measurements, forecast snapshots, undo log). It must be fast for timeline and planning-board queries, work offline, survive provider swaps, and later sync across devices (own server or iCloud). The owner prefers a document/NoSQL model over writing SQL. **Which storage engine and data shape?**

## Decision Drivers

- Query shape: heavy aggregations over time ranges (hours per line per week, completions per ISO week, forecast inputs) and relations (task → project → line → artifact → horizon).
- Flexible, evolving fields per provider and per step kind.
- Nobody hand-writes SQL: typed Swift records; agents generate and test queries.
- Future sync without re-keying; history and undo.
- Longevity and licence compatible with AGPL-3.0 and a future proprietary build.

## Considered Options

1. **SQLite via GRDB**: typed Codable records, core fields as columns, flexible fields as a JSON `attrs` column, append-only `changes` table.
2. SwiftData (object API over SQLite, CloudKit sync).
3. Couchbase Lite (embedded document NoSQL with sync).
4. Realm.
5. JSON/markdown files per entity (document store on disk).
6. Automerge (CRDT documents).

## Decision Outcome

**Chosen option: "1"**, because the dominant queries are relational aggregations over time, which SQL engines do well and document stores do poorly; JSON columns give document-style flexibility where needed; GRDB's typed query interface means no hand-written SQL in app code; and a change log gives history, undo and a sync feed. CRDT documents (option 6) are re-evaluated when sync starts (phase 7, new ADR).

**Amendment (2026-11-01, owner; ADR-0010).** Sync starts in phase 3b, not phase 7: ADR-0010 chose CloudKit with the Mac as the only importer, and `docs/ROADMAP.md` puts the iPad and iPhone in 3b. The CRDT question is settled there, not in a new ADR.

### Consequences

- Good — one fast local engine; planning-board and timeline queries are indexed aggregates.
- Good — "document feel" in code: every entity is a Codable struct; provider-specific data lives in `attrs` JSON without migrations.
- Good — change log = audit of AI proposals and undo now, sync feed later.
- Bad — schema migrations for core columns (numbered GRDB migrations).
- Bad — sync logic is ours when it comes (or a CRDT layer then).
- Neutral — notes stay markdown files (ADR-0004), not rows.
- Note (2026-10-01, P1-S2) — history outlives the provider. A full import never removes a completed task: the snapshot only covers a 12-week window, so a completed task missing from it has aged out and stays in the store. Anything else missing from an import is soft-deleted (`removed_at`, logged as `delete`) and restored with the same id if it reappears. Trade-off: a completed task deleted in OmniFocus stays in MoonShine's history; the provider cannot tell "deleted" from "aged out", and history matters more for stats and forecasts. The rule lives in Core (`StoredWorkspace.merging`), so every `Store` applies it.
- Note (2026-10-07, P1-S3b-2a) — lines are the exception to "anything else missing is soft-deleted": a line is soft-deleted only after a clean vault read (budget note found, `lines:` parsed, no item skipped). When the vault cannot read the lines, or skips an item, the stored lines are kept and keep mapping tasks (`VaultLines`, `Importer.makeWorkspace`).
- Note (2026-10-10, P1-S3b-3a) — notes and artifacts are exceptions too: one leaves the store only when the read saw that it is gone. A stored note that exists and could not be read, or is no longer recognised, stays with its artifacts; a note whose `artifacts:` list was not read in full keeps its unread artifacts; a vault that was not read at all keeps everything (`VaultUnread`, `VaultSnapshot.notRead`, `Importer.makeWorkspace`; vault contract §3).
- Note (2026-10-01, P1-S2) — single writer process by design: imports are single-flight per `ImportService`, and a commit carries the store version its identity map was read at; an `IdentityConflict` means a second writer exists (an architecture violation), so it is never retried and stays loud.

### Confirmation

All persistence goes through GRDB records in the `Store` adapter; raw SQL only inside tested query functions; re-import idempotency test; migration tests from each previous schema version.

## Pros and Cons of the Options

### 2. SwiftData

- Good — least code, CloudKit for free. Bad — sync locked to CloudKit (blocks own server/web/Android), weaker control over aggregations and migrations.

### 3. Couchbase Lite

- Good — real document DB with N1QL-style queries and built-in sync. Bad — sync needs Couchbase server infrastructure; Community Edition binaries come under Couchbase's own licence agreement (check before any commercial build); heavier dependency.

### 4. Realm

- Bad — MongoDB deprecated Atlas Device Sync and the Realm SDKs (2024–2025); community-maintained only. Rejected for a long-lived project.

### 5. Files per entity

- Good — transparent, git-friendly. Bad — aggregations mean loading everything; no transactions. Kept only for notes.

### 6. Automerge

- Good — conflict-free multi-device sync, offline-first by design. Bad — queries/aggregations still need an index (SQLite anyway); premature for a single device.
