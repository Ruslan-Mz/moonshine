# MoonShine — Roadmap

**Rule of gates:** a phase starts only after the previous one has been **used for real for ≥ 2 weeks** and its "done" link exists. Every phase has a hard timebox; when it runs out, cut scope, don't extend.

| Phase | Name                            | Timebox      | What ships                                                                                                                                                                                                      | Jobs    |
| ----- | ------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| 0     | **Discover**                    | 1 evening    | OmniFocus + vault data report via MCP, contracts, synthetic fixtures, line mapping, weekly-review prompt                                                                                                        | —       |
| 1     | **See**                         | 2 weekends   | macOS app, read-only: Today / Week / Month, Lines, trace task → project → line → artifact. OmniFocus + Obsidian adapters, local store, Demo mode                                                                | J1      |
| 2     | **Plan**                        | 3 weekends   | Plans with steps of any kind, effort levels min/normal/max, time entries + measurements (quick log, OmniFocus completions), forecast engine (calibration + Monte Carlo), project forecast view with drift chart | J2      |
| 3     | **Board**                       | 2 weekends   | Planning board: all selected projects, levels + sliders, weekly load vs capacity, scenarios A/B, inverse mode (target date → effort); Excel hours import with column mapping                                    | J2b, J5 |
| 4     | **Ask**                         | 2 weekends   | Assistant (Claude first): read tools over plans, forecasts, tasks, notes; "what if" over scenarios; plan drafting from text as proposal; eval harness in CI; token/cost log; MoonShine MCP server               | J3      |
| 5     | **Zoom out**                    | 2 weekends   | Semantic-zoom timeline: quarter / year / 5·10·25 years / lifetime; artifacts and horizons from Obsidian; plans and forecasts on the same axis                                                                   | J1      |
| 6     | **Act**                         | 2–3 weekends | Commands through adapters (OmniFocus create/complete/defer/plan; Obsidian note create/append; publish active scenario to the budget note) with confirm + undo; assistant can apply proposals                    | J4      |
| 7     | **Own** _(gated)_               | —            | Native tasks and markdown notes module (Obsidian-compatible folder), iOS app, sync (ADR on CRDT vs own server)                                                                                                  | —       |
| 8     | **Share** _(gated by audience)_ | —            | Accounts, own backend + AI proxy, App Store, pricing                                                                                                                                                            | —       |

## Why Plan before Ask

The planning engine is the part that helps plans actually get done, and it is MoonShine-native (no provider limits). The assistant is far more useful once it can reason over plans and scenarios ("what if violin goes to max?"). Measurement showcase comes from the engine's tests (seeded simulations, property tests) as well as from later evals.

## Gates for 7–8 (from the owner's own rules)

- Phase 7: daily driver for ≥ 2 months **and** a concrete OmniFocus/Obsidian limitation blocks me.
- Phase 8: ≥ 50 people outside my circle asked for it (blog/GitHub), **and** at least one said "I'd pay" — then name a price immediately.

## Showcase checkpoints

- After phase 1: public repo, README with GIF, ADRs, method log → Profile README, CV keywords.
- After phase 2: forecasting engine with seeded/property tests, drift chart → applications (A.Team etc.).
- After phase 3: blog post "Planning 15 lines of life with min/normal/max effort and Monte Carlo" (Sci-Social pillar candidate).
- After phase 4: evals in CI, `METHOD.md` with real numbers, MCP server.
