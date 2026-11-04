---
name: review-pr
description: Independent multi-lens review of a MoonShine pull request by Opus reviewers in fresh contexts, followed by an adversarial verification pass and inline PR comments. Use when the owner asks to review a pull request, for example "/review-pr 7" or "review PR 7". Never run it in the session that wrote the PR's code.
disable-model-invocation: true
argument-hint: "<pr-number> [standard|deep] [local] [since <sha>] [at <sha>]"
model: opus
---

# Review a pull request

The author of a change cannot review it well: it reads what it meant, not what it wrote. This skill gives every PR reviewers that start from nothing, each looking through one lens, and a verifier that tries to prove them wrong.

## 0. Preconditions

- **Fresh session.** If this session wrote or edited code in the PR, stop and tell the owner to run the skill in a new session.
- **Read barrier on.** Before starting any reviewer, run `ls ~ | head -1` in the sandbox (not unsandboxed). It must print `Operation not permitted`; a folder name means the sandbox's read barrier is off — it lives in the git-ignored local settings file (`settings.local.json` next to `settings.json`, key `sandbox.filesystem.denyRead`) — so stop and tell the owner (`ls -d` is no test: it reads only metadata, which the barrier allows). The barrier's entries are in `.claude/settings.local.example.json`.
- **Read hook on.** Then call the Read tool on `~/.CFUserTextEncoding`. The read-boundary hook (`.claude/hooks/read-boundary.py`) must deny it. If the read is allowed, the hook is not running: stop and tell the owner. Never print or quote what the read returned.
- Arguments: `$ARGUMENTS`. The PR number comes first. If none is given, use the PR of the current branch (`gh pr view --json number`).
- The owner may add: `standard` or `deep` (the mode, see §2; default `standard`), `local` (do not post to GitHub, report here only), `since <sha>` (review only what changed after that commit) or `at <sha>` (review the PR as it was at that commit: the worktree is created from that commit and diffed against the base; always `local`).
- You orchestrate. You do not review the code yourself and you do not fix anything.

## 1. Prepare

`gh`, the fetch and SwiftPM run outside the Claude sandbox through `sandbox.excludedCommands` in the local settings (`.claude/settings.local.example.json`), and the allow rules there cover every command this skill sends: no prompt, and no `dangerouslyDisableSandbox`. `gh` and the fetch need the network; SwiftPM cannot build or test inside the sandbox at all (its build service cannot write `.build`, with or without `--disable-sandbox`). Code outside the sandbox can read and write beyond it, so reviewers and verifiers never build or run the PR's code when it changes the package's external dependencies (a package added or changed in `Package.swift` or `Package.resolved`), a build plugin or a build script. A target that gains a dependency on a local target of the same package does not count: then they run the tests as usual (PR #14's reviewers skipped `swift test` for exactly that one line).

**Commands.** One command per Bash call: no `;`, `&&` or `||` chains, no heredocs, no inline `python` or `node -e`, no `cd` (use `git -C <path>` and an absolute `--package-path`). A pipe into `tail`, `head` or `grep` is fine, except after `swift`, `gh`, `gh-post`, the fetch or the push: those run alone, because a piped line matches no `sandbox.excludedCommands` entry and runs, and fails, inside the sandbox. A permission rule matches each part of a chain separately, so a chain prompts where its parts would not. Files you need (the review JSON, probe files) are written with the Write or Edit tool, in the session scratchpad. Every subagent you start follows the same rule (`pr-reviewer.md`, `review-verifier.md`).

1. `gh pr view <n> --json number,title,body,url,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,additions,deletions,files,reviews`. Take `<owner>/<repo>` from `url` (`https://github.com/<owner>/<repo>/pull/<n>`).
   - **Fork PRs are read-only** (owner, 2026-11-02; PUB-3 round 1; `fork/` branches, owner, 2026-11-03). Before any worktree is created, read the PR's head repository and head branch. If `isCrossRepository` is true, or `headRepositoryOwner.login` / `headRepository.name` is missing or is not `<owner>/<repo>`, or `headRefName` starts with `fork/` (a fork PR the owner re-pushed here: `docs/setup/github.md`, "A pull request from a fork"), the review is **read-only**: nothing from the PR is built, tested or run (no `swift`, no `xcodebuild`, no `node`, `npm` or script from the PR, no mutation probe), because those run outside the sandbox and the repository is public. Skip step 3: no worktree. Reviewers and verifiers read the diff only, from the main repository: `git -C <main repo> diff origin/<baseRefName>...origin/pr/<n>` and `git -C <main repo> show origin/pr/<n>:<path>`. The review's first line says so: **Read-only review: the head is a fork's code; nothing from this PR was built, tested or run.**
2. Fetch: `git fetch origin`, exactly, with no arguments. `origin` is the HTTPS remote with `gh` as its credential helper, and its fetch refspecs bring `origin/<baseRefName>` and every PR head as `origin/pr/<n>` (owner, 2026-10-19). A fetch with arguments is never allowed: a refspec can name any destination, so it prompts. If it asks for a username, stop and say so. Then, in a separate call, `git rev-parse origin/pr/<n>`: it must print `headRefOid`; if not, the PR moved during the run — stop.
3. Check the PR out into a separate worktree **in this session's scratchpad**, so the owner's working tree is never touched: `git worktree add <scratchpad>/review/pr-<n> origin/pr/<n>`, or with `at <sha>`: `git worktree add <scratchpad>/review/pr-<n> <sha>`. Run it in the sandbox. Not under the repository: the sandbox write-protects every `.claude/` folder there, so git can neither create nor delete the worktree's `.claude/` files (PR #11's review left 80 files behind). The scratchpad is also the only temporary folder the read-boundary hook lets reviewers read. If a worktree for this PR exists from an earlier run, `git worktree list` shows it; remove it as in §6. With `at <sha>`, first check that the commit belongs to the PR (`git merge-base --is-ancestor <sha> origin/pr/<n>`).
4. Work out the round: look in the PR's reviews for the marker `<!-- moonshine-review round=… head=… -->`. No marker means round 1.

## 2. Choose the lenses

Lens files are `${CLAUDE_SKILL_DIR}/lenses/<name>.md`.

| Lens         | Run when the PR changes                                                                                                                                   |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec`       | always                                                                                                                                                    |
| `privacy`    | always                                                                                                                                                    |
| `docs`       | any `*.md`, `design/`, `docs/`                                                                                                                            |
| `contract`   | any `*.swift`, `bridge/`, `fixtures/`, `scripts/`, `*.mjs`, `*.js`, `*.py`, `.claude/hooks/`                                                              |
| `robustness` | any `*.swift`, `bridge/`, `scripts/`, `*.mjs`, `*.js`, `*.py`, `.claude/hooks/`                                                                           |
| `security`   | any `*.swift`, `bridge/`, `.github/workflows/`, `.claude/`, `scripts/`, `Package.swift`, `Package.resolved`, `package*.json`, `project.yml`, entitlements |
| `platform`   | any `*.swift`, `bridge/`, `Package.swift`, `project.yml`, `.github/workflows/`, or an ADR                                                                 |
| `tests`      | any `*.swift`, `scripts/`, `*.mjs`, `*.js`, `*.py`, `.claude/hooks/`                                                                                      |

### Modes

- **`standard`** (default): three `pr-reviewer` subagents, each with a group of lenses:
  - **code**: `contract` + `robustness` + `tests`;
  - **boundaries**: `privacy` + `security` + `platform`;
  - **consistency**: `spec` + `docs`.

  A group runs only if at least one of its lenses is selected by the table above; within a group, lenses the table does not select are left out.

- **`deep`**: one `pr-reviewer` per selected lens. Use it when the owner asks for it. Propose it (and wait for the owner's answer) when the PR exceeds the size guide in `CLAUDE.md` or touches process execution, concurrency, sync or the assistant.

## 3. Review

Start the `pr-reviewer` subagents of the chosen mode, **all in parallel**. Give each: the worktree path, the main repository path, the pinned dependency sources (`<main repo>/Adapters/.build/checkouts/`, so nobody searches for them), the base ref (`origin/<baseRefName>`, that is `origin/main`; reviewers diff with `git -C <worktree> diff origin/main...HEAD`), the absolute paths of its lens files, the changed file list, and the PR title and description. Give nothing else: no summary of what you expect, no findings from other reviewers. Give the verifiers the same paths. For a fork PR (§1, step 1) give no worktree: give the main repository path, the two read-only commands of §1 and the rule that nothing from the PR is built, tested or run.

In round 2 and later, also pass the earlier findings and the commit they were made on, and ask the reviewer to (a) check that each earlier `High` and `Medium` is really fixed, (b) for every finding marked fixed, check the neighbouring cases of the same defect — root vs subfolder, first vs last, empty vs one (round 2 on #10 found a fix that covered subfolders but not the vault root), and (c) review only `git diff <previous head>..HEAD`.

**Reports.** Round 3 of PR #11 posted a review early and had to replace it.

- A reviewer's or verifier's report is only what its Agent call returns, with the json block. A completion notice or a summary that arrives in a user turn is a status signal, never a report.
- Before verifying, posting or cleaning up, confirm that no reviewer or verifier is still running.
- If a spot check shows a claim in a report to be false, do not drop the claim and go on: get the report again from that agent.
- The worktree is removed only after the review is posted.

## 4. Verify

1. Parse the `json` block from each reviewer. Merge duplicates: same file, lines within five of each other, same defect. Keep the clearer wording and note both lenses.
2. Send every `High` and `Medium` finding to `review-verifier` subagents, grouped by lens, in parallel. Give each verifier its lens name too: a mutation probe runs in its own worktree, `<scratchpad>/review/pr-<n>-probe-<lens>` (`review-verifier.md`), never in the shared one, because verifiers run at the same time. For a fork PR (§1, step 1) verifiers run no probe: they verify from the diff and mark what a probe would have shown as not reproduced.
3. Keep `CONFIRMED` findings. Keep `PLAUSIBLE` ones only when their verified severity is `High`, and label them as not reproduced. Drop `REFUTED` ones. Keep every `Low` finding, unverified.

## 5. Report

Show the owner the `owner` findings first, under **Needs your decision**, then the `author` findings. Each part is a table sorted by severity: severity, class, `path:line`, summary, verdict. Then the failure scenario and the suggested fix for each. Then one line of counts: found, confirmed, plausible, refuted, per lens.

Verdict line:

- any confirmed `High` → **Changes required**;
- only `Medium` or `Low` → **Changes recommended**;
- nothing → **No findings**.

Unless the owner said `local` or `at <sha>`, post **one** GitHub review with event `COMMENT`:

- one inline comment per kept `High` and `Medium` finding, and for at most five `Low` ones, on `path` + `line` (side `RIGHT`); a finding whose line is not part of the diff goes into the review body instead;
- comment text: `**<Severity> · <class> · decision: <author|owner>** — <summary>`, then the failure scenario, then the suggested fix, then `Verified: <verdict> — <verification>`;
- review body: the verdict, the counts, the mode, the lenses that ran, the model, a **Notes** list of **all** `Low` findings (unverified; `path:line` and summary), and the marker `<!-- moonshine-review round=<r> head=<headRefOid> -->`.

Write the request with the Write tool as a JSON file at the fixed path `<scratchpad>/review/pr-<n>-review.json`, never under `$TMPDIR` (sandboxed and unsandboxed commands see different `$TMPDIR` values, so the posting command could not find the file), and send it with `~/.config/moonshine/bin/gh-post review <n> <file>`, written with the absolute home path (`commit_id`, `event`, `body`, `comments[]` with `path`, `line`, `side`, `body`). `gh-post` scans the file with the deny-list and posts it to `POST repos/{owner}/{repo}/pulls/<n>/reviews`; posting through it needs no owner approval (`CLAUDE.md` → "Asking the owner"). If it refuses, fix the text it names by line and kind; never post the review another way.

## 6. Clean up

A read-only review (§1, step 1) created no worktree and no probe worktree: run only `git worktree prune`. Otherwise, in the sandbox (see "Reports" in §3 for when), each as its own call: `git worktree remove --force <scratchpad>/review/pr-<n>` (`--force` because reviewers may leave untracked files, such as test caches), the same for every verifier probe worktree `<scratchpad>/review/pr-<n>-probe-<lens>` that `git worktree list` shows, then `git worktree prune`. Run the prune yourself, never hand it to the owner: the local settings allow it (`.claude/settings.local.example.json`). After PR #15 the owner had to run it by hand, and the next review could not create its worktree. No refs are deleted: `origin/pr/<n>` and `origin/main` belong to `origin` and the next `git fetch origin` updates them (owner, 2026-10-19). Leave nothing else behind.

Never delete anything unsandboxed (no `rm -rf`, no unsandboxed `git worktree remove`). If a sandboxed step fails, stop cleaning up and end the report with the exact command for the owner to run, for example `git worktree remove --force <absolute path>` followed by `git worktree prune`. Files inside this session's scratchpad (the review JSON, caches) are not leftovers: never ask the owner to delete them. List a leftover file only when it lies outside the scratchpad.

## Rounds

The round rule is stated once, in `CLAUDE.md` → "Pull requests". Round 1 reviews the whole PR. From round 2 on, list every finding that is not `High` under "Deferred" so the author can copy it into the PR description.

## For the method log

End with a block the author can paste into the PR's row in `docs/method/log.md`: round number, mode, number of reviewers and verifiers, findings per severity and per decision (`author` / `owner`), confirmed / refuted counts, the classes found, which lens found each `High`, and the subagents' reported token totals. Session cost is what the owner pastes from `/cost`; `n/a` otherwise.

## Keeping the lenses sharp

When the owner, CI, or any other reviewer finds a defect this skill missed, add one line to the matching lens file under "Seen in this repository": what it was and how to look for it. That list is what makes this reviewer better than a generic one.
