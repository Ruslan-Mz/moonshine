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
5. Check: on an open pull request from a branch of this repository, **Checks** → **Guard** → **Re-run all jobs**. It passes, and its log names commits and files only, never an entry.
6. Pushes to `main` between the merge of PUB-3 and this step failed with "DENY_LIST is not set", and nothing re-runs them: **Actions** → **Guard** → filter **Branch:** `main` → each failed run → **Re-run all jobs**. A re-run scans the same range of `main` as the first run.

## Step 6: branch protection on `main`

1. **Settings** → **Branches** → **Add classic branch protection rule** → **Branch name pattern:** `main`.
2. **Require a pull request before merging**: on; **Require approvals**: off (the owner cannot approve his own pull requests).
3. **Require status checks to pass before merging**: on; **Require branches to be up to date before merging**: on. In the search box add `docs`, `swift`, `core-linux` and `guard`, and for each choose the source **GitHub Actions**, so no other app can report a check of the same name. A check appears in the search only after it ran in the last week.
4. **Do not allow bypassing the above settings**: on (administrators included).
5. **Allow force pushes** and **Allow deletions**: off.
6. **Create**.

A job skipped by its condition counts as passed: a docs-only pull request, whose `swift` and `core-linux` jobs are skipped, can still merge.

## Live checks after step 6

1. `guard` shows on a branch pull request's checks.
2. A docs-only pull request merges with `swift` and `core-linux` skipped.
3. Add an invented word to `DENY_LIST` for the test and put it in a pull request's added line: `guard` fails with `commit …, "<file>":<line>: a deny-list entry` and no text. Remove the word from the secret afterwards.
4. A test pull request that adds a `pull_request` job with `environment: guard`, printing only whether the secret is set (`[ -n "$X" ] && echo present || echo absent`, never its value): the job is refused the environment. Close the pull request unmerged.
5. A pull request from a fork (a second account, if there is one): `guard` fails with "fork PR: not scanned".
6. In zsh, the guard's reinstall command (CLAUDE.md → Commands → Guard) runs and installs `commit-scan.mjs`.

## What the guard in CI does not do

It keeps a match off `main` and flags it on the pull request. It does not keep a pushed commit off GitHub: a pushed branch is public at once, and GitHub keeps every pull request's head. A branch pushed without a pull request is not scanned; a scheduled scan of branch heads and tags not reachable from `main` is a follow-up (`docs/specs/phase-1-see.md` → PUB).
