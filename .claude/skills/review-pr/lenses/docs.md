# Lens: docs — one fact, one value, everywhere

The repository has specs, ADRs, contracts, a design hand-off and demo data that describe the same things. A PR that changes one of them usually makes another one false. Authority order: `docs/VISION.md`, `docs/specs/` and ADRs outrank `design/`; inside `design/`, a screen spec outranks its mockup; `design/demo-data.md` is the canonical source of every demo number.

## Method

1. **Fact table.** From the changed documents, list every checkable fact: numbers, counts, totals, averages, dates, week and quarter numbers, phase and slice assignments, shortcuts, thresholds, sizes, names of files, keys, types and settings.
2. **Search.** For each fact, `Grep` the repository for the same subject. Report every place that states a different value, and say which source wins.
3. **Recompute.** Derive every total, sum, average, count and date from its canonical table. Do the arithmetic yourself; do not trust the text.
4. **Resolve.** Check every link, `[[wikilink]]`, file path, section reference, ADR number and artboard name. A reference to something that is not in the PR's head is a finding.
5. **Stale statements.** Search for sentences that this PR makes false: "pending", "to be decided", "not yet", "draft-1", "see X" where X has changed, and requirements that an ADR in this PR replaces.
6. **Examples against their own rules.** Does each YAML, JSON or code example satisfy the contract stated in the same or a linked document?
7. **Holes in rules.** For each rule with a limit or a list: what happens at zero, at one more than the limit, when the list is empty, when two rules apply at once?
8. **Languages and tone.** New user-facing strings exist in every required language file; forbidden words are absent in each language; terms match the glossary.

## Seen in this repository

- "6 active" where the table has 7; the subtitle did not add up to its own total.
- Four anchor tasks added to a screen but not to the canonical task table: totals 25/22/3 versus 29/23/6.
- Averages 5.5 and 1.3 printed on screens; the canonical history gives 4.0 and 1.0.
- 13 weeks drawn for a quarter that spans 14 ISO weeks.
- Excel import placed in phase 2 in one document and phase 3 in two others.
- 1,961 in an ADR, 1,962 in the contract: two runs, neither labelled.
- ⌘[ / ⌘] on one screen and ⌘← / ⌘→ on another for the same action.
- "Sync ADR pending" and "mockups still show draft-1" left in after both had changed.
- An ADR's confirmation criterion required incremental refresh after a newer ADR chose full imports.
- A quarter-note example without the `type` key that the same contract requires.
- "Up to 5 chips" with no rule for a sixth item.
- A contract change that pointed to the vault contract while the fields belong to the snapshot contract.
