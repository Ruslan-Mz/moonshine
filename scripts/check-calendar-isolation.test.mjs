// The second-file case of the calendar write check (ADR-0012, PR #25 round 1): a file that does
// not import EventKit must not reach the event store through members. `check-vault-writes.mjs`
// stops a second file from importing EventKit or naming an `EK…` type; the compiler stops the
// rest, with `MemberImportVisibility` on the CalendarAdapter target.
// macOS only (needs `xcrun swiftc` and the EventKit SDK); CI runs it in the Swift job.
// Run: node --test scripts/check-calendar-isolation.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const onMac = process.platform === "darwin";

/// Type-checks two files: one owns an event store, the other calls a write on it without
/// importing EventKit. Never runs anything.
function typecheck(flags) {
  const dir = mkdtempSync(join(tmpdir(), "calendar-isolation-"));
  writeFileSync(
    join(dir, "Store.swift"),
    "@preconcurrency import EventKit\nfinal class Store: @unchecked Sendable { let store = EKEventStore() }\n",
  );
  writeFileSync(
    join(dir, "Second.swift"),
    "import Foundation\nextension Store { func write() throws { try store.commit() } }\n",
  );
  return spawnSync(
    "xcrun",
    ["swiftc", "-typecheck", "-swift-version", "6", ...flags, join(dir, "Store.swift"), join(dir, "Second.swift")],
    { encoding: "utf8" },
  );
}

test("the CalendarAdapter target enables MemberImportVisibility", () => {
  const manifest = readFileSync(join(repository, "Adapters/Package.swift"), "utf8");
  // The target, not the library product: from its `name:` line to the next target.
  const start = manifest.search(/\.target\(\s*name: "CalendarAdapter",/);
  assert.ok(start >= 0, "no CalendarAdapter target");
  const rest = manifest.slice(start + 1);
  const next = rest.search(/\.(target|executableTarget|testTarget)\(/);
  assert.match(rest.slice(0, next < 0 ? rest.length : next), /enableUpcomingFeature\("MemberImportVisibility"\)/);
});

test("with MemberImportVisibility a second file cannot call the store", { skip: !onMac }, () => {
  const open = typecheck([]);
  assert.equal(open.status, 0, `the probe must see the hole without the feature:\n${open.stderr}`);
  const closed = typecheck(["-enable-upcoming-feature", "MemberImportVisibility"]);
  assert.notEqual(closed.status, 0, "a file without `import EventKit` called the store");
  assert.match(closed.stderr, /EventKit/);
});
