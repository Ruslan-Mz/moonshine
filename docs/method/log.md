# Method log

One row per PR / agent session. Honest numbers only; `n/a` when unknown. This file feeds `METHOD.md` (written after phase 4 from real data only — small sample stated explicitly).

**Columns**

- **Slice** — phase + slice id (P0, P1-S1, P1-S2…)
- **Agent** — model / tool (e.g. Claude Code + model name, subagent type)
- **Prompts** — number of owner prompts in the session
- **Δ lines** — changed lines excluding fixtures
- **Accepted as-is** — yes / partly / no
- **Review findings** — classes of issues caught by the owner (e.g. `privacy`, `wrong-API`, `over-abstraction`, `tone`, `test-gap`, `hallucinated-property`)
- **Owner time** — minutes spent directing + reviewing
- **Wall time** — minutes from first prompt to merge
- **Tokens / cost** — if available from `/cost` or usage

| Date       | Slice | Agent                                                              | Prompts | Δ lines                                                             | Accepted as-is | Review findings                                                                                                                                                                                                  | Owner time | Wall time                                                  | Tokens / cost                                                                                                  | Notes                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------- | ----- | ------------------------------------------------------------------ | ------- | ------------------------------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-09-30 | P0    | Claude Code (Opus 5.5) + Explore subagent (MCP server source read) | 4       | 437 (commit 1b1411f, excl. fixtures; over the ~400 guide, all docs) | partly         | owner decisions on open questions (O1 rhythm/progress split, Q1 `scale` key, Life ops bucket); latency target revised (< 5 s blocking → ≤ 20 s background + incremental); config scope (repo-only settings.json) | 1h         | ~125 min (08:44→10:49 UTC, from file mtimes + commit time) | session d94d16df: 17.33M total (input 182, output 95.6k, cache write 568k, cache read 16.67M); API-equiv $9.57 | Session 1: vault half; OmniFocus MCP not connected (registered only in `.vscode/mcp.json`). Session 2: OmniFocus half via `omnifocus_read` only, ~75 read calls, mostly `countOnly`; server halves pages to 125 rows and mis-serialises repeat enums; full-scan count ≈ 8 s. Fixtures from a seeded generator (not committed). Open: hours-tracker xlsx location. * Omnifocus MCP diagnosis was wrong, it was available. |
