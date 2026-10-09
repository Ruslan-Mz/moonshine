---
title: Platforms — Mac, iPad, iPhone
status: draft-2
date: 2026-10-01
---

# Platforms (draft-2)

One product, three roles. The owner plans on the iPad (OmniFocus is great for doing, poor for planning), works on the Mac, captures on the iPhone.

|                            | Mac                                                    | iPad                                                                                         | iPhone                                                                |
| -------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **Role**                   | Hub: imports (OmniFocus JXA, vault, Excel), everything | **Planning studio**: Week & weekly review, Forecast, Planning board, Quarterly review, Lines | **Capture & glance**: Today, anchors, quick time log / practice timer |
| Input                      | Keyboard first                                         | Touch + Pencil + Magic Keyboard (all shortcuts work)                                         | One hand                                                              |
| Typical context            | Desk, deep work                                        | Sofa, Sunday review, side by side with OmniFocus                                             | Between things, during practice                                       |
| Writes (when phases allow) | All                                                    | MoonShine-native planning data (plans, levels, scenarios, review "seen")                     | Time entries, measurements                                            |

## Architecture consequence (ADR-0010)

- The **Mac stays the importer** (JXA exists only on macOS). The iPad and iPhone read a **replicated MoonShine store** and write only MoonShine-native data. Decided in **ADR-0010**: CloudKit private database via `CKSyncEngine`; provider-sourced records have one writer (the Mac importer), native records are multi-writer with per-field last-writer-wins and a conflict log. Sync is **opt-in, off by default**, turned on in Settings after explicit consent (VISION principle 5).
- Core and Adapters are already multiplatform Swift packages (ADR-0007); the iPad app reuses them.

## Design rules for iPad and iPhone

- Same tokens, tone rules and copy as Mac (`principles.md`, `copy.md`, `i18n.md`). No red; amber only for real due dates.
- Touch targets ≥ 44 pt; Dynamic Type supported up to XXL without clipping; VoiceOver labels for every chart (values read as text).
- iPad: size classes regular/compact; layouts must work full screen, in Split View next to OmniFocus (½ and ⅓) and in Stage Manager windows. Hardware keyboard shortcuts identical to Mac; pointer hover states.
- Pencil: direct manipulation only (drag a forecast level, scrub a timeline, circle to select); no handwriting-as-data in v1.
- iPhone: bottom tab bar; glanceable; a Home/Lock Screen widget; a practice timer as a Live Activity whose session becomes time entries, one per interval (ADR-0016).

## When

Design now (cheap; keeps components touch-ready). Build after phase 3 (Board), when there is planning worth taking to the iPad — see the roadmap decision.
