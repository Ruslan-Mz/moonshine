---
title: Line detail
status: draft-1
date: 2026-10-01
slice: S4
artboards: [mockups/LineDetail.dc.html, mockups/LineDetail-Dark.dc.html]
---

# Line detail (draft-1)

Example: 🎻 Violin.

## Layout

Toolbar: breadcrumb `Lines › 🎻 Violin`, subtitle `Line detail · 4 projects · 9 next actions`, button "Open in OmniFocus" (opens the line's folder or tag perspective if possible, else the first project).

Main (scroll):

1. Header: emoji 34, name 24 bold, meta line `Creative · active · budget 6 hours / week · last activity today`.
2. Two `MetricCard`s side by side: **Rhythm** (sessions per week, 4-week avg 5.5) and **Progress** (tasks done per week, avg 1.3), W33–W40, current week partial.
3. **Projects** table: Project (folder symbol + name + due badge if the project has a real due) · Kind (`plan · 4 steps`, `repeating sessions`, `one-off tasks`) · Next actions · Remaining (`≈ 2 h 15 min est.`).
4. **Next actions** (count): `TaskRow`s; the When column shows `today` / `Fri` / `no date`, or a due badge.

Inspector 360:

- **Parent artifact** card: label, title 17 bold, description, Horizon / Target / Note path grid, button "Open in Obsidian".
- **Last 10 completions**: date (`Today`, `Wed 30 Sep`) · title · tag (`session` rhythm colour / `task` progress colour).

## Data

Line detail model (moved to S4 in the phase-1 spec): parent artifact (NoteRef), projects, next actions, last 10 completions, weekly rhythm and progress for 8 weeks plus the 4-week means.

## Acceptance

- [ ] Two separate charts; the average is a dashed rule, not a third series.
- [ ] "Open in Obsidian" uses `obsidian://open?vault=…&file=…`.
- [ ] The kind "plan · 4 steps" appears only once plans exist (phase 2); in phase 1 show `one-off tasks` / `repeating sessions`.
