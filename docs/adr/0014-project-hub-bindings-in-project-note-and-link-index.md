---
title: "0014 — Project as a hub: bindings declared in the project note, and a link index over note bodies"
status: proposed
date: 2026-10-06
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0001-own-domain-model-with-ports-and-adapters]]"
  - "[[0004-obsidian-adapter-and-notes-stay-markdown-files]]"
  - "[[0010-cloudkit-sync-mac-hub-satellite-devices]]"
  - "[[0015-vault-writes-narrow-command-path-rituals-simple-editor]]"
---

# 0014 — Project as a hub: bindings declared in the project note, and a link index over note bodies

## Context and Problem Statement

The owner wants a project to be one place that ties together its OmniFocus tasks, its plan, its notes in the vault and the journal entries that mention it ("this week I finished project X", with a link he can follow). Today a `Project` is an imported OmniFocus project, a note is a `NoteRef` with frontmatter only, and note bodies are never read (ADR-0004, vault contract). A project that exists only as a draft plan in a note has no entity at all. **Where does the tie between a project, its OmniFocus project and its notes live, and how do mentions in note bodies become navigable without copying the notes into the store?**

## Decision Drivers

- No second source of truth: what a project is and why lives in the vault; OmniFocus holds execution (ADR-0004).
- A binding must survive a rebuilt store and a renamed note.
- A project may exist before it has any OmniFocus task, and without any note (as today).
- Plans, time entries, forecasts and takes hang on the MoonShine project id. A re-binding must not orphan them.
- Journal text is the most sensitive data: it must not be copied into the store or into CloudKit (the one exception is the text of a pending vault command, ADR-0015 write rule 8).
- The vault is untrusted input for the reader (limits in vault contract §3).
- Obsidian keeps working: a link must mean the same thing in both tools.

## Considered Options

1. **The binding is declared in the project note's frontmatter; a link index is built from note bodies (links and tags only).**
2. The binding is stored in MoonShine: a native link table edited in the UI.
3. The binding is a name convention: note name = OmniFocus project name.
4. `Project` stays an OmniFocus project; notes are shown only through `related` frontmatter links.

## Decision Outcome

**Chosen option: "1"**, because it keeps the vault as the only place where a project is described, survives a rebuilt store, lets a project exist before its first task, and gives backlinks without storing any note text.

**This ADR amends the vault contract**: note bodies are read for links and tags only, never for values.

### The project note

A note is a project note when its frontmatter carries the marker and an id:

```yaml
moonshine: project # marker
id: thesis-ch2 # required. slug [a-z0-9-]+, unique among project notes, never renamed
omnifocus_project: "Chapter 2" # optional: the OmniFocus project's name, exact match
omnifocus_id: # optional: the OmniFocus project's id; wins over the name. Written by MoonShine from the Write phase (ADR-0015)
line: research # optional line id; used only while the project has no OmniFocus project
notes: folder # optional: every note in this note's folder and below belongs to the project
status: active # optional, passed through like on other notes
```

Keys are flat on purpose: MoonShine later writes `omnifocus_id` by editing one line, without re-serialising the frontmatter (ADR-0015).

Any other note joins a project with `project: <id>` (one id or a list), or by being linked from the project note.

### One `Project`, several anchors

`Project` keeps its `UUIDv7`. Its anchors:

| Anchor                  | How it is found                                                                    | Count in v1 |
| ----------------------- | ---------------------------------------------------------------------------------- | ----------- |
| OmniFocus project       | `ExternalRef` from the import; bound by `omnifocus_id`, else `omnifocus_project`   | 0..1        |
| Project note            | `ExternalRef` to the note's `id`                                                   | 0..1        |
| Notes of the project    | `project: <id>`; the `notes: folder` rule; links from the project note             | 0..n        |
| Mentions                | any link that resolves to the project note, or a `moonshine://project/<uuid>` link | 0..n        |
| Plan, tasks, time, take | native records and imported tasks, by project id (unchanged)                       | —           |

Rules:

- An OmniFocus project with no note is a `Project`, as today.
- A project note with no OmniFocus binding is a `Project` sourced from the vault. It has no tasks; its line is the note's `line`.
- A project note bound to an OmniFocus project that already is a `Project` attaches to **that** project. The id and its history are kept.
- A note-only project that already has native records (a plan, time entries, takes) and is later bound to an OmniFocus project with its own history gives two projects. They are **never merged automatically**: a banner offers one logged, undoable merge command that the owner confirms.
- Line: from the OmniFocus mapping when the project is bound (precedence in the vault contract §1). When the note's `line` differs, the mapping wins and a banner names both.
- Two project notes with the same `id`, or claiming the same OmniFocus project: banner naming both paths; first by path wins.
- A binding that names an OmniFocus project the import does not contain is a typed problem; the project is shown as note-only.
- **One OmniFocus project per project note in v1.** Grouping several OmniFocus projects under one project is a later decision; it needs merge rules for plans and history.

### The link index

The `ObsidianAdapter` reads note bodies for links and tags only. Bodies are indexed for every note, with or without frontmatter: most journal notes have none.

**Amendment (2026-10-19, owner; ADR-0019).** The link index skips notes with `moonshine: entry` in frontmatter: their bodies are never read, so they yield no links, tags or backlinks. A note whose first 8 KiB hold a top-level `moonshine: entry` line is skipped too when its frontmatter was rejected (the lexical rule of the budget marker).

- Extracted: `[[target]]`, `[[target|alias]]`, `[[target#heading]]`, `![[embed]]`, Markdown links to notes in the vault, `moonshine://` links, inline `#tags`, and wikilinks in any frontmatter value (`parent`, `related`, …).
- Not extracted: anything inside code fences, inline code or `%% comments %%`.
- Stored per link: source note path, target as written (without its anchor and alias), resolved note path or none, kind (`wikilink` · `embed` · `markdown` · `frontmatter` · `moonshine`), line number. **Nothing around the link is stored**: no alias, no anchor, no snippet, no heading, no sentence (owner, 2026-10-09).
- Resolution follows Obsidian: an exact vault-relative path; else the file name without extension, case-insensitive. Several candidates → the shortest path, and the link is flagged ambiguous. Unresolved links are kept. A bare `[[name]]` that matches only a note's `aliases` stays unresolved, as in Obsidian: aliases feed its autocomplete, which inserts `[[Note|Alias]]`.
- Backlinks and mentions are queries over the index.
- The line of context, the alias and the anchor shown with a mention are read from the file at display time, on a device that has the vault. Other devices show the note's title and date.
- Limits: a body larger than 1 MB is not indexed and gives a typed problem; the walk limits of vault contract §3 apply. A note is re-read only when its size or modification time changed.
- The index is provider-sourced data: built on the Mac, synced read-only (ADR-0010). The sync consent text names it.

### Deep links

`moonshine://project/<uuid>` opens the project page; it also works from a note opened in Obsidian. MoonShine opens a note in Obsidian with `obsidian://open`.

### When

| Step                                                  | Where                                     |
| ----------------------------------------------------- | ----------------------------------------- |
| Marker values and keys reserved in the vault contract | now, documents only; no code in phase 1   |
| Reader extension, index, read-only project page       | the **Hub** slice: after R1, before Board |
| Creating a project note, writing `omnifocus_id`       | the Write phase (ADR-0015)                |

The Hub slice is placed after R1 so that the R1 deadline does not depend on it.

### Consequences

- Good — one page per project: tasks, plan, note, notes of the project, mentions.
- Good — a project can exist before its first OmniFocus task, so a draft plan in a note has something to attach to.
- Good — the binding lives in the vault and survives a rebuilt store; Obsidian's own graph stays valid.
- Good — the index puts no note text into the store or CloudKit (a pending vault command carries its own text, ADR-0015 write rule 8).
- Bad — until the Write phase the owner adds two or three frontmatter lines to each project note by hand.
- Bad — a second parser over untrusted text. Wikilink edge cases (escaped pipes in tables, nested brackets) and Obsidian's resolution rules can be mirrored wrongly; fixtures and the ambiguous flag reduce this and do not remove it.
- Bad — a binding by name breaks when the project is renamed in OmniFocus, until `omnifocus_id` is written.
- Bad — one OmniFocus project per note in v1.
- Bad — merging a note-only project into an imported one needs an explicit step from the owner.
- Neutral — `Project` in `docs/ARCHITECTURE.md` gets a second source (the vault); a `Link` record is added.

### Confirmation

- Reader tests on synthetic fixtures: a note without frontmatter has its links indexed; a bare link that matches only an alias stays unresolved; a note binds by id and by name; a duplicate `id` and a doubly claimed OmniFocus project give a banner and a stable winner; a missing OmniFocus project gives the typed problem; links inside code are ignored; an ambiguous link is flagged; an unresolved link is kept; a renamed note keeps its project through `id`.
- Store test: after importing a fixture vault whose bodies contain a sentinel string — in the text, inside an alias and inside an anchor — the sentinel does not occur anywhere in the store file.
- Core tests: binding a note to an existing project keeps the project id; two projects with history are never merged without the command.
- No code path writes to the vault before the Write phase: a CI check (added in S3b-3) that covers every target that can reach the vault — `MoonShineCore`, all of `Adapters/` (the `moonshine-import` CLI included) and `Apps/` once it exists — and fails on any file-writing call outside a short allowlist of files that write MoonShine's own data (the store); from the Write phase `VaultWriter` joins the allowlist.

## Pros and Cons of the Options

### 2. Binding stored in MoonShine

- Good — linked in the UI at once, no frontmatter to type.
- Bad — a second source of truth next to the vault; lost or stale after a rebuilt store; invisible in Obsidian.

### 3. Name convention

- Good — nothing to declare.
- Bad — names are the owner's data and change; two tools must be renamed together; no way to express "no OmniFocus project yet".

### 4. `Project` stays an OmniFocus project

- Good — no new rules.
- Bad — a project cannot exist before its tasks; mentions in the journal stay invisible; the assistant has nothing to attach a draft plan to.

## More Information

- Obsidian's link resolution is mirrored from its documented behaviour. The resolution order, the shortest-path tie-break included, is checked against Obsidian with the Hub slice's fixtures, and against the owner's vault by counts only (resolved / ambiguous / unresolved), never by content.
- Follow-up: several OmniFocus projects under one project; heading and block anchors resolved to positions; rename tracking for notes without an `id`.
