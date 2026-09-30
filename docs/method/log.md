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
