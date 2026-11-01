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

**This ADR amends ADR-0005**: every write stays a proposal confirmed by the owner, except commands of the `auto` class defined below (ADR-0005 § Amendment).

### Entities (MoonShine-native, change-logged, synced under ADR-0010)

- **`Capture`**: the text exactly as dictated, device, time, state (`new` → `interpreted` → `closed`). It is saved locally before any network call.
- **`Proposal`**: its source capture; a one-paragraph summary of what was understood; a list of commands, each with a preview; the impact computed by the planning services (what drops out, what moves, by how much); alternatives where they exist; state (`draft` → `confirmed` | `partly confirmed` | `rejected` → `applied`, or `needs attention` for a failed or unresolved `auto` command, below).
- **`Command`**: a typed change (`CompleteTask`, `CreateTask`, `SetPlannedDate`, `Defer`, `LogTime`, `AddTakeNote`, `AddCapacityException`, …) with a MoonShine id (the **idempotency key**), target ids, parameters, autonomy class, origin (`owner` through the UI, or `assistant` from an utterance), for an `assistant` command the literal spans of the utterance it was built from, state (`pending` → `queued` → `executing` → `done` | `failed` | `unknown` | `undone`) and what is needed to undo it.

### One command bus

The UI and the assistant change data only through the `CommandBus`. It is introduced in **phase 2** for MoonShine-native writes (time entries, takes, capacity exceptions) and extended in the Act phase to provider adapters. Every command lands in an **activity log** with undo.

### Execution

- A native command executes at once on the device where it was created.
- A provider command (OmniFocus, later calendar and vault) is **queued**. The Mac executes it when it is online and the provider's capabilities allow it, then the result syncs back. A failure is shown on the proposal, never silently dropped.
- **Executed once.** The command id is the idempotency key. The Mac records the attempt (`executing`, with its time) before running the command. A provider command found `executing` after a restart is **never re-run blindly**: its outcome is `unknown` until the next full import shows the result (the task is completed; or a new inbox task with that title was created after the attempt), and then it becomes `done` or is run again. If the import cannot tell, the command goes to the review inbox for the owner.
- Until the Act phase ships, provider commands in a proposal are shown as a checklist with deep links ("do these in OmniFocus"); native ones are applied.

### Autonomy classes

- **`auto`** — applied without confirmation, when unambiguous. **Until the Act phase ships, `auto` covers native commands only**: log time; add a take note (a draft). **From the Act phase** it also covers `CompleteTask` and `CreateTask` (inbox), executed through the queue.
- A take note filed by the assistant carries only the owner's own words. It gets a direction only when the owner said one of the four words; the assistant never picks a direction and never confirms a take (takes are set only by the owner).
- **`confirm`** — everything else: planned, defer or due dates; dropping or deleting; editing an existing task; project changes; capacity, plan or scenario changes; calendar writes; any change that touches several items.

Conditions for `auto`, all required and checked by the app, not by the model:

1. **Spans.** The model returns the action plus the literal spans of the owner's utterance that name the target and each value. The app checks that every span is a substring of the capture text.
2. **Target resolved by the app.** The app resolves the target itself from its span: exactly one match (for a task: one open task, by an exact or near-exact title within the named line or today's list). The model's own choice of id is not used.
3. The change can be undone.
4. The assistant answers with one line that names what happened (below).

Only then is the command executed. If any condition fails, the command becomes part of a draft proposal, and the assistant asks at most one clarifying question. It never guesses.

The classes are fixed defaults now. A per-class setting in Settings comes later (owner decision 2026-10-03).

**Amendment (2026-10-06, ADR-0015).** `AppendJournal` (the owner's dictated words appended to today's daily note) is the one provider command in the `auto` class before the Act phase, from the time the Write and Ask phases both exist; the four conditions above hold. The assistant's read tools return note bodies only from the folders the owner listed in Settings → Assistant, never from a note with `moonshine_ai: false`; while interpreting for `auto` they still return entity titles only (§ Safety). `moonshine_ai: false` wins in the standing context pack too (owner, 2026-10-09): such a note appears in the pack's list as excluded and is never sent (§ Standing context). The `CommandBus` reaches the vault adapter in the Write phase, before the Act phase extends it to the other providers (§ One command bus). Vault commands created on the iPad or iPhone use the queue under the same once-only rules as other provider commands (§ Execution).

**Amendment (2026-10-07, ADR-0016).** `StartTimer`, `PauseTimer`, `ResumeTimer` and `StopTimer` are native `auto` commands; the subject and any time offset are spans of the utterance and the app resolves the subject itself. `EditTimeEntry` is `auto` only for the entry just stopped; any other edit is a proposal.

**Amendment (2026-10-16, ADR-0017).** `CreateReminder`, `EditReminder`, `MarkReminderSeen`, `SnoozeReminder`, `ArchiveReminder` and `ConvertTaskToReminder` are native `auto` commands. By voice, `CreateReminder` is `auto` only when the text and the whole schedule are spans of the utterance and parse to exactly one schedule; otherwise it is a proposal.

**Amendment (2026-10-19, ADR-0018).** `RecordMemoOutcome`, `ChooseOtherVariant` and `DismissMemo` are native `auto` commands, logged and undoable.

**Amendment (2026-11-01, owner; `docs/specs/phase-2-plan.md`).** A capture is interpreted before the Ask phase, for one feature: Log by text (phase 2). The owner dictates or pastes what he did; the `Capture` is stored on the Mac before any network call; the model returns only literal spans, which the app checks and turns into times; the owner confirms the list as one `LogEntries` command of the `confirm` class, with undo. Consent for cloud AI is required from LT3, per provider (ADR-0005, amendment 2026-11-01). Nothing in this path is `auto`. `AddCapacityException` and `RemoveCapacityException` of kind `away` (ADR-0023) are native `auto` commands, with undo: the one exception to "capacity changes" in the `confirm` class above. An away mark may be set from today up to 400 days ahead, and back to the running and the previous ISO week (spec question 34).

### Where the assistant runs

On each device, against that device's replicated store, through the typed read tools of ADR-0005. The provider key is stored in that device's Keychain. Without a network the capture stays `new` and is interpreted when a connection returns.

### Answers

- `Done` only for a command that has executed: `Done: 25 min logged to Violin.`
- A queued provider command (from the Act phase) is answered as queued: `"Scales — G minor" will be completed in OmniFocus when the Mac is online.`
- A failed or unresolved `auto` command creates an item in the **review inbox** — a proposal in state `needs attention` with the command and the reason — plus an activity-log entry. Nothing fails silently.
- For proposals: `Draft ready: 3 tasks move, 1 drops out. Review it on your Mac or iPad.` The phone shows the summary; the full report waits in a review inbox on every device.

### Standing context

The assistant receives a fixed context pack chosen by the owner in Settings: the planning-context and prioritisation notes from the vault, the current quarter focus, tiers and budgets. The list is visible and editable. It is sent to the provider only under the owner's consent for cloud AI.

### Safety

- Tool results and any imported text are data. An `auto` command executes only when its target and values are spans of the owner's utterance and the app resolved the target from that span (conditions above); text read through tools cannot supply a target or a value. While interpreting for `auto`, tools return entity titles only, never note bodies. A command's origin and spans are recorded.
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
- Bad — unattended actions can be wrong; the span check with app-side target resolution, the one-line answer, undo, the review inbox for failures and the evaluation set reduce this and do not remove it.
- Neutral — VISION principle 4 is reworded: every AI change is visible and reversible; simple, unambiguous changes of the `auto` class are applied at once, everything else waits for confirmation.
- Neutral — the roadmap order changes: Act moves directly after Ask; the lifetime timeline follows.

### Confirmation

- Core tests: a capture is stored when the AI port fails; a command with two matching tasks never executes as `auto`; a command whose target or value is not a span of the utterance never executes as `auto` (it becomes a draft proposal); before the Act phase a provider command is never `auto`, except `AppendJournal` (§ Amendment, ADR-0015); a failed `auto` command creates a `needs attention` item and an activity-log entry; undo restores the previous state for every native command.
- Contract tests for the queue: a provider command created on a non-Mac device is executed once by the Mac; the attempt is recorded before it runs; a command found `executing` after a restart is not re-run until an import resolves it, and goes to the review inbox when the import cannot tell; a failure is reported.
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
