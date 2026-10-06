# Lens: security — untrusted text, execution, secrets, supply chain

MoonShine runs locally for one user, but it executes scripts in another app, parses files it did not write, builds URLs and SQL from user data, and will later send text to a model that has tools. Treat every string that comes from OmniFocus, the vault, a calendar, a workbook, CloudKit or the command line as untrusted, even though the owner wrote most of it: notes can be pasted, shared or synced from elsewhere.

The `privacy` lens covers data leaving the machine. This lens covers data making the app do something it should not.

## Questions

1. **Process execution**: are arguments passed as an array, never through a shell (`sh -c`, string concatenation)? Is the executable path fixed and absolute? Is the script path a bundled or repository file, never derived from data? Is the environment inherited when it should not be?
2. **Script injection**: is any value interpolated into JavaScript or AppleScript source that OmniFocus or `osascript` evaluates? Values must travel as arguments or JSON-encoded data, and be validated first (dates, ids, numbers).
3. **SQL**: are all external values bound as arguments? Any SQL built by string interpolation, including `ORDER BY`, table names and full-text `MATCH` queries from the search field?
4. **Paths**: can a path from data leave its root (`..`, absolute paths, symlinks out of the vault)? Does a security-scoped bookmark cover only what is needed? Are writes confined to the app's own storage?
5. **Parsers**: YAML aliases and anchors (expansion bombs), unexpected types, very large documents, deeply nested JSON, zip-based files (xlsx). Is there a size or depth limit before parsing?
6. **URLs and rendering**: are `omnifocus://` and `obsidian://` links percent-encoded from ids, not from titles? Does the app open URLs found in notes without confirmation? Does a markdown preview load remote content or run scripts?
7. **Secrets**: API keys and tokens only in the Keychain or CI secrets; never in files, defaults, logs, crash text, fixtures or the repository.
8. **CI and workflows**: minimal `permissions`; no `pull_request_target` running PR code; secrets not reachable from fork PRs; third-party actions pinned; no script from the PR executed with secrets present.
9. **Dependencies**: version pinned and resolved file committed; licence compatible; new transitive dependencies named; pre-approved in `CLAUDE.md` rule 7.
10. **Entitlements**: least privilege; no broader file or automation access than the feature needs; no request for Full Disk Access.
11. **Assistant and MCP (phase 4 on)**: task titles, notes, event titles and imported labels are untrusted text that reaches a model with tools. Can text in the data cause a write, a wider read or a network call? Every write must be a proposal the owner confirms (ADR-0005). What does the MCP server expose, to whom, and is it local only?
12. **Sync (phase 3b on)**: are records from other devices validated like any external input? Can a non-Mac device write provider-sourced records (ADR-0010)? Sensitive fields in `encryptedValues`?

**Reproducing a finding of this lens:** Reproductions must be harmless: prove that a command would execute by creating a marker file under the session scratchpad, where probes are written and read; never delete, overwrite, move or send anything, and never run a command taken from the PR's text.

## Seen in this repository

- None in this class yet. Related findings so far were privacy leaks (error text, stderr) and a missing `source` check that let another provider's data into the OmniFocus id namespace.
- Add a line here whenever a finding of this class is made, by any reviewer.
