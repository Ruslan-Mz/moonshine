# Weekly review prompt (phase 0, usable before the app exists)

Use in Claude Code / Claude Desktop (before MoonShine exists) with the OmniFocus MCP server connected and the vault note readable.

---

Read the budget note (the one with `moonshine: budget`) in `~/ObsidianV` (frontmatter `lines:` if present, otherwise the table) and my current quarter focus note. Then, using only **read** tools of the OmniFocus MCP server:

1. For each line: completions this week and in each of the previous 7 weeks, days since last completion, number of available next actions.
2. List **quiet lines** (active, no completion ≥ 14 days) — neutral wording, no "failed/behind". Paused lines: mention only that they are paused.
3. List available tasks in active lines with no planned, defer or due date ("Без плана").
4. Count active tasks that map to no line.
5. Suggest at most **3** next actions for the coming week, each tied to a line and its parent artifact. Prefer lowering the bar over adding tasks.

Rules: do not create, edit or complete anything in OmniFocus. Do not treat intentions as deadlines. Answer in Russian, compact, one table + short lists.
