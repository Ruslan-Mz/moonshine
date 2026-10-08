---
title: "0015 — Writing to the vault: a narrow command path, rituals over Obsidian templates, a simple editor"
status: proposed
date: 2026-10-06
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0004-obsidian-adapter-and-notes-stay-markdown-files]]"
  - "[[0005-assistant-tools-over-domain-proposals-and-mcp]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0013-captures-proposals-command-queue-autonomy]]"
  - "[[0014-project-hub-bindings-in-project-note-and-link-index]]"
---

# 0015 — Writing to the vault: a narrow command path, rituals over Obsidian templates, a simple editor

## Context and Problem Statement

The owner wants to keep a journal, run his daily and weekly review templates and write project notes from MoonShine, later by voice, in the same vault that Obsidian edits and Obsidian Sync carries to his devices. He already has such templates in Obsidian (core Templates and Templater, mostly without scripts) and almost never uses them. ADR-0004 keeps notes as Markdown files and forbids any vault write before the Act phase; the roadmap had the notes module in the gated Own phase. **How does MoonShine write into a vault that Obsidian also edits and syncs, without risking the owner's notes, and how much of an editor does it need?**

## Decision Drivers

- The vault is the owner's most valuable data. A wrong write costs more than a missing feature.
- Obsidian stays the editor for long texts. Both tools must address the same files: one daily note, not two.
- Friction is why the templates go unused. An entry must be one action away from Today and arrive pre-filled with the facts MoonShine already has.
- Obsidian Sync is the vault's transport. No second sync for note bodies.
- Nothing that comes from the vault is ever executed.
- Journal text is the most sensitive data; the owner decides what the assistant may read.
- One write path with undo for the UI and the assistant (ADR-0013).
- The project is built on weekends. An editor with Obsidian's features is out of reach and is not what makes MoonShine useful.

## Considered Options

1. **Narrow typed write commands on files; rituals that reference Obsidian templates; a plain editor with a preview; Obsidian for everything else.**
2. An own notes store in SQLite, exported to the vault.
3. A full Obsidian-compatible editor (live preview, plugin syntax).
4. Writing through Obsidian's URL scheme, so that MoonShine never touches a file.
5. Stay read-only; all writing happens in Obsidian.

## Decision Outcome

**Chosen option: "1"**, because it keeps the vault as plain files that both tools address in the same way, limits what a wrong write can damage, removes the friction that keeps the templates unused, and fits a weekend-sized project.

**This ADR amends ADR-0004** (vault writes start in the Write phase, not the Act phase), **ADR-0013** (one provider command joins the `auto` class before the Act phase; an allowlist for note bodies) and the roadmap (below).

### Commands

Vault writes are commands of the provider `vault` and go through the `CommandBus` (ADR-0013), with the activity log and undo.

| Command           | What it does                                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `CreateNote`      | Creates a note in a writable folder, named by that folder's pattern. Never overwrites: an existing note is opened instead |
| `AppendToNote`    | Adds text at the end of a note, or at the end of a named section; creates the section when it is absent                   |
| `UpdateNoteBody`  | Replaces the body of a note the owner edited in MoonShine                                                                 |
| `SetNoteProperty` | Sets one frontmatter key that MoonShine owns (list in the vault contract; first: `omnifocus_id`, ADR-0014)                |

There is no delete, rename or move in v1: Obsidian rewrites links on a rename and MoonShine does not.

### Write rules (enforced in the adapter, not in the UI)

1. **Writable folders by role.** The owner names folders in Settings: daily notes, weekly notes, project notes, inbox. `CreateNote` works only there. A note elsewhere changes only through an explicit action of the owner on that note.
2. **Precondition.** Every write to an existing file carries the hash of the content it was based on. On a mismatch nothing is written and the owner sees both versions.
3. **Atomic replace.** No partly written file is ever visible to Obsidian or to sync.
4. **Byte fidelity.** A write changes only the span it means to change. Frontmatter is never re-serialised; unknown syntax, line endings and the final newline are preserved. `SetNoteProperty` edits one line.
5. **Undo.** The previous content is kept in a local version store outside the vault for 30 days. Undo is a write with a precondition.
6. **Path safety.** The resolved path stays inside the vault root; symbolic links are not followed (the reader's checks, vault contract §3).
7. **Nothing is executed.** Template code, Dataview queries and embedded scripts are text.
8. **The text a command adds** travels in the command, in an encrypted field, and is pruned 30 days after the command finished. The index still stores no body text (ADR-0014).

### Where a write runs

The Mac writes. A vault command created on the iPad or iPhone is queued and executed by the Mac under the once-only rules of ADR-0013; an append found `executing` after a restart is resolved by comparing the note with the recorded result, never by running it again blindly. The entry is visible at once on every device as a pending journal entry, shown from the command itself.

Writing directly on a satellite that holds a copy of the vault is decided in the 3b spec, after a spike (More Information).

### Journal and rituals

- **The journal is the daily and weekly notes Obsidian already uses.** Their folder and file-name pattern are read from Obsidian's own settings in the vault when present, otherwise set in MoonShine. This is the one exception to "hidden folders are not read" (vault contract §3): the named settings files only, and from them only the folder, the pattern and the template path. Date tokens are a documented subset; with an unsupported pattern the role is switched off with a message. MoonShine never guesses a file name.
- **`Ritual`** is a native, synced record: name, moment (`morning` · `evening` · `weekly` · `manual`), optional line or project, the path of a template file in the vault, the target (the daily note, the weekly note, or a new note in a role folder) and a section heading. The template file stays an ordinary Obsidian template; MoonShine adds nothing to it.
- **Running a ritual:** MoonShine renders the template into a draft in the editor, the owner writes, and saving emits `AppendToNote` or `CreateNote`. Nothing is written before the owner saves.
- **Placeholders:** the core Templates set (`{{date}}`, `{{time}}`, `{{title}}`, with formats); a date-and-title subset of Templater; and MoonShine facts — `{{ms:done_today}}`, `{{ms:planned_tomorrow}}`, `{{ms:hours_by_line}}`, `{{ms:week_summary}}` — rendered once as plain Markdown. A fact is a snapshot, not a live query. Any other template code stays as text, and the ritual is marked "contains a script that MoonShine does not run".
- **Entry points:** cards on Today at the ritual's moment; the weekly review; a line or project page for `manual` rituals (a practice review, for example).
- A ritual screen may show the take control; the take follows its own rules and is still never written to the vault.

### Reading and editing

- The Hub slice (ADR-0014) brings a rendered, read-only view of a note. The Write phase adds a plain-text Markdown editor with a preview.
- Rendering tiers:

  | Tier | Syntax                                                                          | Behaviour                                      |
  | ---- | ------------------------------------------------------------------------------- | ---------------------------------------------- |
  | 1    | CommonMark, tables, task lists, wikilinks, tags, frontmatter as a property list | rendered; links navigate inside MoonShine      |
  | 2    | callouts, footnotes, embeds                                                     | rendered when cheap, otherwise shown as source |
  | 3    | Dataview, Templater, other plugin blocks, canvas, math, diagrams                | shown as source, never run                     |

- Every note has "Open in Obsidian".
- No live preview, no attachments in v1.

### The assistant and notes

- **Allowlist.** The assistant's read tools return note bodies only from folders the owner listed in Settings → Assistant. The list starts empty; the standing context pack of ADR-0013 is unchanged. A note with `moonshine_ai: false` is excluded even inside a listed folder. Journal folders are never pre-selected.
- **Note bodies are untrusted.** A request over notes ("turn the draft plan in this project's note into tasks") always produces a `Proposal` of the `confirm` class, never an `auto` command.
- **`AppendJournal`** joins the `auto` class as soon as the Write and Ask phases both exist: the owner's dictated words are appended to today's daily note under the configured section. The conditions of ADR-0013 hold: the text is the utterance itself, the app resolves the target, the change can be undone, the answer is one line. It is the only provider command that is `auto` before the Act phase. From a satellite it is queued for the Mac and answered as queued.

### Roadmap

| Phase           | Change                                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| Hub slice       | New, after R1 and before Board: project page with the rendered note and mentions (ADR-0014)                     |
| **Write** (new) | After Board, before 3b; 2–3 weekends: vault commands, journal, rituals, the editor, creating a project note     |
| 3b              | The iPad and iPhone are designed with the journal from the start                                                |
| Ask             | Adds: a project's notes as a source for plan and task proposals; `AppendJournal` by voice; the allowlist        |
| Act             | Loses "Obsidian note create/append"; keeps publishing the active scenario to the budget note, on the Write path |
| Own             | Keeps native tasks only. A fuller editor is reconsidered only if the owner leaves Obsidian                      |

### Consequences

- Good — the journal and the review rituals are one action away and arrive with the day's facts filled in.
- Good — both tools address the same files; nothing changes for Obsidian or Obsidian Sync.
- Good — every write is logged and can be undone; nothing from the vault is executed.
- Bad — two programs write the same files. A note with unsaved edits in Obsidian can still collide; the precondition turns that into a visible conflict instead of a loss, but the owner has to resolve it.
- Bad — a vault change made on the phone waits for the Mac, and reaches Obsidian on other devices only once Obsidian has synced on the Mac.
- Bad — templates with scripts do not work as rituals; the owner rewrites the ones he wants.
- Bad — a subset of date patterns and a subset of the rendering: some notes will look poorer than in Obsidian.
- Bad — the text of a pending entry passes through CloudKit inside its command (the owner's private database, encrypted field, pruned).
- Bad — the Write phase puts 2–3 weekends between Board and the iPad.
- Neutral — a `VaultWriter` port in Core; the file implementation is part of the `ObsidianAdapter` (ADR-0001).

### Confirmation

- Adapter tests on a temporary vault: a precondition mismatch writes nothing; `CreateNote` never overwrites; a create outside a role folder is refused; a path through a symbolic link or `..` is refused; after an edit the file is identical outside the edited span (fixtures with CRLF, no final newline, unknown syntax); a body edit leaves the frontmatter bytes unchanged; undo restores the exact bytes; a template with a script is not executed and is flagged.
- CI: a CI check that fails on file-writing calls in the Obsidian adapter (added in S3b-3; from the Write phase on, allowed only inside `VaultWriter`).
- Core tests: a read tool returns no body from a folder outside the allowlist or from a note with `moonshine_ai: false`; a proposal built from a note is never `auto`; the text of `AppendJournal` equals the capture text.
- The queue contract tests of ADR-0013 are extended to vault commands.
- Write-phase acceptance: one week of the owner's real morning and evening rituals, with Obsidian open on the same vault, and no edit overwritten.

## Pros and Cons of the Options

### 2. Own notes store, exported to the vault

- Good — full control of concurrency and sync.
- Bad — two copies of every note; the vault stops being the truth; leaving MoonShine becomes a migration, which ADR-0004 set out to avoid.

### 3. Full Obsidian-compatible editor

- Good — one tool for everything.
- Bad — months of work on a part that already works for the owner; plugin syntax can never be matched without running plugin code.

### 4. Writing through Obsidian's URL scheme

- Good — MoonShine never touches a file; Obsidian resolves its own conflicts.
- Bad — Obsidian must be running and comes to the front on every write; no result is returned, so no reliable undo or "done"; text length is limited by the URL.

### 5. Stay read-only

- Good — no risk to the vault.
- Bad — the rituals stay unused; the assistant cannot file a dictated entry; the project hub can show notes but not start one.

## More Information

Spikes before the Write phase spec. None of these has been checked yet:

1. An atomic replace next to a running Obsidian: does Obsidian reload the note, and does Obsidian Sync ever produce a conflict copy?
2. The names and format of Obsidian's settings files for daily and periodic notes.
3. For 3b: can the iOS app keep access to the vault folder inside Obsidian's container, and how stale is that copy when Obsidian is not opened?
4. A count of the constructs used in the owner's templates (constructs only, no content), to size the placeholder subset.

Follow-ups: attachments; rename and move with link rewriting; a per-ritual setting for light clean-up of dictated text.
