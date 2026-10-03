---
name: review-pr
description: Independent multi-lens review of a MoonShine pull request by Opus reviewers in fresh contexts, followed by an adversarial verification pass and inline PR comments. Use when the owner asks to review a pull request, for example "/review-pr 7" or "review PR 7". Never run it in the session that wrote the PR's code.
---

# Review a pull request

The author of a change cannot review it well: it reads what it meant, not what it wrote. This skill gives every PR reviewers that start from nothing, each looking through one lens, and a verifier that tries to prove them wrong.

## 0. Preconditions

- **Fresh session.** If this session wrote or edited code in the PR, stop and tell the owner to run the skill in a new session.
- The PR number comes from the owner's request. If none is given, use the PR of the current branch (`gh pr view --json number`).
- The owner may add: `local` (do not post to GitHub, report here only) or `since <sha>` (review only what changed after that commit).
- You orchestrate. You do not review the code yourself and you do not fix anything.

## 1. Prepare

1. `gh pr view <n> --json number,title,body,baseRefName,headRefName,headRefOid,additions,deletions,files,reviews`
2. `git fetch origin <baseRefName> <headRefName>`
3. Check the PR out into a separate worktree so the owner's working tree is never touched: `git worktree add .build/review/pr-<n> <headRefOid>` (`.build/` is git-ignored). If it exists from an earlier run, remove it first.
4. Work out the round: look in the PR's reviews for the marker `<!-- moonshine-review round=… head=… -->`. No marker means round 1.

## 2. Choose the lenses

Lens files are in `lenses/` next to this file.

| Lens         | Run when the PR changes                                                                                                           |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `spec`       | always                                                                                                                            |
| `privacy`    | always                                                                                                                            |
| `docs`       | any `*.md`, `design/`, `docs/`                                                                                                    |
| `contract`   | any `*.swift`, `bridge/`, `fixtures/`                                                                                             |
| `robustness` | any `*.swift`, `bridge/`                                                                                                          |
| `security`   | any `*.swift`, `bridge/`, `.github/workflows/`, `Package.swift`, `Package.resolved`, `package*.json`, `project.yml`, entitlements |
| `platform`   | any `*.swift`, `bridge/`, `Package.swift`, `project.yml`, `.github/workflows/`, or an ADR                                         |
| `tests`      | any `*.swift`                                                                                                                     |

## 3. Review

Start one `pr-reviewer` subagent per chosen lens, **all in parallel**. Give each: the worktree path, the base ref (`origin/<baseRefName>`), the absolute path of its lens file, the changed file list, and the PR title and description. Give nothing else: no summary of what you expect, no findings from other lenses.

In round 2 and later, also pass the earlier findings and the commit they were made on, and ask the reviewer to (a) check that each earlier `High` and `Medium` is really fixed and (b) review only `git diff <previous head>..HEAD`.

## 4. Verify

1. Parse the `json` block from each reviewer. Merge duplicates: same file, lines within five of each other, same defect. Keep the clearer wording and note both lenses.
2. Send every `High` and `Medium` finding to `review-verifier` subagents, grouped by lens, in parallel.
3. Keep `CONFIRMED` findings. Keep `PLAUSIBLE` ones only when their verified severity is `High`, and label them as not reproduced. Drop `REFUTED` ones. Keep at most five `Low` findings, unverified, as notes.

## 5. Report

Show the owner a table sorted by severity: severity, class, `path:line`, summary, verdict. Then the failure scenario and the suggested fix for each. Then one line of counts: found, confirmed, plausible, refuted, per lens.

Verdict line:

- any confirmed `High` → **Changes required**;
- only `Medium` or `Low` → **Changes recommended**;
- nothing → **No findings**.

Unless the owner said `local`, post **one** GitHub review with event `COMMENT`:

- one inline comment per kept finding on `path` + `line` (side `RIGHT`); a finding whose line is not part of the diff goes into the review body instead;
- comment text: `**<Severity> · <class>** — <summary>`, then the failure scenario, then the suggested fix, then `Verified: <verdict> — <verification>`;
- review body: the verdict, the counts, the lenses that ran, the model, and the marker `<!-- moonshine-review round=<r> head=<headRefOid> -->`.

Build the request as a JSON file under `$TMPDIR` and send it with `gh api --method POST repos/{owner}/{repo}/pulls/<n>/reviews --input <file>` (`commit_id`, `event`, `body`, `comments[]` with `path`, `line`, `side`, `body`).

## 6. Clean up

`git worktree remove .build/review/pr-<n>`. Leave nothing else behind.

## Rounds

- Round 1 reviews the whole PR.
- A further round is run only when the previous round had a confirmed `High`.
- From round 2 on, only `High` findings must be fixed in this PR. List the rest in the report under "Deferred" so the author can copy them into the PR description.

## For the method log

End with a block the author can paste into the PR's row in `docs/method/log.md`: round number, findings per severity, confirmed / refuted counts, the classes found, and which lens found each `High`.

## Keeping the lenses sharp

When the owner, CI, or any other reviewer finds a defect this skill missed, add one line to the matching lens file under "Seen in this repository": what it was and how to look for it. That list is what makes this reviewer better than a generic one.
