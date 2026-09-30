---
title: "0008 — License and distribution: AGPL-3.0 with sole copyright; direct distribution now, App Store later"
status: proposed
date: 2026-09-30
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[ROADMAP]]"
---

# 0008 — License and distribution: AGPL-3.0 with sole copyright; direct distribution now, App Store later

## Context and Problem Statement
The repo will be public (showcase, possible users with the same stack), but the owner may later sell an App Store version and a hosted service. **Which license and distribution path keep both options open?**

## Decision Drivers
- Public source for showcase and trust.
- Keep the right to sell (App Store, hosted backend) later.
- Discourage a third party from turning it into a competing hosted product.
- Simplicity.

## Considered Options
1. MIT.
2. **AGPL-3.0, owner keeps sole copyright (external contributions only under a CLA), dual-license later.**
3. FSL-1.1 (source-available, converts to MIT/Apache after 2 years).
4. Private repo.

## Decision Outcome
**Chosen option: "2"**, because it is a real open-source licence (good for showcase), blocks closed hosted clones, and — as sole copyright holder — the owner can still ship a proprietary App Store build and hosted service. Not legal advice; confirm with a lawyer before phase 8.

### Consequences
- Good — commercial options remain with the owner.
- Bad — AGPL scares some companies from using or contributing; third parties cannot ship it to the App Store.
- Bad — a CLA adds friction for contributors (acceptable: contributions are not a goal now).
- Neutral — distribution now: locally signed / Developer ID, non-sandboxed (JXA). App Store later requires the sandboxed OmniFocus path (ADR-0003) and a backend proxy for AI keys (ADR-0005).

### Confirmation
`LICENSE` = AGPL-3.0; `CONTRIBUTING.md` states the CLA requirement; no third-party code under incompatible licences (dependency licence check before adding any dependency).

## Pros and Cons of the Options
### 1. MIT
- Good — maximum adoption. Bad — anyone can ship a paid clone or hosted version.
### 3. FSL
- Good — strongest commercial protection. Bad — not OSI open source ("open source" claim would be inaccurate).
### 4. Private
- Bad — no showcase value.
