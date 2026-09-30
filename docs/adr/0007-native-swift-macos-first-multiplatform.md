---
title: "0007 — Native Swift, macOS first, SwiftUI multiplatform"
status: proposed
date: 2026-09-30
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0003-omnifocus-adapter-jxa-now-plugin-export-for-sandbox]]"
---

# 0007 — Native Swift, macOS first, SwiftUI multiplatform

## Context and Problem Statement
The app must be very convenient and powerful on Mac (dense timelines, Gantt, keyboard), later available on iOS, integrate with OmniFocus (Apple Events), on-device Apple models, widgets and App Intents, and serve as a showcase. The owner is an expert in both native iOS and React Native. **Which stack?**

## Decision Drivers
- Deep macOS integration (JXA, App Intents, Foundation Models, widgets, menu bar).
- Performance of zoomable timelines.
- iOS later with shared code.
- Showcase value ("back to native" trend).

## Considered Options
1. **Swift: SwiftUI (+ AppKit where needed), shared Swift packages, macOS first.**
2. React Native (iOS) + React Native macOS.
3. Web stack (Tauri/Electron + React).

## Decision Outcome
**Chosen option: "1"**, because every integration requirement is first-class in Swift, timelines benefit from native rendering, and Core/Adapters packages are reused by iOS unchanged.

### Consequences
- Good — best OS integration and performance; iOS app reuses Core.
- Bad — no Android/web; not the owner's primary commercial stack (RN), so the showcase shows range rather than the main stack.
- Neutral — XcodeGen `project.yml` instead of hand-edited `.xcodeproj` (agent-friendly).

### Confirmation
Core builds and tests on Linux (`swift test`); app target builds in CI on macOS runner.
