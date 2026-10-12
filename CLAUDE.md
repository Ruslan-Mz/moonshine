# CLAUDE.md — MoonShine

MoonShine (working name) is a macOS-first app to **see, ask about and eventually run** all of the owner's tasks, projects and goals — from today to a lifetime horizon — on top of swappable tools (OmniFocus, Obsidian, Claude, Excel today). Read in this order: `docs/VISION.md` → `docs/ROADMAP.md` → `docs/ARCHITECTURE.md` → `docs/adr/` → the current spec in `docs/specs/`.

It is also a **public showcase** of agent-driven engineering with measurements: how it is built matters as much as what is built.

## Current phase

See `docs/ROADMAP.md`. **Only build what the current phase's spec asks for.** Later phases shape the architecture (ports, ids, commands) but are not implemented early. If you see a shortcut that would block a later phase, raise it in the PR; if you see a feature from a later phase, don't build it.

## Hard rules

1. **Spec first.** Every change starts from `docs/specs/`. Missing/ambiguous spec → propose a spec change and stop.
2. **One slice = one PR**, sized by risk (owner, 2026-10-09). Sizes are changed lines of production code after the size factor of `docs/method/forecast.md` ("Sizing a slice"; tests, fixtures and generated files excluded).
   - **Risky slice**: it parses data from outside the repository (vault, OmniFocus, calendars, workbook), changes what is stored or deleted, adds a command, starts a process, or touches concurrency, sync, permissions or the assistant. Limit about 400; above it, split in the plan. `deep` review is proposed as before (`/review-pr` §2).
   - **Plain slice**: everything else: SwiftUI views, view models and navigation over data the store already holds, layout, localisation, settings that add no storage rule. Limit about 800; one screen, or a group of related screens, is one PR.
   - A slice with any risky part is risky. Prefer moving the risky part into its own PR first, so the rest can be plain. The plan names its class and the reason.
   - Reason: the High findings so far came from risky slices of 200–400 lines (parser expansion, read-boundary bypass); in plain slices the fixed cost of each PR (plan, review, merge) dominates.
3. **Ports & adapters (ADR-0001).** `MoonShineCore` imports no AppKit (nor Cocoa, Carbon, Quartz)/SwiftUI/SwiftUICore/OSAKit/GRDB/EventKit/Yams (`scripts/check-core-imports.sh` in CI). UI talks to view models/services, never to adapters.
4. **Tests first in Core.** New domain logic → failing test → code.
5. **Privacy.** Raw content — titles, labels, values, names, ids — from the vault (`~/ObsidianV`), OmniFocus, calendars (events: no real titles, attendees or calendar names), `data/`, `snapshots/` and `*.local.*` is never committed or pasted into PRs, commits or logs. Aggregates (counts, timings, orders of magnitude) and structure descriptions (shapes, field names, layouts) are allowed, as in `docs/discovery/` since phase 0. Fixtures are invented.

   **Code a test runs** — the test itself and the production code it calls — may open only `fixtures/`, a temporary folder and files tracked in the repository, and may start only system tools named in the test (`/bin/sh`, `osacompile`). It never opens `data/`, `deny-list.txt`, `snapshots/`, `*.local.*`, the home folder or the vault, and never calls a live OmniFocus or EventKit.

6. **No writes to external tools before their phase:** the vault from the Write phase (ADR-0015), OmniFocus and calendars from the Act phase. No such code until that phase's spec exists.
7. **Dependencies:** ask first. Pre-approved: `GRDB` (store), `Yams` (YAML), `CoreXLSX` (phase 2), official MCP Swift SDK (phase 4); EventKit is a pre-approved system framework (ADR-0012). Check licence compatibility with AGPL-3.0.
8. **UI tone is a requirement:** no red and no "failed/overdue/behind" wording for intentions or lines; drift and quiet lines are facts with a suggested next step; paused lines are "paused on purpose". Urgent colour only for tasks with a real `due` date. "Hours" only next to real time data or numbers the owner set himself: the vault values `budget_h_week`, `floor_h_day` and `portion_h_day`, and the length of events in a line's calendar (the day portion of ADR-0016; owner, 2026-10-08) (ADR-0006).
9. **UX bar:** keyboard-first on Mac (every view reachable by shortcut, ⌘K command palette from phase 1), dense but calm layout, instant view switching (reads come from the local store).
10. **Log the method:** append a row to `docs/method/log.md` at the end of each PR. Honest numbers; `n/a` if unknown. The Tokens / cost column takes the subagents' reported token totals (when any ran); the session's cost is what the owner pastes from `/cost`, otherwise `n/a`.

## Git

Start every slice with the HTTPS fetch, then `git switch main && git merge --ff-only origin/main`, then branch. The fetch uses `gh` as a one-off credential helper and is allowed without a prompt: `git -c credential.helper= -c credential.helper='!gh auth git-credential' fetch https://github.com/Ruslan-Mz/moonshine.git '+refs/heads/*:refs/remotes/origin/*'`. Plain `git fetch` goes over SSH, which fails from sessions.

## Plans

- A slice plan is written to a file in the session scratchpad and printed in full in chat. Every claim it makes about existing code names its file, and the line where it matters: the critic has no search, so a claim without a path is a finding (`unverifiable-claim`).
- **Critic, on trial** (owner, 2026-10-10; criteria and results in `docs/method/calibration/plan-critic-trial.md`): after printing the plan, run `plan-critic` (`.claude/agents/plan-critic.md`) on it once, with the file path and the slice name, nothing else, and print its report verbatim, after the plan.
- Do not change the plan in response to the critic yet. Wait for the owner's decisions, then fix the plan and continue.
- One critic run per plan. No critic for a docs-only change, or for a plain slice (rule 2) under about 80 lines after the size factor (estimate × factor < 80).
- Every plan waits for the owner's OK. The architect reviews plans during the trial; the critic's S3b-2 calibration did not pass (2026-10-10).

## Pull requests

- **Sizing a slice**: when planning a slice, multiply your own estimate of production lines by the size factor in `docs/method/forecast.md` (the median of actual / estimated production lines over the last five merged code slices; each code slice's PR updates it), and say so in the plan; with no factor there, double it. If the result exceeds the limit of the slice's class (rule 2), split the slice in the plan, before coding. Reason: estimates have run low on every measured slice; the ratios are in the table in `docs/method/forecast.md`.
- **Before opening a PR**, check that:
  - errors carry no raw values (no titles, ids, dates, payload text or stderr from a provider);
  - every decoded field is validated, on every path that decodes it;
  - numeric arguments are bounds-checked (zero, negative, very large);
  - every number in a document is derivable from its canonical source;
  - every link and ADR reference resolves;
  - a size overrun is stated in the PR and in the method-log row.
- **Review**: the owner runs `/review-pr <n>` in a **new** session (`.claude/skills/review-pr/`). The session that wrote the PR never reviews it.
- **After a review is posted**, the author session reads it from the PR itself (`gh pr view <n> --comments`), fixes the `author` findings, answers with **one** PR comment that lists every finding and what was done with it, and asks the owner only about the `owner` findings. No reply per thread: everything that sends data to GitHub asks the owner, so one comment is one prompt instead of one per thread (owner, 2026-10-08). The owner does not copy review text between sessions.
- **Rounds** — one rule for every PR, docs-only included: round 1 is a full `/review-pr`. If round N had a confirmed High, run round N+1 after the fixes, on the changes since round N. Otherwise no further round. From round 2 on only High findings must be fixed, the rest are listed in the PR as deferred; at most three rounds, then the owner decides.

## Definition of done

Tests green · `swift format lint` clean · Prettier check clean · `node scripts/check-refs.mjs` clean · app builds · spec checkboxes ticked · method-log row · ADR if a costly-to-reverse choice was made · screenshots only in Demo mode.

## Commands

- Core tests (any OS): `swift test --package-path MoonShineCore`
- Adapter tests: `swift test --package-path Adapters`
- Generate Xcode project: `xcodegen generate`
- Build app: `xcodebuild -scheme MoonShineMac -destination 'platform=macOS' build`
- Lint: `swift format lint --recursive MoonShineCore Adapters Apps`
- Markdown: `npm install` once, then `git ls-files -z '*.md' | xargs -0 node_modules/.bin/prettier --write` · check: `git ls-files -z '*.md' | xargs -0 node_modules/.bin/prettier --check`. Never `npx`: it can download a package when `node_modules` is missing. The local binary runs inside the sandbox, and `git ls-files` skips the unreadable `data/` folder (owner, 2026-10-08). CI keeps `npx`, after `npm ci`.
- References: `node scripts/check-refs.mjs` · its tests: `node --test scripts/check-refs.test.mjs`
- Vault-write check (no vault writes before the Write phase): `node scripts/check-vault-writes.mjs` · its tests: `node --test scripts/check-vault-writes.test.mjs`
- Core import check: `scripts/check-core-imports.sh` · its tests: `node --test scripts/check-core-imports.test.mjs`
- Read-boundary hook tests: `python3 -m unittest discover -s .claude/hooks -p 'test_*.py'`
- Local sandbox (read barrier, git-ignored): copy `.claude/settings.local.example.json` to `settings.local.json` next to it and fill in the placeholders; `/review-pr` stops without it. `~/.gitconfig` and `~/.config/git/ignore` are allowed for git, `~/.nvm/versions/node` for node; `env.PATH` puts the system folders first and lists only folders the sandbox can read (node stops at the first unreadable one and cannot start git or bash). Probes and throwaway files go under the session scratchpad and are read there; the read-boundary hook (`.claude/hooks/read-boundary.py`) denies the Read tool everything outside this session's folders, including the shared `$TMPDIR`. It does not guard names inside the repository: real data in the repository is protected from the built-in tools by rule 5 and `.gitignore` only, until S4 moves it out (`docs/specs/phase-1-see.md` → S4).

## Owner

Senior mobile/full-stack engineer, native iOS since 2008. He directs and reviews; agents write the code. Plan before coding and wait for his OK on each slice plan. Prefer clarity over cleverness; explicit types at module boundaries; no abstraction beyond the ports in ARCHITECTURE.md without an ADR.
