---
title: "0005 — Assistant: provider-agnostic, typed tools over the domain, write-as-proposal, exposed via MCP"
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
  - "[[0008-license-and-distribution]]"
---

# 0005 — Assistant: provider-agnostic, typed tools over the domain, write-as-proposal, exposed via MCP

## Context and Problem Statement
The assistant must answer questions (summaries, "where is X", plan checks) and perform actions (create/complete/change), with Claude first and other providers later (including on-device Apple Foundation Models). **How is the assistant wired so it is safe, provider-agnostic, measurable and reusable outside the app?**

## Decision Drivers
- Safety: no silent writes to the owner's system.
- Provider choice (Claude first; others later; on-device for privacy).
- Measurability: evals in CI (showcase requirement).
- Reuse: same capabilities from Claude Desktop/Code.

## Considered Options
1. Free-form chat; model outputs text, app parses intents.
2. **Typed `ToolRegistry` over domain services; `AIProvider` protocol; read tools execute, write tools return a `Command` proposal that the user confirms; the same registry served as an MCP server.**
3. Delegate everything to an external agent (Claude Desktop + MCP only), no in-app assistant.

## Decision Outcome
**Chosen option: "2"**, because typed tools make behaviour testable (evals), proposals keep every write visible and undoable, and serving the registry over MCP gives option 3 for free.

### Consequences
- Good — one tool schema for UI actions, assistant and MCP.
- Good — evals: golden conversations on fixture snapshots check tool choice, arguments, tone rules and refusal to write without confirmation.
- Bad — tool schemas are an API to version.
- Bad — cloud providers see the data sent in context; mitigated by provider choice, minimal context and a visible "what was sent" log.
- Neutral — API key in Keychain for single-user builds; a future public build needs an own backend proxy (phase 8), never a key in the bundle.

### Confirmation
Eval suite runs in CI on every PR touching `Assistant/`; a test asserts that no write tool mutates the store without a confirmed proposal; token/cost logged per request.
