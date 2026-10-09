# Architecture Decision Records

| #                                                                             | Decision                                                                                              | Status   |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | -------- |
| [0001](0001-own-domain-model-with-ports-and-adapters.md)                      | Own domain model with ports and adapters                                                              | proposed |
| [0002](0002-sqlite-engine-document-attributes-change-log.md)                  | SQLite (GRDB) as the engine, document-style attributes, append-only change log                        | proposed |
| [0003](0003-omnifocus-adapter-jxa-now-plugin-export-for-sandbox.md)           | OmniFocus adapter: JXA bridge now, plug-in export for sandboxed builds                                | proposed |
| [0004](0004-obsidian-adapter-and-notes-stay-markdown-files.md)                | Obsidian adapter; lines in frontmatter; notes stay markdown files                                     | proposed |
| [0005](0005-assistant-tools-over-domain-proposals-and-mcp.md)                 | Assistant: provider-agnostic, typed tools over the domain, write-as-proposal, exposed via MCP         | proposed |
| [0006](0006-plan-model-steps-effort-levels-simulated-forecast.md)             | Plan model: step plans, effort levels and a simulated, adaptive forecast                              | proposed |
| [0007](0007-native-swift-macos-first-multiplatform.md)                        | Native Swift, macOS first, SwiftUI multiplatform                                                      | proposed |
| [0008](0008-license-and-distribution.md)                                      | License and distribution: AGPL-3.0 with sole copyright; direct distribution now, App Store later      | proposed |
| [0009](0009-localization-string-catalogs-and-in-app-language.md)              | Localization: String Catalogs, values-not-strings in Core, in-app language switch                     | proposed |
| [0010](0010-cloudkit-sync-mac-hub-satellite-devices.md)                       | Sync for iPad/iPhone: CloudKit private database, Mac as the only importer, native data multi-writer   | proposed |
| [0011](0011-change-driven-import-full-snapshots-on-omnifocus-deactivation.md) | Change-driven import: full snapshots through the bridge, triggered when OmniFocus resigns active      | proposed |
| [0012](0012-calendar-eventkit-read-only-per-device.md)                        | Calendar: EventKit read-only on each device; events are never stored or synced                        | proposed |
| [0013](0013-captures-proposals-command-queue-autonomy.md)                     | Voice captures, proposals and a command queue; autonomy levels for the assistant                      | proposed |
| [0014](0014-project-hub-bindings-in-project-note-and-link-index.md)           | Project as a hub: bindings declared in the project note, and a link index over note bodies            | proposed |
| [0015](0015-vault-writes-narrow-command-path-rituals-simple-editor.md)        | Writing to the vault: a narrow command path, rituals over Obsidian templates, a simple editor         | proposed |
| [0016](0016-time-tracking-interval-entries-one-timer-sources-reconciled.md)   | Time tracking: one running timer, interval entries, nudges as facts, Excel reconciled by day and line | proposed |

Accepted ADRs are immutable; changes go into a new ADR that supersedes the old one.
