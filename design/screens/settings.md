---
title: Settings and status bar
status: draft-2
date: 2026-10-01
slice: S4
artboards: [mockups/Settings.dc.html, mockups/Settings-Dark.dc.html]
---

# Settings + status bar (draft-2)

## Settings

Recommended implementation: a native `Settings` scene (⌘,) with `Form { }.formStyle(.grouped)`. The canvas draws a sheet (580 wide, attached under the toolbar) only to show it in context.

**Data** group

- Source: `Picker(.segmented)` **Demo | Live**.
- Obsidian vault: path field (folder symbol + `~/Documents/Life vault`) + "Choose…" → `.fileImporter(allowedContentTypes: [.folder])` → security-scoped bookmark.
- OmniFocus: status text (`not read in Demo mode` / `last full import 14 s`).
- Caption: "Demo shows bundled sample data — nothing is read from OmniFocus or your vault. The vault is opened read-only through a security-scoped bookmark."

**General** group (draft-2)

- Language: `Picker(.menu)` **System** + every shipped language in its own name (phase 1: English, Русский) (see `i18n.md`, ADR-0009).
- Content languages: an ordered list of the languages the owner writes in (default from macOS preferred languages; e.g. RU, EN, LV, IT, DE) — hints for content-language detection. Changing it shows a confirmation `MoonShine will restart to switch the language.` with Restart / Cancel, unless the S4 spike proves a live switch.
- Caption: "Line names, tasks and notes are shown as they are in OmniFocus and Obsidian."

**Refresh** group

- Refresh every: `Picker(.menu)` 1 / 5 / 15 / 30 minutes.
- Last import: `3 min ago · incremental, 0.8 s` + "Refresh now ⌘R".
- Caption: "Imports run in the background; the window always renders from the local store."

Buttons (sheet variant only): Cancel, Done (default, accent). The Settings scene applies changes immediately.

## Status bar

`.safeAreaInset(edge: .bottom)` HStack, 28 high: "Demo data" capsule (Demo only) · `Updated 3 min ago` (relative, refreshes every minute) · while importing: a small `ProgressView` + `Importing…` (never blocks the UI) · shortcut hints on the right.

## Acceptance

- [ ] Fresh clone runs in Demo mode with no vault and no OmniFocus.
- [ ] Switching to Live without a vault prompts "Choose…", not an error.
- [ ] No write APIs anywhere (phase 1).
- [ ] Language picker switches the whole UI; user data stays untranslated; dates and plurals follow the chosen language.
