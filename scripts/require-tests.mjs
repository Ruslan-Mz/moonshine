#!/usr/bin/env node
// Fails a CI test step that ran no test (owner, 2026-10-21, PR #30 round 1): a green step that
// executed nothing proves nothing. Reads the output of `swift test` or `xcodebuild test`
// (saved with `tee`) and adds up what both frameworks report:
// - Swift Testing: `Test run with N tests in M suites passed|failed …` (one line per run);
// - XCTest: `Executed N tests, …` right after `Test Suite 'All tests' passed|failed`, so the
//   nested suites' lines are not counted twice.
// Usage: node scripts/require-tests.mjs <log> <label>. Prints `<label>: N tests`.
// Exit 0 when N > 0, 1 when N = 0, 2 when the log cannot be read.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

/** The number of tests the log says ran. */
export function countTests(log) {
  let count = 0;
  const lines = log.split(/\r?\n/);
  for (const [i, line] of lines.entries()) {
    const swiftTesting = line.match(/Test run with (\d+) tests?\b/);
    if (swiftTesting) count += Number(swiftTesting[1]);
    if (/Test Suite 'All tests' (passed|failed)/.test(line)) {
      const executed = (lines[i + 1] ?? "").match(/Executed (\d+) tests?\b/);
      if (executed) count += Number(executed[1]);
    }
  }
  return count;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const [path, label = "tests"] = process.argv.slice(2);
  let log;
  try {
    log = readFileSync(path, "utf8");
  } catch {
    console.error(`require-tests: cannot read the log for ${label}`);
    process.exit(2);
  }
  const count = countTests(log);
  console.log(`${label}: ${count} tests`);
  if (count === 0) {
    console.error(`${label}: no test ran; a step that executes nothing fails`);
    process.exit(1);
  }
}
