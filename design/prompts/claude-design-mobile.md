# Claude Design prompt — iPad and iPhone (MoonShine)

Use the **same** Claude Design project (same tokens and components), on a **new page "iPad & iPhone"**. Attach/read: design/platforms.md, principles.md, tokens.md, copy.md, i18n.md, components.md, demo-data.md, screens/week.md, screens/forecast.md, screens/planning-board.md, screens/quarterly-review.md.

---

Design the iPad and iPhone versions of MoonShine (iPadOS 26 / iOS 26, SwiftUI-implementable, system materials, SF Pro, SF Symbols only). Read design/platforms.md first: the **iPad is the planning studio**, the **iPhone is capture & glance**, the Mac is the hub. Same tokens, tone rules (no red; amber only for real due dates; "quiet for 29 days", "paused on purpose"; rhythm and progress never summed) and demo data (design/demo-data.md incl. draft-2 additions). Light and dark for every artboard.

## iPad (13" landscape 1376×1032 pt unless stated)

1. **Shell**: sidebar (Today, Week, Month, Lines, Plan; lines grouped by tier) + content; collapsible sidebar; toolbar with search (⌘K works with a keyboard).
2. **Week — planning**: 7 day columns + No plan tray, touch-sized cards; drag a card from the tray onto a day (show the drag state; caption "writes to OmniFocus in the Act phase"). Weekly review mode as on Mac, adapted to touch (the three-column panel becomes swipeable cards in portrait).
3. **Project forecast** (Bach Partita — Allemande): steps, p10–p90 band with p50, drift chart; effort level segmented control min/normal/max and a large slider — drag with finger or Pencil, the band updates live.
4. **Planning board**: rows of projects with level controls and finish bands on a shared 12-month timeline; stacked weekly load vs capacity on top; pinch to zoom the timeline; "Doesn't fit by 4 h/week — Italian and Math would move." as a neutral fact.
5. **Quarterly review** (Q3 → Q4): adapted from the Mac screen to a scrolling iPad layout; the quarter note in a side panel that becomes a sheet in portrait.
6. **Split View with OmniFocus**: MoonShine at ½ and at ⅓ width next to a grey placeholder labelled "OmniFocus" — show which screens still work at compact width (Today list, Week as a vertical day list, Forecast summary).
7. **iPad 11" portrait (834×1210)**: Today and Week, to prove the compact-regular layout.
8. **Pencil & pointer details**: one artboard of interaction states (hover, drag, slider scrub with Pencil, long-press context menu: Open in OmniFocus / Open in Obsidian).

## iPhone (6.3", 402×874 pt)

9. **Today**: anchors strip (`3 of 5`), Top 3, then line sections; due badges; tab bar (Today · Week · Lines · Log).
10. **Quick log**: one-hand sheet — pick line (recent first), minutes stepper/chips (10/15/20/30/45/60), optional note, Save; also a **practice timer** (start/pause/stop) that saves a time entry.
11. **Practice timer Live Activity** (Lock Screen + Dynamic Island compact/expanded): `🎻 Violin · 18:42`, pause/stop.
12. **Widgets**: small (anchors 3 of 5), medium (Top 3 + next real due), Lock Screen circular (anchors ring without a percentage — show "3/5" as text).
13. **Line glance**: one line's rhythm and progress (8 weeks), last activity, suggested next step.

## Also

- One artboard per device in **Russian** (iPad Week, iPhone Today) and one iPad Today with **mixed-language task titles** (RU, IT, DE, ZH, HE) to check glyphs, bidi and truncation.
- Accessibility: show Today on iPhone at Dynamic Type XXL.
- Write the specs as markdown like the Mac ones: design/screens/ipad-_.md and design/screens/iphone-_.md, each with Layout, Data, Behaviour, SwiftUI, Acceptance. Add an "iPad & iPhone" section to design/README.md listing artboards and open questions.
