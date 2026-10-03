# Lens: spec — conformance, scope and the project's own rules

The spec in `docs/specs/` is the source of truth for the slice. `CLAUDE.md` holds the hard rules. ADRs hold the costly decisions.

## Questions

1. **Requirement by requirement**: find the slice in the phase spec. For each sentence that states a requirement, and each acceptance line the PR touches: where is it implemented, and which test proves it? Quote the requirement in the finding when it is unmet.
2. **Satisfiable at all**: can each requirement and acceptance line be met given the others, the design tokens and the measured numbers? Do the arithmetic.
3. **Ticked honestly**: is a checkbox ticked while part of its text is not done or was changed by a decision that the text does not record?
4. **Scope**: anything from a later phase built now? Anything the slice requires that is missing? Any abstraction beyond the ports in `ARCHITECTURE.md` without an ADR?
5. **Hard rules, one by one** (`CLAUDE.md`): Core imports no AppKit, SwiftUI, OSAKit, GRDB or EventKit; the UI never talks to adapters; tests came first in Core; privacy; no external writes; dependencies pre-approved and licence-compatible; tone (no red, no forbidden words, amber only for deadlines under the active rule); keyboard access; method-log row present.
6. **Size**: count the changed production lines. State the number and whether the PR declares an overrun.
7. **ADRs**: does the change contradict an ADR? Does it make a costly-to-reverse choice without one? Does a new ADR leave an older one stating the opposite?
8. **Claims versus diff**: for each statement in the PR description and the method-log row ("X is tested", "Y is removed", numbers), check it against the diff.
9. **Decisions recorded**: when the PR implements an owner decision, is the decision written into the spec or an ADR, with its date?

## Seen in this repository

- "29 tasks fit without scrolling" could not hold: the rows alone needed more than the window height.
- "Visible ≤ 2 s after MoonShine becomes active" stayed in the spec after the import was measured at 4.0 s.
- The spec required three-run medians; the measurements were single runs by an owner decision that the spec did not record.
- Keys used only by a later slice (R1) were parsed in S3b.
- The phase spec grouped Lines by block while the design grouped them by tier, and the hand-off rule said the spec wins.
- A spec line pointed to an ADR that was not in the repository.
- A document was "corrected" to match an outdated roadmap instead of the owner's later decision; check the date of each source.
- Slices ran 1.5–2.4× over the size guide; the overrun must be stated, not discovered.
