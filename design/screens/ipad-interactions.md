---
title: iPad — Pencil and pointer interactions
status: draft-2
date: 2026-10-01
artboards:
  [mockups/iPadInteractions.dc.html, mockups/iPadInteractions-Dark.dc.html]
---

# iPad — Pencil and pointer (draft-2)

Direct manipulation only. No handwriting as data in v1 (`platforms.md`).

## States (one panel each on the artboard)

1. **Pointer hover**: the row gets the `hover` fill and the pointer morphs into it (`.hoverEffect(.highlight)`). A truncated trace chip shows the full path as a tooltip (`.help`).
2. **Drag a card**: long-press (touch) or immediate drag (Pencil, pointer) lifts the card: scale 1.04, −2°, lift shadow. The target day gets an accent outline and a drop label. The source leaves a dashed ghost. Drop is a preview until phase 6.
3. **Slider scrub with Pencil**: Pencil **hover** (before contact) shows a value bubble (`2.6 h/week · finish 26 Nov`) and a dashed preview band. Contact commits; the forecast updates live. Pencil double-tap/squeeze returns to `normal`.
4. **Long-press context menu** on a task: preview + `Open in OmniFocus` · `Open in Obsidian` · `Show line · 🎻 Violin` · `Copy link`. No complete or delete in read-only phases. Secondary click with a pointer opens the same menu.

## SwiftUI

`.hoverEffect`, `.onHover`, `.help`; `.draggable` / `.dropDestination` with custom previews; Pencil hover via `.onContinuousHover` + `UIPencilHoverPose` (iPadOS 17.5+) and `.onPencilDoubleTap` / `.onPencilSqueeze`; `.contextMenu(menuItems:preview:)`.

## Acceptance

- [ ] Each state is reachable with finger, Pencil and pointer (where it applies) and has a VoiceOver equivalent (actions rotor).
- [ ] No destructive items in context menus.
