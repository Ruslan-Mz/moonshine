---
title: "0001 — Own domain model with ports and adapters"
status: accepted
date: 2026-09-30
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[ARCHITECTURE]]"
  - "[[0002-sqlite-engine-document-attributes-change-log]]"
---

# 0001 — Own domain model with ports and adapters

## Context and Problem Statement

MoonShine must show and eventually edit tasks, projects, goals and notes that today live in OmniFocus and Obsidian, talk to an AI provider (Claude first), import hours from Excel — and later be able to replace any of these tools, including with native modules. **How do we structure the code so that swapping a tool does not mean rewriting the app?**

## Decision Drivers

- Replaceability of OmniFocus, Obsidian and the AI provider (explicit requirement).
- Path to native task/notes modules without a rewrite.
- Testability without any external app installed (CI, cloud agents, public repo).
- One API for UI, assistant tools and MCP server.

## Considered Options

1. UI binds directly to provider data (OmniFocus objects, markdown files).
2. **Own domain model + ports (protocols) + adapters**, domain in a pure Swift package.
3. Adopt an existing generic PKM/task schema (e.g. Todo.txt / iCalendar VTODO) as the model.

## Decision Outcome

**Chosen option: "2"**, because it is the only option that satisfies replaceability and the native-module path at the same time, and it gives the assistant and the MCP server the same typed API as the UI.

### Consequences

- Good — adapters are small and independently testable; fixtures drive the whole app.
- Good — capabilities per adapter (read / write / which commands) are explicit.
- Bad — mapping code for every provider; some provider features will not map cleanly (e.g. OmniFocus perspectives).
- Neutral — the domain model will evolve; changes go through ADRs.

### Confirmation

`MoonShineCore` has no imports of AppKit (nor Cocoa, Carbon, Quartz, which re-export it)/SwiftUI/SwiftUICore/OSAKit/GRDB/EventKit/Yams (CI: `scripts/check-core-imports.sh`); adapters depend on Core, never the reverse; the Demo-mode app runs entirely on fixture adapters.

## Pros and Cons of the Options

### 1. Bind to providers

- Good — fastest first screen. Bad — every replacement is a rewrite; no single API for the assistant.

### 3. Generic external schema

- Good — interoperability. Bad — no concepts for lines, horizons, skill tracks, forecasts.
