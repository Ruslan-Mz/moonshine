# Phase 0 — Discover (one evening)

**Goal:** learn the real shape of the owner's OmniFocus and Obsidian data before writing app code, using Claude Code + an OmniFocus MCP server. Output becomes the snapshot contract, synthetic fixtures and the line mapping. Bonus: a weekly-review prompt usable immediately.

## Setup (owner, on the Mac)
- [x] OmniFocus 4.7+ running; Node 18+.
- [x] Clone `kip-d/omnifocus-mcp`, `npm install && npm run build`.
- [x] `claude mcp add omnifocus -- node /ABS/PATH/omnifocus-mcp/dist/index.js`
- [x] Allow the macOS Automation permission.

## Questions (agent; read-only tools only)
OmniFocus:
- [x] Folders/projects/tags: counts, hierarchy depth.
- [x] Line tags (`violin`, `аспирантура`, …) vs meta tags (`Тип работы : …`, `Контекст : …`, `Время : …`, `Энергия : …`, `Цикл : …`).
- [x] Completions per line tag and per top-level folder per ISO week, last 12 weeks. *(Partly: 12-week totals per line tag and per folder, plus weekly totals overall; the per-folder × per-week grid is computed by the phase-1 bridge.)*
- [x] Field availability: `estimatedMinutes`, `plannedDate`, `deferDate`, `dueDate`, repeat rules, notes length.
- [x] Active tasks mapping to no line (count + anonymised examples).
- [x] How repeating-task completions are represented.
- [x] Latency of a full read (active + 12 weeks of completed).

Obsidian (`~/ObsidianV`, read-only file access):
- [x] Frontmatter keys in use across `00_Стратегия/`, `journal/`, `projects/` (counts per key, value types).
- [x] Notes that represent horizons/artifacts: year artifacts, quarter focus, month plans, long horizons — how they are identified (`type`, filename pattern).
- [ ] Structure of the hours tracker Excel if found in the vault or pointed to by the owner (sheet names, columns — no values). — **open:** not in the vault; owner to point to the file (carried into phase 3, Excel import).

## Deliverables
- [x] `docs/discovery/data-report.md` — **aggregates only**; no task/project/note titles.
- [x] `docs/discovery/snapshot-contract.md` — JSON contract for the OmniFocus adapter.
- [x] `docs/discovery/vault-contract.md` — frontmatter contract: `lines:` block in the budget note; artifact/horizon notes (`type`, `scale` — renamed from `horizon`, decision Q1 —, `period`, `parent`, `line`).
- [x] `fixtures/omnifocus.snapshot.json` — synthetic: ~8 lines, ~150 tasks, 12 weeks of completions; a paused line, a quiet line, a repeating habit, untagged tasks, a few real `due` dates.
- [x] `fixtures/vault/` — synthetic notes: budget note with `lines:`, 2026 artifacts, a quarter focus, a month plan, a long-horizons note.
- [x] `data/mapping.local.yaml` (git-ignored) — real line mapping draft for the owner to paste into his vault.
- [x] Method-log row.

## Out of scope
Swift code; any writes.
