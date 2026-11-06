# Lens: privacy — nothing personal leaves the machine or enters the repository

`CLAUDE.md` rule 5: raw content from the vault, OmniFocus, calendars, `data/` and the data folder `~/Library/Application Support/MoonShine/` (titles, labels, values, names, ids) is never committed, logged or pasted. Aggregates and structure descriptions are allowed. Rule 6: no writes to external tools before their phase (the vault from the Write phase, OmniFocus and calendars from the Act phase).

## Questions

1. **Errors**: does any error type carry a `String` built from input? Follow each `throw` and each `catch`: what text can reach a log, the console, a test failure message or the UI?
   - Foundation errors (`DecodingError`, `CocoaError`, `NSError.localizedDescription`) can quote the payload or a file path.
   - A child process' stderr or stdout passed through unchanged.
   - `String(describing: error)`, `"\(error)"`, `print(error)`, `dump`.
2. **Output**: every `print`, log call and CLI message — counts, timings and JSON paths only?
3. **Tests**: for each new error path, is there a test that plants a secret in the input and asserts that it is absent from the error? Do test failure messages print payloads?
4. **Documents and fixtures**: any real title, label, name, id, personal date range, exact count that identifies real data, absolute path containing a user name? Fixtures and demo data must be invented.
5. **Network and sync**: any new outbound request, upload or SDK that phones home? Sync must be opt-in and off by default (ADR-0010). Calendar events must not be stored or synced (ADR-0012).
6. **External writes**: any OmniFocus, vault or EventKit write API, including "Save As" or export that changes the other app's state?
7. **Files on disk**: does anything with real data land outside `data/` (git-ignored) and the data folder `~/Library/Application Support/MoonShine/` (S4-4c-1)? Temporary files removed?
8. **Access**: does the change read another app's private files or need a broader permission than the feature needs?

## Seen in this repository

- Contract violations carried ids and dates; `badValue` carried the raw value.
- A Foundation `DecodingError` was passed through; its text quotes an oversized number verbatim.
- `BridgeError.failed` kept up to 500 characters of raw osascript stderr.
- The Excel contract described the real workbook (month range, layout change dates, exact counts).
- CloudKit sync was introduced while VISION promised that data never leaves the device.
- Running the bridge script directly would have put real titles into the agent's context; only the count-printing tool may be run.
- A path check against a name or a folder must ignore case and Unicode form on macOS: APFS ignores case, and realpath keeps the case as typed (`DATA/x` passed a check for `data/`).
