---
title: "0009 — Localization and multilingual content: String Catalogs, values-not-strings in Core, in-app language switch, RTL/CJK-ready"
status: proposed
date: 2026-10-01
deciders: Ruslan Mozhaev
consulted: Claude
informed:
tags: [adr]
supersedes:
superseded-by:
related:
  - "[[0001-own-domain-model-with-ports-and-adapters]]"
  - "[[i18n]]"
---

# 0009 — Localization and multilingual content: String Catalogs, values-not-strings in Core, in-app language switch, RTL/CJK-ready

## Context and Problem Statement

The owner works in Russian, English and Latvian, studies Italian and German, and plans 13 languages including Chinese, Japanese, Greek, Hebrew and Arabic; his tasks and notes are already written in several languages at once. The UI must be switchable inside the app; user data must be rendered, searched and sorted correctly in any script and never translated. Plural rules range from 2 forms (EN) to 6 (AR); Hebrew and Arabic need right-to-left layout. **How do we localise the UI and handle multilingual content without retrofitting every view later?**

## Decision Drivers

- Switching language inside the app (owner requirement).
- Correct plurals and date/number formatting per language.
- Tone rules (banned words) enforceable in every language.
- No rework of Core when a language is added.
- RTL and CJK must work for both UI and content.
- Search must work across scripts.

## Considered Options

1. English only now, localise later.
2. **String Catalog (`Localizable.xcstrings`) from the first view; Core returns values, never display text; app-level language override (stored choice + relaunch), with macOS per-app language as the underlying mechanism.**
3. Live in-app switch via a custom bundle/locale injection at runtime.

## Decision Outcome

**Chosen option: "2"**, extended with: a `LanguageDetector` port (NaturalLanguage adapter on macOS) for per-item content language; SwiftUI layout that mirrors for RTL; per-text language attributes and Unicode bidi isolation for mixed-script rows; SQLite FTS5 `trigram` search (script-agnostic). UI languages ship in waves (EN+RU in phase 1; LV/IT/DE next; others on demand) — see `design/i18n.md`. Chosen because it costs almost nothing when started with the first view (S4), gives correct plurals and formatting from Apple's tooling, and keeps Core language-agnostic. A live switch (option 3) is evaluated in a short S4 spike; if SwiftUI resolves catalog strings from the environment locale reliably, the relaunch is dropped — recorded as an amendment, not a new architecture.

### Consequences

- Good — RU from day one; adding any language, including RTL and CJK, is a translation task, not code.
- Good — mixed-language task lists render correctly (glyph variants, bidi) and are searchable in any script.
- Good — Core stays testable with values (`quietDays: 29`), and the assistant (phase 4) gets structured data, not prose.
- Bad — every view must use catalog keys; reviews must catch literals.
- Bad — a relaunch on language change (until the spike proves otherwise).
- Neutral — ISO weeks stay ISO in every language (product rule).

### Confirmation

- CI: a check that fails on string literals in SwiftUI `Text`/`Label`/`Button` initialisers outside previews (simple grep/lint rule), and a banned-words grep over the catalog in EN and RU.
- S4/S5 acceptance includes Russian at 1440×900 and 1100×700, the double-length and right-to-left pseudolanguages, and a fixture with mixed-script task titles (RU, IT, ZH, HE).
- CI: plural categories present for every shipped language; banned-word grep per language (`design/tone-glossary.md`).

## Pros and Cons of the Options

### 1. English only

- Good — fastest now. Bad — retrofitting every view and Core-generated strings later; owner requirement unmet.

### 3. Live runtime switch

- Good — no relaunch. Bad — relies on bundle tricks or behaviour that may differ across OS versions; more code to own.
