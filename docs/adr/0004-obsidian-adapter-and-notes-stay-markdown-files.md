---
title: "0004 — Obsidian adapter; lines in frontmatter; notes stay markdown files"
status: proposed
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

### Consequences

- Good — the owner already uses frontmatter (`type`, `parent`, `related`, `review_cadence`).
- Bad — table and YAML in the budget note can drift; YAML is authoritative for MoonShine.
- Neutral — vault path via security-scoped bookmark; default `~/ObsidianV`.

### Confirmation

Parser tests on fixture notes; invalid YAML shows a banner, never a crash; until phase 6 no code path writes to the vault (CI grep).
