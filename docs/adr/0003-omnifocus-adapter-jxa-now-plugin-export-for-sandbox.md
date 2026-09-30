---
title: "0003 — OmniFocus adapter: JXA bridge now, plug-in export for sandboxed builds"
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

# 0003 — OmniFocus adapter: JXA bridge now, plug-in export for sandboxed builds

## Context and Problem Statement
OmniFocus has no cloud API. On macOS it is scriptable via AppleScript/JXA and Omni Automation (`evaluateJavascript`); on iOS a third-party app cannot read its database. Omni Group has announced first-class MCP support; community MCP servers exist. App Store builds are sandboxed, which makes Apple Events to other apps hard. **How does the OmniFocus adapter read (and later write) data across distribution modes?**

## Decision Drivers
- Phase 1: fast bulk read on macOS, no extra runtime.
- Phase 5: writes (create/complete/defer/plan).
- Future sandboxed / App Store / iOS builds.

## Considered Options
1. Runtime dependency on an MCP server.
2. **JXA/Omni Automation bridge in the app (direct distribution)**; for sandboxed builds, an Omni Automation **plug-in** that exports a JSON snapshot to a shared folder and handles write requests via URL.
3. Parse OmniFocus database/sync files.

## Decision Outcome
**Chosen option: "2"**, because it is fast and dependency-free today and has a known path for sandboxed builds. MCP is used in Phase 0 for discovery only; revisit when Omni ships official MCP (may replace the bridge — new ADR).

### Consequences
- Good — one JSON snapshot contract shared by the JXA bridge, the plug-in and fixtures.
- Bad — direct-distribution build must be non-sandboxed with the Automation permission.
- Bad — we maintain a JS script against Omni Automation.
- Neutral — writes in phase 6: Omni Automation via JXA (direct), `omnifocus:///add` URL or plug-in (sandboxed).

### Confirmation
Snapshot contract tests on fixtures. Phase 1 S3 measures on the real database and logs in `docs/method/log.md`: full background import ≤ 20 s, incremental refresh (items modified since the last import), UI reading only from the store in < 1 s. Phase-0 discovery showed a full-database scan costs ~8 s through Omni Automation, which is why the target is a background import rather than a blocking < 5 s load.

## More Information
- kip-d/omnifocus-mcp: https://github.com/kip-d/omnifocus-mcp
- Omni Roadmap 2026 (post-WWDC): https://www.omnigroup.com/blog/omni-roadmap-2026-post-wwdc-update
