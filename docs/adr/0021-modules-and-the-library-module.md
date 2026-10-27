---
title: "0021 — Modules: built-in features over the owner's own note kinds; the Library module first"
status: accepted
date: 2026-10-26
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0014-project-hub-bindings-in-project-note-and-link-index]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
  - "[[0018-memos-rule-bound-notes-on-events-and-tasks]]"
  - "[[0019-practice-lines-nested-lines-measured-by-entries]]"
  - "[[0020-period-quotas-n-times-per-week-or-month]]"
---

# 0021 — Modules: built-in features over the owner's own note kinds; the Library module first

## Context and Problem Statement

The owner keeps whole domains in his vault with their own conventions. For books he has:

- notes with `type: book` or `type: academic_book`, with fields for author, status, start and finish dates, pages, and similar;
- a hand-kept registry note;
- reading tasks in OmniFocus.

For papers he has notes with `type: article` and a `todo / wip / done` status. Today Obsidian queries and manual rules ("at most 7 active") hold this together.

He wants MoonShine to _understand_ such domains: know that a note is a book, treat a book as a project with sub-tasks, show reading regularity per week, and later replace the tags and fields with MoonShine's own records. **How does MoonShine add domain features like this without a plug-in system, without rewriting the owner's notes, and without a new parser for every whim?**

## Decision Drivers

- The owner's own frontmatter (`type`, `status`, …) is the source of truth for these domains. MoonShine adapts to it, not the other way round.
- Nothing from the vault is executed (ADR-0015): no user scripts, no query language.
- Reuse what is decided:
  - the project hub and note bindings (ADR-0014);
  - quotas and their period history (ADR-0020);
  - rituals (ADR-0015);
  - memos (ADR-0018).
- Read-only until the Write phase; no duplicates; failed reads are never shown as empty.

## Considered Options

1. **Built-in modules, defined in code, that recognise the owner's note kinds through an explicit mapping.**
2. User-defined modules: a schema or a script in the vault.
3. Native MoonShine records now.
4. Also parsing the lines of the hand-kept registry note.

## Decision Outcome

**Chosen option: "1"** (owner, 2026-10-26). Option 3 is the later step, after the Write phase. Option 4 is **not taken for now** (owner): a book that is both a note and a registry line would appear twice, and the registry is free text.

### What a module is

A module is a feature set compiled into MoonShine and switched on in Settings. Each module declares:

- **Note kinds:** which values of the owner's own key mark its notes. The defaults come from the owner's templates, and Settings can change them.
- **Fields:** a typed schema. Each field is parsed with its own problem when invalid, never dropped silently.
- **States:**
  - a small canonical set;
  - a mapping from the owner's status values onto it;
  - an unknown value gives a problem, and the item is listed under "Unknown status", never hidden.
- **Relations:**
  - the note's binding to an OmniFocus project or task, with the `omnifocus_id` key of ADR-0014, typed by hand until the Write phase sets it;
  - its line, which comes through that binding (the bound project's line), so there is no new line field.
- **Screens and rules:** lists by state, an entity page (a variant of the hub page), and facts such as counts. A rule is shown as a fact, never enforced.

A module never reads the bodies of its notes, except where its own ADR names a section (none in this one). It never writes to them before the Write phase.

### The Library module

**Note kinds (defaults):**

| Kind    | Owner's key                         |
| ------- | ----------------------------------- |
| Book    | `type: book`, `type: academic_book` |
| Article | `type: article`                     |

**Fields read:**

- `title`;
- `author` or `authors`;
- `status`;
- `started`, `finished`;
- `rating`;
- `category` or `discipline`;
- `pages_total`, `current_page`;
- `source` (articles);
- `omnifocus_id`.

Every other key is ignored.

**Canonical states:** `someday` · `to buy` · `queue` · `reading` · `paused` · `done`.

**Default status mapping:**

| Owner's value    | Canonical |
| ---------------- | --------- |
| `todo`           | queue     |
| `reading`, `wip` | reading   |
| `paused`         | paused    |
| `done`           | done      |
| `someday`        | someday   |
| `buy`            | to buy    |

The mapping is editable in Settings.

**Only notes count** (owner, 2026-10-26). A book that lives only as a line of the registry note is not in the module. The rule the owner adopts: a book he starts reading gets a note from his template.

**Screens:**

- **Library**, in the sidebar: Books and Articles, each grouped by state.
  - Each group shows a count, the books' line emoji, author and title.
  - Done shows the last 20, the rest behind a disclosure.
  - Above the lists sits the fact `Reading: 6 of 7`. The limit is a setting, default 7, from the owner's own rule. Going above it changes no colour to red, and the fact stays a fact.
- **Book page** (a hub page variant):
  - the fields;
  - the bound tasks;
  - **progress**, by what the note is bound to (owner, 2026-10-27), with real counts (ADR-0020), plus `current_page / pages_total` when both are present:
    - a task with a quota: that quota's history in its own period (a monthly quota gives monthly bars), with the quota as a line;
    - a task without a quota: its completions per week;
    - a project: the completions of all its tasks per week, plus the quota line of a quota task inside it if there is one;
  - "Open in Obsidian";
  - later, ritual buttons ("Summary", "Report") that start the owner's templates (ADR-0015).

**Problems:**

| Kind                       | When                                                                                                                                                        |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `libraryStatusUnknown`     | a status with no mapping                                                                                                                                    |
| `libraryFieldInvalid`      | a typed field that does not parse (a date, a page count, a rating)                                                                                          |
| `libraryPagesInconsistent` | `current_page` greater than `pages_total`                                                                                                                   |
| `libraryBindingMissing`    | `omnifocus_id` names no task or project in the snapshot, on a book in state `reading` or `paused`, and the store has never seen that id (owner, 2026-10-27) |

In the UI a problem names its note. Logs carry only the kind and a count (rule 5).

**Read state:**

- When the vault is unavailable, the last known lists are shown with their date, never an empty library.
- A rejected note is listed under its problem, not dropped.
- A finished or set-aside book whose project was completed long ago and has left the snapshot gives no problem: `libraryBindingMissing` is only for books in `reading` or `paused`, and never for an id the store has seen before.
- A note whose frontmatter is not closed within the scanner's 8 KiB gives `frontmatterTooLarge` when those 8 KiB hold a top-level `type:` line naming a note kind of an enabled module (vault contract §6).

### Roadmap

| Phase / slice | Change                                                                                                                                                                                              |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| After Hub     | **Library L1** (risky: parses vault notes): the module frame, note kinds, fields, states, problems, the Library screen. **Library L2** (plain): the book page with progress from the quota history. |
| Write         | Ritual buttons on the book page; MoonShine sets `omnifocus_id` on book notes.                                                                                                                       |
| Later         | Native library records (option 3). Integrations, e.g. Zotero for articles. A named body section (an academic book's chapter checklist) as a progress source.                                        |

### Consequences

- Good:
  - books and papers get a home in MoonShine with no change to the owner's notes or templates;
  - the module mostly composes existing parts (hub, quotas, rituals, memos);
  - the frame is ready for the next module.
- Bad:
  - books kept only as registry lines are invisible until they get a note;
  - the OmniFocus binding is typed by hand until the Write phase;
  - each new module is code, not configuration: a new domain waits for a slice.
- Neutral:
  - a `Module` protocol in Core;
  - the readers in the `ObsidianAdapter`, on the scanner of ADR-0018.

### Confirmation

- **Reader tests on fixtures** (invented titles only):
  - each kind and field is read;
  - each problem kind;
  - an unknown status lists the note under "Unknown status";
  - changing the mapping in Settings moves notes between states;
  - an unbound book has no progress and no problem;
  - a binding to a missing id gives `libraryBindingMissing` on a book in `reading` or `paused`, and nothing on a book in `done`, or for an id the store has seen before.
- **Progress tests:**
  - weeks with 1, 3 and 2 completions against a 2/week quota show 1, 3 and 2 with the quota line;
  - a `1/мес` quota shows monthly bars; a task without a quota shows completions per week;
  - a project binding shows the completions of all its tasks per week, with the quota line of its quota task when it has one;
  - pages progress appears only when both fields are valid.
- **Read-state tests:** an unreadable vault shows the last lists with their date.
- **Privacy:** no title, author or path appears in logs or problem texts sent anywhere.
