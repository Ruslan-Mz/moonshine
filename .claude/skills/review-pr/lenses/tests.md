# Lens: tests — would a test fail if this were wrong?

Green tests prove little by themselves. Find the behaviour that no test protects and the tests that pass for the wrong reason.

## Method

1. For each behaviour the PR adds or changes, name the test that fails if the change is reverted. If you cannot, that is a finding.
2. **Mutate in your head.** Pick the three most important lines of the diff. For each: flip the condition, move the boundary by one, remove the guard. Would a test go red? Where it is cheap, check it for real in a copy under the session scratchpad, where probes are written and read.
3. Read each new test as an adversary: what wrong implementation would still pass it?

## Questions

1. **Red first, for the right reason**: the PR and the method log say tests failed before the code existed. Could a test have passed against the stub, or failed only because something did not compile or did not exist?
2. **Rejection tests**: every validation rule has a test with input that must be refused, and the test asserts the kind of error and its content (including that no raw value is in it).
3. **Boundaries**: zero, one, the limit, the limit plus one, empty, the other time zone, the other half of the year, the period boundary.
4. **Behaviour, not implementation**: assertions on results and state, not on call counts or private details, unless the count is the contract (coalescing).
5. **Determinism**: sleeps, wall-clock time, test order, shared files or shared state, the real time zone or locale of the machine.
6. **One suite, every implementation**: contract tests run against each implementation of a port.
7. **Derived numbers**: expected values come from the fixtures or from stated rules, not from a number typed twice.
8. **Fixtures**: invented, minimal, and containing the cases the rules distinguish (maintenance versus active quiet line, own versus inherited date, default versus chosen time).
9. **Concurrency tests**: do they force the interleaving they claim to test, and stay stable when repeated?

## Seen in this repository

- An append-only test passed against the stub because the missing table also threw.
- A fixture's quiet line sat on a maintenance line, so the demo showed no quiet line at all.
- A gated test provider kept only the last continuation and hung against the stub.
- Averages on screens were typed by hand and disagreed with the canonical history; a derivation test was added.
- The first timeout code had no test with a child that ignores SIGTERM. The SIGTERM-only version was verified not to hang with osascript (it exits on SIGTERM); the kill was kept as hardening, and its first test passed even without the kill — it now asserts the child is gone (`kill(pid, 0)` → `ESRCH`).
- Error-sanitising was tested for validation errors but not for decoding errors, where the leak was.
- A daylight-saving comparison had no winter-and-summer test until a reviewer asked.
