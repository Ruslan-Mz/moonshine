# Phase 0 — Discover (one evening)

**Goal:** learn the real shape of the owner's OmniFocus and Obsidian data before writing app code, using Claude Code + an OmniFocus MCP server. Output becomes the snapshot contract, synthetic fixtures and the line mapping. Bonus: a weekly-review prompt usable immediately.

## Setup (owner, on the Mac)
- [ ] OmniFocus 4.7+ running; Node 18+.
- [ ] Clone `kip-d/omnifocus-mcp`, `npm install && npm run build`.
- [ ] `claude mcp add omnifocus -- node /ABS/PATH/omnifocus-mcp/dist/index.js`
- [ ] Allow the macOS Automation permission.

## Questions (agent; read-only tools only)
OmniFocus:
- [ ] Folders/projects/tags: counts, hierarchy depth.
- [ ] Line tags (`violin`, `аспирантура`, …) vs meta tags (`Тип работы : …`, `Контекст : …`, `Время : …`, `Энергия : …`, `Цикл : …`).
- [ ] Completions per line tag and per top-level folder per ISO week, last 12 weeks.
- [ ] Field availability: `estimatedMinutes`, `plannedDate`, `deferDate`, `dueDate`, repeat rules, notes length.
- [ ] Active tasks mapping to no line (count + anonymised examples).
- [ ] How repeating-task completions are represented.
- [ ] Latency of a full read (active + 12 weeks of completed).

Obsidian (`~/ObsidianV`, read-only file access):
- [ ] Frontmatter keys in use across `00_Стратегия/`, `journal/`, `projects/` (counts per key, value types).
- [ ] Notes that represent horizons/artifacts: year artifacts, quarter focus, month plans, long horizons — how they are identified (`type`, filename pattern).
- [ ] Structure of the hours tracker Excel if found in the vault or pointed to by the owner (sheet names, columns — no values).

## Deliverables
- [ ] `docs/discovery/data-report.md` — **aggregates only**; no task/project/note titles.
- [ ] `docs/discovery/snapshot-contract.md` — JSON contract for the OmniFocus adapter.
- [ ] `docs/discovery/vault-contract.md` — frontmatter contract: `lines:` block in the budget note; artifact/horizon notes (`type`, `horizon`, `period`, `parent`, `line`).
- [ ] `fixtures/omnifocus.snapshot.json` — synthetic: ~8 lines, ~150 tasks, 12 weeks of completions; a paused line, a quiet line, a repeating habit, untagged tasks, a few real `due` dates.
- [ ] `fixtures/vault/` — synthetic notes: budget note with `lines:`, 2026 artifacts, a quarter focus, a month plan, a long-horizons note.
- [ ] `data/mapping.local.yaml` (git-ignored) — real line mapping draft for the owner to paste into his vault.
- [ ] Method-log row.

## Out of scope
Swift code; any writes.
