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

| Date | Slice | Agent | Prompts | Δ lines | Accepted as-is | Review findings | Owner time | Wall time | Tokens / cost | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | P0 | Claude Code (Opus 5.5) + Explore subagent (MCP server source read) | 3 | 352 (3 discovery docs + this row) | n/a (awaiting review) | n/a | n/a | n/a | n/a | Session 1: vault half; OmniFocus MCP not connected (registered only in `.vscode/mcp.json`). Session 2 (after `claude mcp add`): OmniFocus half via `omnifocus_read` only — ~75 read calls, mostly `countOnly`; server halves pages to 125 rows and has an enum-serialisation bug; full-scan count ≈ 8 s → ADR-0003 latency target at risk. Fixtures from a seeded generator (not committed). |
