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
  - "[[0013-captures-proposals-command-queue-autonomy]]"
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

**Amendment (2026-10-03, ADR-0013).** Every write is a proposal confirmed by the owner, **except commands of the `auto` class** defined in ADR-0013 (simple, unambiguous, undoable changes that follow from the owner's own utterance and pass its checks). `auto` commands are applied at once, logged in the activity log and undoable; everything else stays a confirmed proposal.

**Amendment (2026-11-02, owner; `docs/specs/phase-2-plan.md` § Decided, Q8).** Provider and model are configurable, because other users will want other models; this is a requirement, not a later option.

- The `AIProvider` port in Core is provider-neutral: a request with a JSON-schema output, and a typed reply. Nothing in Core names a vendor or a model id.
- Settings → Assistant lists the providers and keeps a model id per **feature**: Log by text from phase 2; day checkpoints L2 (ADR-0022) and the routine assistant (ADR-0023) in phase 4. Each provider has its own key in the Keychain and its own consent text; a local endpoint is labelled "stays on this Mac".
- Phase 2 ships the Claude API adapter (LT3), then an OpenAI-compatible adapter with a configurable base URL (AP2), which also covers local servers such as Ollama or LM Studio.
- Safety does not depend on the model: the app checks every span and value whatever the provider (ADR-0013 § Conditions for `auto`), so a weaker model gives more blocking problems, never wrong data.
- The eval set and a CLI command (`moonshine-import eval-dictation --provider … --model …`, counts only) run against any configured model, so a user can check his choice. The proposed models are defaults, kept only if they do well on that eval.
- CI allows the network API in the AI adapter target only.

### Consequences

- Good — one tool schema for UI actions, assistant and MCP.
- Good — evals: golden conversations on fixture snapshots check tool choice, arguments, tone rules and refusal to write without confirmation.
- Bad — tool schemas are an API to version.
- Bad — cloud providers see the data sent in context; mitigated by provider choice, minimal context and a visible "what was sent" log.
- Neutral — API key in Keychain for single-user builds; a future public build needs an own backend proxy (phase 8), never a key in the bundle.

### Confirmation

Eval suite runs in CI on every PR touching `Assistant/`; a test asserts that no write tool mutates the store without a confirmed proposal, except an `auto` command that passes ADR-0013's checks (a command of the `confirm` class, or an `auto` command that fails a check, never executes without confirmation); token/cost logged per request.
