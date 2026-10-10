# S3b-2 plan — calibration case for `plan-critic`

> The S3b-2 plan as its author first wrote it (2026-10-07), word for word, inside the fence. A calibration run gives the critic only the text inside the fence, copied to a file in the session scratchpad, with `slice: S3b-2` and `root:` a worktree of `main` just before PR #12 was merged (`0dcbcdd`). The answer key is [plan-critic-s3b-2-key.md](plan-critic-s3b-2-key.md); never give it to the critic.

```text
I've read the spec, the vault contract, the S3b-1 reader, the store records and moonshine-import, and the plan is below. I haven't written any code or created a branch.

S3b-2 — Lines: plan
What the spec asks for
Find the budget note by moonshine: budget only. If there is none, report budgetNoteMissing as an issue without a path. If there are several, the first by path wins and the others get a banner.
Read lines: with the v0.2 keys and carry them to Line and the store.
Add the live check as a moonshine-import vault subcommand that prints counts only. It includes the anchor rejections and does not fail on them.
Size and split
Part	Production lines
Core: foundation, floorHoursPerDay, language on Line/SourceLine (defaulted init params, so existing callers don't change); SourceLine: Equatable; new problem kinds; vault-wide issue case; Importer carry-over	~50
Adapter: small key/scalar accessors on FrontNode, finding the budget note, validating lines: items, a public ObsidianVault: NoteProvider, a note count in VaultScan	~225
Store: three optional fields in LineRecord.Attrs (no migration, ADR-0002), the new issue case in WorkspaceRecord	~18
CLI vault subcommand + Package.swift dependency	~60
Total	~355 → doubled ~710
That is above 400, so I'd split it into three PRs:

S3b-2a — Budget note and live check (~140, doubled ~280): finding the budget note (missing or duplicate), the vault-wide issue shape in Core and the store, the note count, the vault subcommand. This puts the anchor count on the real vault first. That count is the one that could reopen S3b-1's rule, so it's worth seeing before more code depends on it.
S3b-2b — Lines, v0 keys (~170, doubled ~340): id, name, emoji, block, state, budget_h_week, parent, omnifocus.{tags,folders,projects}, all validated. A golden test checks that the reader's output on fixtures/vault/ matches DemoVault.snapshot.lines. The live check adds line counts.
S3b-2c — Lines, v0.2 keys (~70, doubled ~140): foundation, floor_h_day (ignored with a banner when the line isn't foundation), language (parse only). These go into Line, the store attrs and the store contract suite. The live check adds counts for these.
I'd reuse your S3b-1 rule: if 2a's actual size is under 1.3× its estimate, 2b and 2c ship as one PR.

Left for S3b-3 (unchanged): recognised notes, deriving scale and period, year and quarter artifacts:, the full golden test (including the budget note itself as a SourceNote), and live-check counts for artifacts and notes by type.

Not in S3b-2:

Tier grouping and "foundation is never quiet" in Overview: that belongs to the Lines and Today views in S4.
Foundation lines in fixtures/vault/ and DemoVault: that is the Demo-data step. 2c tests the v0.2 keys with invented notes in a temporary folder.
Validation (2b and 2c)
Scalars arrive as raw strings from FrontNode, so:

Numbers: decimal digits only, matching ^\d+(\.\d+)?$. That excludes signs, exponents, hex, nan and inf; Swift's Double("0x1p4") would otherwise accept hex. Limits are budget_h_week 0…168 and floor_h_day 0…24. null, ~ or an empty value means the key is absent.
foundation: only true or false.
id: must match [a-z0-9-]+, at most 64 characters, unique. A duplicate means the later line is skipped.
name and block: non-empty after trimming.
state: active, maintenance or paused.
language: shaped like ^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$, at most 35 characters.
omnifocus.*: lists of strings.
What happens on a bad value:
A required key missing or invalid: the line is skipped, with missingKey or invalidValue and the key name (e.g. lines[3].state), plus the line number.
An optional key invalid: the value is dropped and the line is kept.
lines: missing or not a list: zero lines and one issue.
Issues never carry a value from the note.
Live check
The vault path is an argument, so no library carries a path to it. Two steps:


swift build -c release --package-path Adapters --product moonshine-import
Adapters/.build/release/moonshine-import vault ~/ObsidianV
Your approval: both commands need the sandbox off. SwiftPM can't write .build inside it, and the home folder is read-denied. Only the second command reads the vault. Before each run I ask you in chat, and the permission prompt then asks again. I never start a run without your OK in that turn.
What it prints (2a): counts only, every kind always listed, zeros included. No paths, note names or values.

vault: 1234 notes read · 456 with frontmatter · 0.41 s
rejected notes: 3 (unreadable 0 · notUTF8 0 · frontmatterTooLarge 0 · malformedYAML 3 · yamlTooComplex 0 · yamlAnchor 0)
notes rejected for an anchor: 0
skipped: symlinks 0 · outside vault 0 · unreadable folders 0
budget note: found | missing | 2 found, first by path used
Added in 2b: lines: 15 of 16 items (active 9 · maintenance 3 · paused 3) · line problems: missingKey 1 · invalidValue 0 · duplicateLineId 0
Added in 2c: foundation 2 · with floor 2 · with language 3 · floor ignored 0
Exit code: 0 even when there are problems. It is non-zero only for a fatal error (the vault folder can't be read, too many notes) or wrong usage. Those messages carry no path.
If yamlAnchor is above 0, I stop and tell you, as the spec says.
One caveat: an anchor rejection on the budget note would also show as budget note: missing, because the note is rejected before its marker is read.
Before the first run you need to have added moonshine: budget to the budget note.
Open questions
Split: OK to do three PRs (2a/2b/2c), merging 2b and 2c if 2a comes in under 1.3×? The two-PR alternative (2a, then 2b+2c) is about 450 doubled, above the limit.
Issue shape for budgetNoteMissing:
(a) a new case ImportIssue.vaultWide(VaultProblem), which I recommend because no note-level issue can lose its path by accident; or
(b) making the path optional on .vault.
Limits and rules: do the validation limits and the skip-or-drop rule above work for you (168 h/week, 24 h/day, ids up to 64 characters)? For a floor without foundation, I'd add a new problem kind, keyIgnored.
Missing or broken budget note at runtime: once the app imports (S4), a missing budget note soft-deletes every line and moves every task to Life ops until it's fixed. The ids come back when the note does. Is that acceptable, or should S4 keep the last good lines? I'd decide this in S4, not here.
```
