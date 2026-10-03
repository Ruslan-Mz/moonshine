# CLAUDE.md — MoonShine

MoonShine (working name) is a macOS-first app to **see, ask about and eventually run** all of the owner's tasks, projects and goals — from today to a lifetime horizon — on top of swappable tools (OmniFocus, Obsidian, Claude, Excel today). Read in this order: `docs/VISION.md` → `docs/ROADMAP.md` → `docs/ARCHITECTURE.md` → `docs/adr/` → the current spec in `docs/specs/`.

It is also a **public showcase** of agent-driven engineering with measurements: how it is built matters as much as what is built.

## Current phase

See `docs/ROADMAP.md`. **Only build what the current phase's spec asks for.** Later phases shape the architecture (ports, ids, commands) but are not implemented early. If you see a shortcut that would block a later phase, raise it in the PR; if you see a feature from a later phase, don't build it.

## Hard rules

1. **Spec first.** Every change starts from `docs/specs/`. Missing/ambiguous spec → propose a spec change and stop.
2. **One slice = one PR**, < ~400 changed lines of production code (tests, fixtures and generated files excluded).
3. **Ports & adapters (ADR-0001).** `MoonShineCore` imports no AppKit/SwiftUI/OSAKit/GRDB. UI talks to view models/services, never to adapters.
4. **Tests first in Core.** New domain logic → failing test → code.
5. **Privacy.** Raw content — titles, labels, values, names, ids — from the vault (`~/ObsidianV`), OmniFocus, calendars, `data/`, `snapshots/` and `*.local.*` is never committed or pasted into PRs, commits or logs. Aggregates (counts, timings, orders of magnitude) and structure descriptions (shapes, field names, layouts) are allowed, as in `docs/discovery/` since phase 0. Fixtures are invented.
6. **No writes to external tools before phase 6.** No writes to the vault or OmniFocus anywhere in code until the phase-6 spec exists.
7. **Dependencies:** ask first. Pre-approved: `GRDB` (store), `Yams` (YAML), `CoreXLSX` (phase 2), official MCP Swift SDK (phase 4). Check licence compatibility with AGPL-3.0.
8. **UI tone is a requirement:** no red and no "failed/overdue/behind" wording for intentions or lines; drift and quiet lines are facts with a suggested next step; paused lines are "paused on purpose". Urgent colour only for tasks with a real `due` date. "Hours" only next to real time data or the vault budget (ADR-0006).
9. **UX bar:** keyboard-first on Mac (every view reachable by shortcut, ⌘K command palette from phase 1), dense but calm layout, instant view switching (reads come from the local store).
10. **Log the method:** append a row to `docs/method/log.md` at the end of each PR. Honest numbers; `n/a` if unknown. Before appending, run `npx ccusage@latest session --json`, take this session's tokens (input / output / cache write / cache read, separately) and its API-equivalent cost, and put them in the Tokens / cost column marked "API-equiv" (e.g. `session <id>: input … · output … · cache write … · cache read …; API-equiv $…`).

## Git

Start every slice with `git fetch && git switch main && git pull --ff-only`, then branch.

## Pull requests

- **Before opening a PR**, check that:
  - errors carry no raw values (no titles, ids, dates, payload text or stderr from a provider);
  - every decoded field is validated, on every path that decodes it;
  - numeric arguments are bounds-checked (zero, negative, very large);
  - every number in a document is derivable from its canonical source;
  - every link and ADR reference resolves;
  - a size overrun is stated in the PR and in the method-log row.
- **Review**: the owner runs `/review-pr <n>` in a **new** session (`.claude/skills/review-pr/`). The session that wrote the PR never reviews it.
- **After a review is posted**, the author session reads it from the PR itself (`gh pr view <n> --comments` and the review threads), fixes the `author` findings, replies to each thread, and asks the owner only about the `owner` findings. The owner does not copy review text between sessions.
- **Rounds**: a new round only if the previous round had a confirmed High. From round 2 on, only High findings are fixed; the rest are listed in the PR as deferred.

## Definition of done

Tests green · `swift format lint` clean · `prettier --check '**/*.md'` clean · app builds · spec checkboxes ticked · method-log row · ADR if a costly-to-reverse choice was made · screenshots only in Demo mode.

## Commands

- Core tests (any OS): `swift test --package-path MoonShineCore`
- Adapter tests: `swift test --package-path Adapters`
- Generate Xcode project: `xcodegen generate`
- Build app: `xcodebuild -scheme MoonShineMac -destination 'platform=macOS' build`
- Lint: `swift format lint --recursive MoonShineCore Adapters Apps`
- Markdown: `npm install` once, then `npx prettier --write '**/*.md'` · check: `npx prettier --check '**/*.md'`

## Owner

Senior mobile/full-stack engineer, native iOS since 2008. He directs and reviews; agents write the code. Plan before coding and wait for his OK on each slice plan. Prefer clarity over cleverness; explicit types at module boundaries; no abstraction beyond the ports in ARCHITECTURE.md without an ADR.
