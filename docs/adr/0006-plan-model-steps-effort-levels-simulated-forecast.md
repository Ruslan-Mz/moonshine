---
title: "0006 — Plan model: step plans, effort levels and a simulated, adaptive forecast"
status: proposed
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
  - "[[0004-obsidian-adapter-and-notes-stay-markdown-files]]"
---

# 0006 — Plan model: step plans, effort levels and a simulated, adaptive forecast

## Context and Problem Statement

The owner wants a forecast for **any** project, not only "hours to master a piece": a calisthenics progression ("this week X, then next week I can do Y"), a language course, reading a textbook, a violin repertoire. He wants to plan with **min / normal / max** effort per project, see when each goal is reached under each level, see dates drift when practice slips, and have **one board where all chosen projects compete for weekly time** and their parameters can be moved. **What planning and forecasting model supports all of this, honestly and explainably?**

## Decision Drivers

- Works for different kinds of progress: hours, sessions, quantities (pages, lessons, cards), measurable targets (tempo, reps, distance), manual checkpoints.
- Respects physical limits that time can't compress (recovery, adaptation: "at most 3 sessions/week", "each progression step ≥ 1 week").
- Separates **what I choose** (how much I invest per week) from **what I don't know** (how long a step really takes).
- Adaptive: learns from my real pace and my estimation bias.
- Explainable in one sentence; uncertainty shown, never fake precision.
- Tone: drift is a fact with a next step, never a failure.

## Considered Options

1. Hand-set target dates per task (classic Gantt).
2. Single number per track: `remaining effort / recent velocity`.
3. **Step plans + effort levels + capacity-aware Monte Carlo scheduling, calibrated on history.**
4. Automatic optimiser that allocates all weekly time across projects (LP / constraint solver).

## Decision Outcome

**Chosen option: "3"**, because it covers every progress type and the physical limits, keeps the controllable input (effort level) separate from uncertainty (estimates), and yields date **ranges** that adapt to real behaviour. Option 4 is later offered as an _assistant suggestion_ on top of option 3, never as autopilot.

### The model

- **Plan** (belongs to a Project/Goal) = steps with prerequisites (a small DAG; usually a sequence).
- **Step** — a completion criterion of one kind:
  `effort(hours)` · `sessions(n)` · `quantity(n, unit)` · `metric(target, unit, direction)` · `checkpoint(manual)`;
  a **three-point estimate** (optimistic / likely / pessimistic) of the effort or sessions it takes;
  optional `minDuration` (e.g. 1 week of adaptation) and `maxRate` (e.g. ≤ 3 sessions/week).
- **Effort levels** per project: `min / normal / max` in hours/week or sessions/week (+ custom value). The initial `normal` comes from the vault budget (ADR-0004).
- **Capacity**: weekly hours available for development lines, with calendar exceptions (trips, dacha, illness), after the fixed foundation (core practice, sleep, family).
- **Scenario** = one chosen level (or value) per project. Several scenarios can be saved and compared.
- **Evidence**: time entries, session logs, metric measurements, step completions.

**Amendment (2026-11-01, owner; ADR-0023).** The Board's weekly capacity per line starts from the routine template's flexible and protected minutes for that line (phase 3). The budget's `budget_h_week` stays the default `normal` level; the line's template minutes per week are shown beside it as a fact, and the two are never reconciled automatically. A day the owner marks away is a capacity exception of kind `away`, the same record as the trips above, set by `AddCapacityException` (ADR-0013).

### The engine

1. **Calibrate** (per line, from history): estimation bias = actual ÷ estimated effort of completed steps; adherence = realised ÷ planned weekly effort. Defaults of 1.0 until data exists (evidence-based scheduling).
2. **Simulate** (Monte Carlo, ~1 000 runs): sample each step's effort from its three-point distribution × bias; sample weekly realised effort from the scenario level × adherence (or from real history in "actual pace" mode); schedule steps week by week respecting prerequisites, `minDuration`, `maxRate` and total capacity.
3. **Output**: per step and per project a date band **p10 / p50 / p90**, plus weekly load per project.
4. **Modes**: _Actual pace_ (history) · _Scenario_ (min / normal / max / custom) · _Inverse_ — pin a target date → required effort per week (search over the level).
5. **Snapshots**: the p50/p90 of every active project stored weekly → **drift chart** ("the date moved +3 weeks since September; practice was 40% of normal").

### Planning board (UI consequence)

One screen: rows = selected projects; per row a level switch (min / normal / max), a fine slider, and the projected band on a shared timeline. Top: stacked weekly load vs capacity; overload is shown as a neutral "doesn't fit by N h/week" with the projects that would move. Scenarios A/B side by side. Changes recompute live.

### Consequences

- Good — one model for music, sport, languages, study, research, work.
- Good — honest ranges; adaptation to real pace and to personal estimation bias.
- Good — showcase: a tested forecasting engine (deterministic seeds in tests).
- Bad — plans take input effort. Mitigation: plan templates (progression, repertoire, course) and the assistant drafting a plan from plain text ("my calisthenics plan: …") as a proposal.
- Bad — until evidence exists, forecasts rest on estimates; the UI says so ("based on estimates only").
- Neutral — scenarios, levels and plans are MoonShine-native data; the active scenario's h/week can be published to the vault budget note once writes exist (the Act phase), keeping Obsidian the human-readable truth.

### Confirmation

- Engine tests with fixed seeds on synthetic histories (steady, slipping, resuming, over-capacity, minDuration-bound) assert direction and size of changes.
- Property tests: more effort never yields a later p50; adding a prerequisite never yields an earlier one.
- Copy review against the tone rules.

## Pros and Cons of the Options

### 1. Hand-set dates

- Good — familiar. Bad — dates are wishes; no adaptation; drift invisible.

### 2. Single velocity number

- Good — trivial. Bad — no progressions, no physical limits, no scenarios, no uncertainty.

### 4. Automatic optimiser

- Good — "best" allocation. Bad — opaque; takes decisions away from the owner; needs an objective function nobody can state honestly. Useful later as a suggestion.

## More Information

Background: PERT three-point estimates; Monte Carlo schedule simulation; evidence-based scheduling (historical velocity); progressive overload / periodisation (why `minDuration` and `maxRate` exist).
