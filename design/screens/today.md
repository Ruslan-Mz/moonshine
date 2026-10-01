---
title: Today
status: draft-2
date: 2026-10-01
slice: S4
artboards: [mockups/Today.dc.html, mockups/Today-Dark.dc.html]
---

# Today (draft-2)

## Layout

Sidebar (Today selected) · toolbar: title "Today", subtitle `Thursday, 1 October · Week 40 · 22 open · 3 done · ≈ 10 h 15 min est.` · main table · right rail 300 · status bar.

Main, top to bottom: 0. **Draft-2 — Anchors strip** (40): `Anchors · 3 of 5 done`, then up to 5 compact chips (checkbox + short title + line emoji) for today's tasks tagged `anchor`. Done chips are checked and dimmed, not hidden. Absent if no anchors.
0b. **Draft-2 — Top 3 today**: flagged tasks, max 3 rows, as normal `TaskRow`s under a section header `Top 3 today`. If more than 3 are flagged: caption `5 flagged — 3 shown` and a "Show all" link. These tasks are **not repeated** in their line sections.

1. Column header (26): blank · Task · Project → Line → Artifact · Estimate · When.
2. One section per line touched by today's tasks, **foundation lines first**, then the vault order. `LineGroupHeader` + `TaskRow`s. Done tasks stay in place (checked, struck through) until the next day.
3. Section **From earlier** (`arrow.uturn.backward`): available tasks whose planned date is before today. The "When" column shows `planned N days ago`. Never amber unless there is a real due date.
4. **Life ops** (🧺): collapsed disclosure with count and estimate; expands to plain rows.

Right rail:

- **Draft-2 — Quarter focus** (top): card `Q4 focus · 2 of 5 done` listing the current quarter's artifacts (status dot neutral / check), each with its line emoji; footer link `Open quarter note`. Source: the quarter note (`scale: quarter`) and its artifacts. Absent if no quarter note.
- **Touched today**: a grid Line | Rhythm | Progress, e.g. `🎻 Violin | 1 session | —`. Rhythm values in `rhythm` colour, progress values in `progress` colour, "—" in tertiary.
- **Quiet lines**: `QuietLineCard`s, then `NoActivityCard`s, then a caption explaining the rule.
- **Paused on purpose**: greyed rows.

## Data (phase-1 spec)

- Included: available tasks with effective planned or defer = today, flagged, or effective due ≤ today.
- Grouping: by mapped line (task tag → project tag → project name → folder → Life ops).
- Urgent styling: only when effective due ≤ today.
- Est. sums: open tasks only.

## Behaviour

- ↑↓ moves the selection, ↵ or double-click opens in OmniFocus (`omnifocus:///task/<id>`), space toggles Quick Look-like details (later).
- Checkbox is **read-only in phase 1**: it shows state and does not write. Clicking it opens in OmniFocus instead.
- Life ops expansion persists (`@SceneStorage`).

## SwiftUI

`NavigationSplitView` → detail: `Table(sections)` with `TableColumn`s (widths: 34 fixed, flex, 290, 100, 118), `.tableStyle(.inset)`, `alternatesRowBackgrounds: false`. Rail: `.inspector(isPresented:)` + `.inspectorColumnWidth(300)`. Header text: `.navigationTitle` / `.navigationSubtitle`.

## Acceptance

- [ ] 25 demo tasks fit at 1440×900 without scrolling, Life ops collapsed.
- [ ] Only the 2 tasks with real due dates show amber.
- [ ] "From earlier" rows show the planned age and no urgency colour.
- [ ] Italian is listed as quiet; Piano (maintenance) is not; Calligraphy appears only under "Paused on purpose".
- [ ] Rhythm and progress are separate columns in the rail.
- [ ] Light and dark both match the artboards.
- [ ] Anchors strip shows only `anchor`-tagged tasks; Top 3 shows at most 3 flagged tasks and they are not duplicated below.
- [ ] Foundation sections come first.
- [ ] Checked in Russian at 1440×900 and 1100×700.
