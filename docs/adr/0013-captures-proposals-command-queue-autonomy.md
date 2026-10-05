---
title: "0013 — Voice captures, proposals and a command queue; autonomy levels for the assistant"
status: proposed
date: 2026-10-03
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0001-own-domain-model-with-ports-and-adapters]]"
  - "[[0005-assistant-tools-over-domain-proposals-and-mcp]]"
  - "[[0006-plan-model-steps-effort-levels-simulated-forecast]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0011-change-driven-import-full-snapshots-on-omnifocus-deactivation]]"
---

# 0013 — Voice captures, proposals and a command queue; autonomy levels for the assistant

## Context and Problem Statement

The owner wants to use MoonShine as a personal secretary. From the phone (later a watch, or the Mac) he dictates what happened: tasks done, a session that took 25 minutes instead of 30, new tasks, a change of plans, a trip next Thursday. Simple facts should be recorded at once with a short "done". Anything that changes plans should become a **draft report** — what drops out, what moves, which options exist — that he reads and confirms later on the Mac or iPad. Only then do the changes enter the system.

Parts of this already exist as decisions: typed tools and write-as-proposal (ADR-0005), commands with confirm and undo (roadmap "Act"), the Mac as the only writer of provider data (ADR-0010), the planning engine that knows what moves (ADR-0006). Three things are missing: a durable, synced record of what was said and what was proposed; a way for a phone to cause a change in OmniFocus; and a rule for what the assistant may do without asking. **How does a dictated sentence become a safe, reviewable change on any device?**

## Decision Drivers

- A capture must never be lost: no network, no AI and no Mac may be available at that moment.
- Simple facts need an immediate answer; consequential changes need a review, possibly hours later and on another device.
- Dictation makes mistakes, and names of tasks are ambiguous. A wrong unattended action costs more than a question.
- Text in tasks, notes, events and imported files is untrusted; it must never be able to cause a write.
- External tools are written only by the Mac (ADR-0003, ADR-0010).
- Every AI action stays visible and reversible (VISION principle 4).
- One write path for the UI and the assistant, so undo and the activity log cover both.
- No own server before phase 8.

## Considered Options

1. **Capture → Proposal → Command queue, with the assistant running on each device and autonomy decided by action class.**
2. The assistant runs only on the Mac; the phone stores raw captures.
3. An own server runs the assistant and holds the queue.
4. A chat-only assistant that answers and proposes, with every change applied by hand.

## Decision Outcome

**Chosen option: "1"**, because it gives an immediate answer on the phone, keeps the Mac as the only writer to OmniFocus, needs no server, and reuses the proposal and command concepts already decided.

### Entities (MoonShine-native, change-logged, synced under ADR-0010)

- **`Capture`**: the text exactly as dictated, device, time, state (`new` → `interpreted` → `closed`). It is saved locally before any network call.
- **`Proposal`**: its source capture; a one-paragraph summary of what was understood; a list of commands, each with a preview; the impact computed by the planning services (what drops out, what moves, by how much); alternatives where they exist; state (`draft` → `confirmed` | `partly confirmed` | `rejected` → `applied`).
- **`Command`**: a typed change (`CompleteTask`, `CreateTask`, `SetPlannedDate`, `Defer`, `LogTime`, `AddTakeNote`, `AddCapacityException`, …) with target ids, parameters, autonomy class, origin (`owner` through the UI, or `assistant` from an utterance), state (`pending` → `queued` → `executing` → `done` | `failed` | `undone`) and what is needed to undo it.

### One command bus

The UI and the assistant change data only through the `CommandBus`. It is introduced in **phase 2** for MoonShine-native writes (time entries, takes, capacity exceptions) and extended in the Act phase to provider adapters. Every command lands in an **activity log** with undo.

### Execution

- A native command executes at once on the device where it was created.
- A provider command (OmniFocus, later calendar and vault) is **queued**. The Mac executes it when it is online and the provider's capabilities allow it, then the result syncs back. A failure is shown on the proposal, never silently dropped.
- Until the Act phase ships, provider commands in a proposal are shown as a checklist with deep links ("do these in OmniFocus"); native ones are applied.

### Autonomy classes

- **`auto`** — applied without confirmation, when unambiguous: log time; add a take note or draft; complete a task; create a task in the inbox.
- **`confirm`** — everything else: planned, defer or due dates; dropping or deleting; editing an existing task; project changes; capacity, plan or scenario changes; calendar writes; any change that touches several items.

Conditions for `auto`, all required: the command follows from the owner's own utterance; exactly one entity matches (for a task: one open task, by an exact or near-exact title within the named line or today's list); the change can be undone; the assistant answers with one line that names what it did. If any condition fails, the command becomes part of a draft proposal, and the assistant asks at most one clarifying question. It never guesses.

The classes are fixed defaults now. A per-class setting in Settings comes later (owner decision 2026-10-03).

### Where the assistant runs

On each device, against that device's replicated store, through the typed read tools of ADR-0005. The provider key is stored in that device's Keychain. Without a network the capture stays `new` and is interpreted when a connection returns.

### Answers

- For `auto` actions: one line, for example `Done: "Scales — G minor" completed, 25 min logged to Violin.`
- For proposals: `Draft ready: 3 tasks move, 1 drops out. Review it on your Mac or iPad.` The phone shows the summary; the full report waits in a review inbox on every device.

### Standing context

The assistant receives a fixed context pack chosen by the owner in Settings: the planning-context and prioritisation notes from the vault, the current quarter focus, tiers and budgets. The list is visible and editable. It is sent to the provider only under the owner's consent for cloud AI.

### Safety

- Tool results and any imported text are data. Write tools can be called only in a turn that answers an owner utterance, and a command's origin is recorded.
- Reproducible evaluation: a set of invented utterances (Russian, English and mixed-script task titles, with typical dictation errors) with expected commands and classes runs in CI. Wrong `auto` actions are counted separately from wrong drafts.
- A wrong completion of a repeating task is awkward to undo in OmniFocus; this is why completion needs exactly one match.

### Voice

System dictation into a text field, plus an App Intent (Shortcuts, Action button, later a watch) that saves a capture without opening the app. In-app audio recording with its own transcription is a later, separate decision.

### Consequences

- Good — nothing dictated is lost; simple facts are recorded in seconds; consequential changes are reviewed where reading is comfortable.
- Good — one write path gives undo and an activity log for both the UI and the assistant.
- Good — the phone works without the Mac for capture, interpretation and native data.
- Bad — OmniFocus changes wait for the Mac; a confirmed proposal can stay "queued" for hours.
- Bad — a provider key on each device, and a cost per utterance.
- Bad — three new synced entities with state machines; a proposal reviewed on two devices at once needs a clear rule (first confirmation wins; the other device shows the result).
- Bad — unattended actions can be wrong; the exact-match rule, the one-line answer, undo and the evaluation set reduce this and do not remove it.
- Neutral — VISION principle 4 is reworded: every AI change is visible and reversible; simple, unambiguous changes of the `auto` class are applied at once, everything else waits for confirmation.
- Neutral — the roadmap order changes: Act moves directly after Ask; the lifetime timeline follows.

### Confirmation

- Core tests: a capture is stored when the AI port fails; a command with two matching tasks never executes as `auto`; a command whose origin is tool output is rejected; undo restores the previous state for every native command.
- Contract tests for the queue: a provider command created on a non-Mac device is executed once by the Mac, survives a restart, and reports failure.
- The evaluation set runs in CI; the method log records the rate of wrong `auto` actions per release.

## Pros and Cons of the Options

### 2. Assistant only on the Mac

- Good — one place holds the key and the full data.
- Bad — no immediate answer on the phone; nothing happens while the Mac is off.

### 3. Own server

- Good — always on, any device.
- Bad — personal data and keys leave the owner's devices; infrastructure before any audience; against the phase-8 gate.

### 4. Chat only

- Good — the safest; nothing changes without the owner's hands.
- Bad — it is not a secretary: every dictated fact still has to be entered by hand.
