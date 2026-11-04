# Method log

One row per PR / agent session. Honest numbers only; `n/a` when unknown. This index and its monthly files feed `METHOD.md` (written after phase 4 from real data only — small sample stated explicitly).

**For an outside reader**

- A row is one pull request (or one agent session without a PR): what was built, by which agents, how big it was, what review found and what it cost. A row is appended by its PR and completed during that PR's review rounds (the review cells are filled in); once the PR has merged, its row is not rewritten, and a later correction is a new sentence or a new row. Prettier re-pads a month's table, so a diff of that file can show more lines than changed.
- **Plain** and **risky** are the two classes of slice. A risky slice reads data from outside the repository, changes what is stored, adds a command, starts a process, or touches concurrency, permissions or the assistant; it has a lower size limit and always waits for the owner's OK on its plan. The rule and the limits are in [`CLAUDE.md`](../../CLAUDE.md), rule 2.
- **Size factor:** plans estimate production lines; the estimate is multiplied by the measured ratio of actual to estimated lines over recent slices before it is checked against the limit. How it is measured, and its current value, are in [`forecast.md`](forecast.md).
- **Review rounds:** every PR gets a full review in a fresh session; another round runs only after a confirmed High finding, at most three rounds (`CLAUDE.md` → "Pull requests").
- `n/a` means the number was not measured. Real data never appears here: only counts, timings and shapes.

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

**Review rules** (owner)

- One review rule for every PR, docs-only included: see `CLAUDE.md` → "Pull requests" (2026-10-03, PR #8).

**Months**

Rows live in one file per month, each with the same table header. A new row goes into the current month's file (`docs/method/log/YYYY-MM.md`; start it with the header when the month has none yet).

- [2026-09](log/2026-09.md)
- [2026-10](log/2026-10.md)
- [2026-11](log/2026-11.md)
