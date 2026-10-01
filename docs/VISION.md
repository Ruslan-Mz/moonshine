# MoonShine — Vision

> Working name. One app to **see, ask about and eventually run** everything I plan and do — from today's next action to a lifetime horizon — so that plans actually get done.

## Who it is for

1. **Me first:** a polymath with ~20 development lines (music, languages, math, AI/ML, research, body, family, work) whose goals live in Obsidian and whose execution lives in OmniFocus.
2. **Later, maybe:** people with the same or a similar stack. Decided by audience signal, not by hope (see Roadmap gates).
3. **Always:** a showcase of agent-driven engineering with measurements.

## Jobs to be done

| #   | Job                                          | Example                                                                                                               |
| --- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| J1  | **See** everything in one place at any scale | "What's on today / this week / this month; where am I on the year's artifacts; how does this decade look?"            |
| J2  | **Know if I'm really progressing**           | "At my actual pace, when will I master this partita / reach 20 pull-ups / finish this course? Is that date drifting?" |
| J2b | **Plan across lines**                        | "If violin goes to max and Italian to min, what fits by June, and how many hours a week does that take?"              |
| J3  | **Ask** an assistant about my system         | "Summarise last month", "Which lines were quiet?", "Where is my note on X?", "Check my Q4 plan against my budget"     |
| J4  | **Act** without switching apps               | "Create these three tasks", "Complete X", "Move the violin milestone", "Draft next month's plan note"                 |
| J5  | **Bring in data**                            | Import my hours tracker (Excel), map columns with AI help                                                             |

## Product principles

1. **Own the model, adapt the tools.** MoonShine has its own domain model and UI. OmniFocus, Obsidian, Claude, Excel are _adapters_ that can be swapped or replaced by native modules later.
2. **One timeline, semantic zoom.** Day → week → month → quarter → year → 5/10/25 years → lifetime (any configured length) is one continuous zoom, not seven screens. What is shown adapts to the zoom level (tasks → projects → artifacts → horizons).
3. **Honest, never punishing.** Drift and quiet lines are shown as facts with a suggested next step. No red, no "failed/overdue" language for intentions. Real deadlines (external consequences) are the only urgent colour.
4. **The assistant proposes, I confirm.** Every AI write is a visible, reversible command.
5. **Local-first and private by default.** Works offline; no server needed for a single user; data never leaves my devices and my private iCloud unless I turn on sync or choose a cloud AI provider. Sync is opt-in and off by default (ADR-0010).
6. **Fast and keyboard-first on Mac,** touch-first on iOS later.

## Signature features (what makes it more than a dashboard)

- **Forecast for any project, with drift history.** A project has a plan of steps (a piece, a calisthenics progression, a course, a textbook), each with its own kind of progress (hours, sessions, quantity, a measurable target) and physical limits (recovery, adaptation). The app simulates when each step and the goal will be reached — as a range, not a promise — and **records each week's forecast**, so you see the date slide when effort slips and return when it resumes (ADR-0006).
- **Effort levels and a planning board.** Every project has min / normal / max weekly effort. One board shows all chosen projects competing for the week: move levels and sliders, see finish dates and weekly load update live, compare scenarios, or pin a target date and get the effort it needs.
- **Horizon-aware overview.** Every task can be traced up to its project → artifact → year → long horizon ("one thread, one name").
- **Assistant with real tools** over the same domain API the UI uses; also exposed as an **MCP server**, so Claude Desktop/Code can work with MoonShine data.

## Explicit non-goals (until a roadmap gate says otherwise)

Team collaboration, accounts, own sync server, App Store release, monetisation, Android, web app.
