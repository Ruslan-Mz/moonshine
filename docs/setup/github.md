# GitHub setup for MoonShine

The repository settings the owner makes by hand, in this order. Every step is a repository setting or an irreversible action, so it is the owner's (CLAUDE.md, "Asking the owner" (b)). The order matters: the repository is public before the environment can exist on the current plan; the environment's branch policy is set before its secret, so the secret is never readable from another branch; the secret exists before `guard` becomes a required check, which would otherwise block every merge.

Menu paths are those of the GitHub web interface on 2026-11-01; where GitHub has renamed a page, the older name is given in brackets.

## Steps 1–4: the flip (done, 2026-11-01)

The owner made the repository public on 2026-11-01, after PUB-2 (`docs/specs/phase-1-see.md` → PUB). Steps 3 and 4 are confirmed by the owner outside this document.

1. [x] **Delete the Actions runs and artifacts.** Repository → **Actions** → each workflow in the left column → each run → **⋯** → **Delete workflow run** (this deletes the run's logs and artifacts). The owner does it in the interface; a bulk delete is a GitHub write no session makes.
2. [x] **Make the repository public.** **Settings** → **General** → **Danger Zone** → **Change repository visibility** → **Change to public**, then confirm.
3. [x] **Secret scanning and push protection.** **Settings** → **Security** → **Advanced Security** (formerly **Code security and analysis**) → **Secret Protection** (or **Secret scanning**): **Enable**; **Push protection**: **Enable**.
4. [x] **Approval for fork pull requests.** **Settings** → **Actions** → **General** → **Approval for running fork pull request workflows from contributors** → **Require approval for all external contributors** → **Save**.

## Step 5: the environment `guard` and its secret (after PUB-3 is merged)

Until this step, the `guard` check fails on every pull request ("DENY_LIST is not set"). That is expected; it is not a required check yet.

1. **Settings** → **Environments** → **New environment** → name `guard` → **Configure environment**. If a run of `guard.yml` already created `guard` (GitHub creates a missing environment, with no rules, the first time a job names it), open it instead.
2. **Deployment branches and tags** → **Selected branches and tags** → **Add deployment branch or tag rule** → **Ref type: Branch**, **Name pattern:** `main` → **Add rule**. No other rule. No **Required reviewers** (they would hold every run until someone approves it).
3. Only now: **Environment secrets** → **Add environment secret** → **Name:** `DENY_LIST`, **Value:** the whole text of the deny-list file → **Add secret**. A secret holds at most 48 KB; a longer deny-list stops here.
4. **Settings** → **Secrets and variables** → **Actions** → **Repository secrets**: no `DENY_LIST` there (and none among the account's organisation secrets, if any). A repository secret is readable by any workflow on any branch, past the environment's policy.
5. Check: on an open pull request from a branch of this repository, **Checks** → **Guard** → **Re-run all jobs**. It passes, and its findings name commits and files only, never an entry. The log never shows the pull request's title or body; the checkout step lists the repository's branch names, which are public once pushed.
6. Pushes to `main` between the merge of PUB-3 and this step failed with "DENY_LIST is not set", and nothing re-runs them: **Actions** → **Guard** → filter **Branch:** `main` → each failed run → **Re-run all jobs**. A re-run scans the same range of `main` as the first run.

## Step 6: branch protection on `main`

1. **Settings** → **Branches** → **Add classic branch protection rule** → **Branch name pattern:** `main`.
2. **Require a pull request before merging**: on; **Require approvals**: off (the owner cannot approve his own pull requests).
3. **Require status checks to pass before merging**: on; **Require branches to be up to date before merging**: on. In the search box add `docs`, `swift`, `core-linux` and `guard`, and for each choose the source **GitHub Actions**, so no other app can report a check of the same name. A check appears in the search only after it ran in the last week.
4. **Do not allow bypassing the above settings**: on (administrators included).
5. **Allow force pushes** and **Allow deletions**: off.
6. **Create**.

A job skipped by its condition counts as passed: a docs-only pull request, whose `swift` and `core-linux` jobs are skipped, can still merge.

## Step 7: the Actions event policy for `pull_request_target` (done, 2026-11-16)

From 2026-12-02 GitHub blocks `pull_request_target` for public repositories unless an Actions event policy allows it; brownouts before that date apply the block for a few hours (the second, 2026-11-16 16:00–18:00 UTC, stopped two Guard runs on #62 with `startup_failure`: no job and no message). The owner added an event policy that allows `pull_request_target` for `.github/workflows/guard.yml` only (owner, 2026-11-16). Reason: `guard.yml` never checks out or runs the pull request's code. It runs as `main` holds it, fetches the pull request's commits as data and scans them, and reads the title, body and branch name from the event file (CLAUDE.md → Commands → Guard, "The guard in CI"). No other workflow may use `pull_request_target`: one that checks out or runs a pull request's files would run them with the base repository's token and secrets.

The policy as the owner set it (owner, 2026-11-16; P-HR):

- name `enable pull_request_target`, state **Active**;
- targeted to `.github/workflows/guard.yml` only;
- allowed events `pull_request_target` and `push`;
- created on 2026-11-16, ahead of GitHub's default block of 2026-12-02.

What runs `guard.yml` (`guard.yml`'s `on:`, pinned by `scripts/guard-workflow.test.mjs`): `pull_request_target` with `opened`, `synchronize` and `reopened`, so every new head is scanned, and `edited`, so a changed title or body is scanned again; `push` to `main`. What never runs it: `pull_request` (its secrets and code would be the PR's own), `workflow_dispatch` and `schedule` (the scheduled scan of branches is the PUB follow-up, below), `labeled` and the other activity types (nothing new to scan). A change to these events is a reviewed edit of `guard.yml` and of the test, and, for an event the policy does not list, of the policy.

Check after a change to the policy: a body edit of an open pull request (`gh-post pr-edit`) starts a Guard run that succeeds. A Guard run that ends in `startup_failure` with no job usually means the policy does not cover the run, not a fault in the branch.

## Live checks after step 6

1. `guard` shows on a branch pull request's checks.
2. A docs-only pull request merges with `swift` and `core-linux` skipped.
3. Add an invented word to `DENY_LIST` for the test and put it in a pull request's added line: `guard` fails with `commit …, "<file>":<line>: a deny-list entry` and no text. Remove the word from the secret afterwards.
4. A test pull request that adds a `pull_request` job with `environment: guard`, printing only whether the secret is set (`[ -n "$X" ] && echo present || echo absent`, never its value): the job is refused the environment. Close the pull request unmerged.
5. A pull request from a fork (a second account, if there is one): `guard` fails with "fork PR: not scanned".
6. In zsh, the guard's reinstall command (CLAUDE.md → Commands → Guard) runs and installs `commit-scan.mjs`.

## A pull request from a fork

`guard` fails it unscanned, and `/review-pr` reviews it read-only: it reads the diff and builds, tests and runs nothing from it (`.claude/skills/review-pr/SKILL.md`, §1). To take it further, the owner:

1. scans its commits locally (the pre-push hook does this on the push below);
2. re-pushes its head here as a branch named `fork/<pr>-<slug>`: `<pr>` the fork PR's number, `<slug>` a few words of its own, `git push origin HEAD:refs/heads/fork/<pr>-<slug>`;
3. opens a pull request from that branch. `guard` scans it as usual; `/review-pr` treats a head branch starting `fork/` as read-only too, like a cross-repository head, since its code is still a stranger's.

## After merging a pull request that changes `.claude/`

P-AM3 (owner, 2026-11-25). The sandbox denies a session's writes to `.claude/settings.json`, `.claude/hooks/` and `.claude/skills/` (CLAUDE.md → Commands → Local sandbox; `.claude/skills/` seen on 2026-11-24). So a session's `git merge --ff-only origin/main` over such a merge, or a later `git switch` onto it, stops halfway. The owner runs these from the owner's own terminal, in this order:

1. `git -C <main checkout> fetch origin`;
2. `git -C <main checkout> switch main`: the main checkout may still be on the merged slice's branch, and a fast-forward of that branch leaves local `main` behind, so the next `git switch main` would stop on `.claude/` again;
3. `git -C <main checkout> merge --ff-only origin/main`;
4. each author worktree, by its state (owner, PR #71 round 1). Worktrees share the main checkout's refs, so step 1 serves them. `git -C <worktree> branch --show-current` prints nothing when the worktree is detached, and the slice branch's name when it is on one:
   - idle or detached: `git -C <worktree> switch --detach origin/main`;
   - mid-slice on its own branch: never detach it. `git -C <worktree> merge origin/main` merges the change into the slice branch, and the session then pushes as usual, with no non-fast-forward;
5. when the merge also changed `scripts/guard/`, `scripts/xcbuild.sh` or `scripts/check-project-scripts.mjs`, the guard's reinstall (CLAUDE.md → Commands → Guard).

**When a fast-forward or a switch stopped halfway.** git writes the files first and moves `HEAD` and the index last. A stop leaves `HEAD` where it was, with some of the new commit's files written over it. The session stops and tells the owner, and touches nothing. The owner checks with `git -C <checkout> status` that every changed or untracked path is one the stopped merge or switch was writing, and that no other work is uncommitted. Then:

- the main checkout on `main`: `git -C <main checkout> reset --hard origin/main`;
- the main checkout still on the merged slice's branch, after a `git switch main` stopped (PR #71 round 1): `git -C <main checkout> switch --discard-changes main`, then steps 3 to 5 above. A `reset --hard` there would move the slice branch, not `main`;
- a detached worktree: `git -C <worktree> switch --detach --discard-changes origin/main`.

Anything `status` shows that the stopped merge or switch was not writing is the session's own work: commit it or set it aside first.

## What the guard in CI does not do

It keeps a match off `main` and flags it on the pull request. It does not keep a pushed commit off GitHub: a pushed branch is public at once, and GitHub keeps every pull request's head. A branch pushed without a pull request is not scanned; a scheduled scan of branch heads and tags not reachable from `main` is a follow-up (`docs/specs/phase-1-see.md` → PUB).
