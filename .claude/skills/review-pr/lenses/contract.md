# Lens: contract — inputs, validation, API surface

Everything that crosses a boundary (bridge JSON, vault YAML, CLI arguments, files, ports between Core and adapters) must be checked where it enters, and every public API must be valid for every value its types allow.

## Questions

1. **Every decoded field**: is it validated? Required or optional, range, enum membership, cross-field rules. List the fields of each changed document type and tick them off against the validator.
2. **Shape versus value**: does a check test only the shape of a string? Try the smallest wrong value that keeps the shape.
3. **All paths, same rule**: when a rule exists for one document kind, mode or entry point, does every sibling apply it too?
4. **Every public function × every case**: for each enum or mode the signature accepts, is the call meaningful? A combination that can only throw is a defect in the type.
5. **Defaults that hide errors**: where an optional becomes a default (`?? 0`, `?? .zero`, `?? ""`), can "missing" mean "something went wrong"?
6. **Numbers from outside**: zero, negative, very large, non-integer. Ranges such as `1...n`, divisions, array indices, durations.
7. **Identity**: can data from one provider or mode end up in another's id namespace or be merged as if it were complete?
8. **Compatibility**: absent key versus `null`; older OmniFocus versions; an older snapshot version read by newer code.
9. **Stated versus enforced**: for every "must", "never", "only" in the contract documents, find the code that enforces it and the test that proves it.

## Seen in this repository

- A time check `\d{2}:\d{2}` accepted `29:99`.
- A date check looked only for an offset suffix and accepted `not-a-date+03:00`; `Date.ISO8601FormatStyle` rolls `25:61` over instead of failing.
- `source` was validated for change probes but not for normal snapshots, so another source could be imported into the OmniFocus id namespace.
- `document(.probe)` could only throw: the request type allowed a mode the method could not decode.
- A probe was decoded but never passed to the validator on one path (the CLI).
- A missing timing marker was accepted as `nil` and reported as `0 s`.
- `full 0` reached `1...runs` and trapped.
- A partial snapshot could have been committed as a full import, which would soft-delete everything outside the delta.
