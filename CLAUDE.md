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

## Asking the owner

Owner, 2026-10-17: fewer approval prompts, nothing less safe. Ask the owner only for:

- (a) **owner decisions** as this file defines them: the spec, a contract, the scope, behaviour (the `owner` class of a review finding);
- (b) anything **irreversible or outside the repository** beyond the list below: merging, closing, deleting a remote branch, pushing to `main`, repository settings, writes to external tools (rule 6), new dependencies (rule 7);
- (c) **live runs on real data** (the vault, OmniFocus, calendars, `data/`).

Everything else: do it and report it. Pushing a slice branch, opening or editing its PR, posting a review and posting the one answer comment to a review no longer need the owner. This replaces the rule of 2026-10-08 that everything sent to GitHub asks the owner. What may be sent is unchanged: rule 5 holds for every push, PR text and comment. Both ways out are guarded by an owner-installed copy outside the checkout (Commands → "Guard"):

- **Pushes** go through the pre-push hook: one branch per push, never `main`, no tags, no deletion, no rewrite of a branch other than the one HEAD is on, and no deny-list line or vault path in ref names or pushed commits.
- **Posts** (PR create and edit, a PR comment, a review) go through `gh-post` only, called by its absolute path (`/Users/<you>/.config/moonshine/bin/gh-post`; it is not on `PATH`, and the settings match only that form): it sends a file from the session scratchpad after scanning it, and the title and branch name, the same way. The local settings allow `gh-post` and deny every other way to write to GitHub with `gh` (`gh pr create|edit|comment|review|new|ready|reopen`, `gh issue`, `gh gist`, `gh release`, `gh api` with a body, a field or a file), and the rest of (b) (`.claude/settings.local.example.json`).

## Git

Start every slice with `git fetch origin`, then `git switch main && git merge --ff-only origin/main`, then branch with `git switch -c <branch> --no-track origin/main`: tracking would write `.git/config`, which the sandbox protects (owner, 2026-10-20). `origin` is `https://github.com/Ruslan-Mz/moonshine.git` with the repository-local credential helper `!gh auth git-credential`, and its fetch refspecs bring `origin/main` and every PR head as `origin/pr/<n>` (owner, 2026-10-19). The fetch is always `git fetch origin` with no arguments: a refspec on the command line can name any destination (`+main:main` overwrites local `main` and passes every glob deny rule), so a fetch with arguments is never allowed and always prompts. Push always naming the branch: `git push origin HEAD:refs/heads/<branch>`. A branch name containing `main` is denied by the local settings; choose another name. Reason: the earlier long form (`git -c credential.helper=… fetch https://…`) matched neither the allow rules nor `sandbox.excludedCommands`, ran in the sandbox, failed and prompted on every retry.

Never chain an unsandboxed command (`git fetch origin`, `git push origin`, `gh`, `gh-post`, `swift`) with anything via `;`, `|` or `&&`: run it alone in its own call, then the rest separately. A chained line leaves the sandbox as a whole and prompts (owner, 2026-10-17). Never set `dangerouslyDisableSandbox` for `swift test` / `swift build`: they are in `sandbox.excludedCommands` and already run outside the sandbox, and the flag hits the owner's ask rule and prompts every time. If a `swift` command fails in the sandbox without it, stop and report the error instead of retrying with the flag (owner, 2026-10-19).

## Plans

- A slice plan is written to a file in the session scratchpad and printed in full in chat. Every claim it makes about existing code names its file, and the line where it matters: the critic has no search, so a claim without a path is a finding (`unverifiable-claim`).
- **Critic** (permanent step since the owner's decision of 2026-10-17: the trial passed 2 of 2; `docs/method/calibration/plan-critic-trial.md`): after printing the plan, run `plan-critic` (`.claude/agents/plan-critic.md`) on it once, with the file path and the slice name, nothing else, and print its report verbatim, after the plan.
- One critic run per plan. No critic for a docs-only change, or for a plain slice (rule 2) under about 80 lines after the size factor (estimate × factor < 80).
- **What waits.** The owner sees the plan and the critic's "For the owner" list; the architect no longer reviews every plan.
  - A **risky** plan always waits for the owner's OK (owner, 2026-10-09; confirmed 2026-10-17), whatever the verdict and even with an empty "For the owner" list. Then fix the plan, including the critic's "For the author" findings, and start.
  - A **plain** plan whose critic verdict is `ready` and which has no question for the owner (an empty "For the owner" list and none of its own) starts at once; fix the "For the author" findings first. Any other verdict, or any owner question, waits for the owner's answers.
  - A **plain** plan whose verdict is `fix the plan first` with author findings only counts as `ready` once every finding is taken into the plan (fixed, or declined with a reason in the PR description); with an empty "For the owner" list it starts without waiting (owner, 2026-10-19). A risky plan still always waits.
  - A plan with no critic run (docs-only, or plain under 80) waits for the owner's OK, as before.

## Pull requests

- **Sizing a slice**: when planning a slice, multiply your own estimate of production lines by the size factor in `docs/method/forecast.md` (the median of actual / estimated production lines over the last five merged code slices; each code slice's PR updates it), and say so in the plan; with no factor there, double it. If the result exceeds the limit of the slice's class (rule 2), split the slice in the plan, before coding. The limit applies to the head that goes to review; review fixes may take a PR over it without a split (owner, 2026-10-14). Reason: estimates have run low on every measured slice; the ratios are in the table in `docs/method/forecast.md`.
- **Before opening a PR**, check that:
  - errors carry no raw values (no titles, ids, dates, payload text or stderr from a provider);
  - every decoded field is validated, on every path that decodes it;
  - numeric arguments are bounds-checked (zero, negative, very large);
  - every number in a document is derivable from its canonical source;
  - every link and ADR reference resolves;
  - a size overrun is stated in the PR and in the method-log row.
- **Review**: the owner runs `/review-pr <n>` in a **new** session (`.claude/skills/review-pr/`). The session that wrote the PR never reviews it.
- **After a review is posted**, the author session reads it from the PR itself (`gh pr view <n> --comments`), fixes the `author` findings, answers with **one** PR comment that lists every finding and what was done with it, and asks the owner only about the `owner` findings. It pushes the fixes and posts the comment with `gh-post comment`, by its absolute path, without asking ("Asking the owner"). No reply per thread: one comment keeps the answer in one place (owner, 2026-10-08). The owner does not copy review text between sessions.
- **Rounds** — one rule for every PR, docs-only included: round 1 is a full `/review-pr`. If round N had a confirmed High, run round N+1 after the fixes, on the changes since round N. Otherwise no further round. From round 2 on only High findings must be fixed, the rest are listed in the PR as deferred; at most three rounds, then the owner decides.

## Definition of done

Tests green · `swift format lint` clean · Prettier check clean · `node scripts/check-refs.mjs` clean · app builds · spec checkboxes ticked · method-log row · ADR if a costly-to-reverse choice was made · screenshots only in Demo mode.

## Commands

- Swift version: CI pins the oldest supported compiler, **Swift 6.3** (the newest Xcode on the `macos-latest` image; `SWIFT_VERSION` in `.github/workflows/ci.yml`, which fails without a matching Xcode). The local toolchain may be newer (owner, 2026-10-17). The code must build with the Swift version CI pins; do not use features of a newer version; CI decides. `swift-tools-version` in every `Package.swift` stays at or below the pin. Raise the pin when GitHub ships an image with Xcode 27.
- **Clone setup** (the owner, once per clone, from the repository root; CLAUDE.md § Git and `/review-pr` depend on it): `git remote set-url origin https://github.com/Ruslan-Mz/moonshine.git` · `git config --local --add credential.https://github.com.helper ''` · `git config --local --add credential.https://github.com.helper '!gh auth git-credential'` (the empty value clears helpers from the global config, such as the keychain) · `git config --local --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'`. Then `git fetch origin` brings `origin/main` and every PR head as `origin/pr/<n>`.
- Core tests (any OS): `swift test --package-path MoonShineCore`
- Adapter tests: `swift test --package-path Adapters`
- Generate Xcode project: `xcodegen generate`, then `scripts/pin-app-packages.sh` (copies `Adapters/Package.resolved` into the generated project, which is not committed). XcodeGen: `brew install xcodegen` locally; CI downloads the pinned release and checks its SHA-256 (owner, 2026-10-20).
- Build and test app: `xcodebuild -scheme MoonShineMac -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile test` (`build` to build only). `xcodegen generate` and `xcodebuild *` run outside the sandbox (`sandbox.excludedCommands`); each runs alone, never chained or piped (owner, 2026-10-20).
- Lint: `swift format lint --recursive MoonShineCore Adapters Apps`
- Markdown: `npm install` once, then `git ls-files -z '*.md' | xargs -0 node_modules/.bin/prettier --write` · check: `git ls-files -z '*.md' | xargs -0 node_modules/.bin/prettier --check`. Never `npx`: it can download a package when `node_modules` is missing. The local binary runs inside the sandbox, and `git ls-files` skips the unreadable `data/` folder (owner, 2026-10-08). CI keeps `npx`, after `npm ci`.
- References: `node scripts/check-refs.mjs` · its tests: `node --test scripts/check-refs.test.mjs`
- Vault- and calendar-write check (no vault writes before the Write phase, no calendar writes before the Act phase): `node scripts/check-vault-writes.mjs` · its tests: `node --test scripts/check-vault-writes.test.mjs`
- Core import check: `scripts/check-core-imports.sh` · its tests: `node --test scripts/check-core-imports.test.mjs`
- Read-boundary hook tests: `python3 -m unittest discover -s .claude/hooks -p 'test_*.py'`
- **Guard** (pre-push hook and `gh-post`; `scripts/guard/`). The owner installs it from the repository root, once per clone, and again after a change to `scripts/guard/` is merged, from an up-to-date `main`, never from a branch (a branch's guard is unreviewed): `scripts/install-guard.sh`, plus once `git config moonshine.denyList <absolute path of the deny-list>`. The script copies the three guard scripts (`matcher.mjs`, `pre-push.mjs`, `gh-post.mjs`) to `~/.config/moonshine/guard/`, with a `config.json` naming the scratchpad root, writes `~/.config/moonshine/hooks/pre-push` and `~/.config/moonshine/bin/gh-post`, and sets `core.hooksPath` to the absolute hook folder, so a checkout without the guard, or with an edited one, runs the installed copy. When the checkout's copy differs, the hook warns (reinstall after the merge, from `main`); it does not block. One install serves one clone: a second clone's install replaces the first's scratchpad root.
  - The hook blocks a push that updates more than one ref, targets anything outside `refs/heads/`, targets `main`, deletes a ref, or is a non-fast-forward update of a branch other than the one HEAD is on; and one whose ref names or pushed commits (messages, file names, added lines) carry a deny-list line (substring, case ignored, blank lines skipped) or a vault path (case ignored; `\/` and `%2F` count as `/`; `obsidian://` links that name a file).
  - `gh-post comment <pr> <file>`, `review <pr> <file>`, `pr-create <title> <file>`, `pr-edit <pr> <file> [<title>]`: the file must resolve, after symlinks, inside a session scratchpad of this project (`/private/tmp/claude-<uid>/<project>/<session>/scratchpad/`); its text (every decoded string of a review JSON too), the title and the branch name are scanned like the hook's lines; gh gets the scanned bytes on stdin.
  - Both name what matched by kind, and by commit, file and line, never the matched text. A missing setting, an unreadable or empty deny-list, or no `node` blocks. Both read the deny-list outside the sandbox (`sandbox.excludedCommands`). Still open: removing `core.hooksPath` or pushing with `--no-verify` skips the hook; the settings deny every push option starting `--no` (git accepts abbreviations such as `--no-veri`) and every git command naming `hooksPath`, but nothing outside the permission rules guards the config. When S4 moves the deny-list out of the repository, only `moonshine.denyList` changes. Tests: `node --test scripts/pre-push.test.mjs scripts/gh-post.test.mjs`.
- Local sandbox (read barrier, git-ignored): copy `.claude/settings.local.example.json` to `settings.local.json` next to it and fill in the placeholders; `/review-pr` stops without it. `~/.gitconfig` and `~/.config/git/ignore` are allowed for git, `~/.nvm/versions/node` for node; `env.PATH` puts the system folders first and lists only folders the sandbox can read (node stops at the first unreadable one and cannot start git or bash). Probes and throwaway files go under the session scratchpad and are read there; the read-boundary hook (`.claude/hooks/read-boundary.py`) denies the Read tool everything outside this session's folders, including the shared `$TMPDIR`. It does not guard names inside the repository: real data in the repository is protected from the built-in tools by rule 5 and `.gitignore` only, until S4 moves it out (`docs/specs/phase-1-see.md` → S4).

## Owner

Senior mobile/full-stack engineer, native iOS since 2008. He directs and reviews; agents write the code. Plan before coding; which plans wait for his OK is in "Plans". Prefer clarity over cleverness; explicit types at module boundaries; no abstraction beyond the ports in ARCHITECTURE.md without an ADR.
