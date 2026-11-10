---
title: "0004 — Obsidian adapter; lines in frontmatter; notes stay markdown files"
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
---

# 0004 — Obsidian adapter; lines in frontmatter; notes stay markdown files

## Context and Problem Statement

The owner's rule: goals, artifacts, plans and budgets live in Obsidian; OmniFocus holds only execution. MoonShine needs lines (with budgets and tool mappings), artifacts per horizon and notes — and may one day provide its own notes module. **How do we read Obsidian now without locking the future notes module into a proprietary format?**

## Decision Drivers

- No parallel goal system; extend existing notes.
- Stable machine-readable contract.
- Future native notes must stay Obsidian-compatible (user can keep using both, or leave either).

## Considered Options

1. Line/goal definitions inside the app.
2. Parse markdown tables in existing notes.
3. **YAML frontmatter contracts in existing notes** (`lines:` in the budget note; `type`, `scale`, `period`, `parent` in artifact notes; `artifacts:` list in the year note — see `docs/discovery/vault-contract.md`) + future native notes as **plain markdown files in a folder**.
4. Future native notes stored in SQLite.

## Decision Outcome

**Chosen option: "3"**, because it keeps Obsidian as the source of truth without fragile parsing, and makes the future notes module "just another markdown folder", so switching away from Obsidian is not a migration.

**Amendment (2026-10-06, ADR-0015).** Vault writes start in the Write phase, not the Act phase, and only through the vault commands of ADR-0015 (`CreateNote`, `AppendToNote`, `UpdateNoteBody`, `SetNoteProperty`) on the `CommandBus`, with a precondition, byte fidelity and undo. Notes stay Markdown files that Obsidian also edits; there is no own notes store.

### Consequences

- Good — the owner already uses frontmatter (`type`, `parent`, `related`, `review_cadence`).
- Bad — table and YAML in the budget note can drift; YAML is authoritative for MoonShine.
- Neutral — vault path via security-scoped bookmark; default `~/ObsidianV`.

**Amendment (2026-11-10, owner; S4-4d, PR #53).** There is no default vault path: the Neutral consequence above no longer holds in its second half. The owner chooses the vault folder in Settings; the app keeps a security-scoped, read-only bookmark of it, and refuses a folder that holds no `.obsidian/` folder. A chosen folder that no longer holds `.obsidian/` is not read at all, so nothing stored is removed. Read-only is enforced by MoonShine's code and by `scripts/check-vault-writes.mjs` in CI, not by the system: the app is not sandboxed (ADR-0003), so the bookmark's read-only option restricts nothing until it is.

### Confirmation

Parser tests on fixture notes; invalid YAML shows a banner, never a crash; until the Write phase no code path writes to the vault: a CI check (added in S3b-3) that covers every target that can reach the vault — `MoonShineCore`, all of `Adapters/` (the `moonshine-import` CLI included) and `Apps/` once it exists — and fails on any file-writing call outside a short allowlist of files that write MoonShine's own data (the store); from the Write phase `VaultWriter` joins the allowlist.
