# Lens: platform — Apple APIs, OmniFocus automation and tooling claims

Models state APIs with confidence that do not exist, have a different signature, or behave differently. Treat every API named in code, a spec or an ADR as a claim to verify.

## Method

1. List every framework symbol, language feature, automation property, CLI flag and system behaviour that the PR introduces or relies on, in code and in documents.
2. Verify each one. In order of preference: it compiles (`swift build`, or a snippet under the session scratchpad, where probes are written and read); it appears in the SDK interface (`xcrun --show-sdk-path`, then search the `.swiftinterface` or headers); it is in the official documentation (the Context7 tools are allowed). If you cannot verify a claim, report it as unverified with what you tried.
3. Check availability against the deployment targets, and Swift 6 concurrency rules (`Sendable`, actor isolation, `nonisolated`).

## Questions

1. **Exists with this signature?** Parameters, labels, return type, throwing, async.
2. **Does what the text says?** Especially locale, time zone, sorting, formatting, calendar and date APIs.
3. **App-controllable?** Is the behaviour a public API, or a user setting or system mechanism that an app cannot set?
4. **Permissions and sandbox**: Automation (Apple Events), calendars, files of other apps, security-scoped bookmarks, entitlements, usage-description keys. What does the user see, and what happens when access is denied?
5. **OmniFocus / Omni Automation**: does each property and method exist, on which version, and is it read-only? Does a call change OmniFocus' state?
6. **Visibility and packaging**: access levels across SwiftPM packages and targets; resources bundled; script paths.
7. **CI**: does the workflow run what the PR claims (toolchain, steps, caches)? Does a new tool need installing?
8. **Dependencies**: version pinned, licence compatible with AGPL-3.0, pre-approved in `CLAUDE.md` rule 7.

## Seen in this repository

- `localizedStandardCompare` has no locale parameter; it cannot sort in an in-app language.
- "Stored choice + relaunch" does not change String Catalog lookup by itself; per-app language in System Settings is not settable by an app.
- `package` access is not visible across separate SwiftPM packages.
- A domain type named `Task` shadowed Swift Concurrency's `Task`.
- `effectivePlannedDate` exists only from OmniFocus 4.7.1.
- macOS slows a background app's script about 3.4×; listing tasks, not reading properties, is the cost.
- OmniFocus 4 has no SQLite cache to read; its group container needs the "data from other apps" consent.
- `terminate()` sends SIGTERM only.
- `Date.ISO8601FormatStyle` rolls invalid fields over instead of failing.
