import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { countTests } from "./require-tests.mjs";

const script = new URL("./require-tests.mjs", import.meta.url).pathname;

function run(log) {
  const dir = mkdtempSync(join(tmpdir(), "require-tests-"));
  try {
    const path = join(dir, "test.log");
    writeFileSync(path, log);
    execFileSync("node", [script, path, "Probe"], { stdio: "pipe" });
    return 0;
  } catch (error) {
    return error.status;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const emptyXCTest = [
  "Test Suite 'All tests' started at 2026-10-21 10:00:00.000.",
  "Test Suite 'All tests' passed at 2026-10-21 10:00:00.001.",
  "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds",
].join("\n");

test("adds up every Swift Testing run", () => {
  const log = [
    emptyXCTest,
    "✔ Test run with 13 tests in 3 suites passed after 0.001 seconds.",
    "✔ Test run with 152 tests in 23 suites passed after 0.009 seconds.",
  ].join("\n");
  assert.equal(countTests(log), 165);
});

test("a failed run and a single test still count", () => {
  assert.equal(countTests("✘ Test run with 1 test in 1 suite failed after 0.1 seconds."), 1);
});

test("counts XCTest only at the top-level suite", () => {
  const log = [
    "Test Suite 'All tests' started at 2026-10-21 10:00:00.000.",
    "Test Suite 'Bundle.xctest' started at 2026-10-21 10:00:00.000.",
    "Test Suite 'Bundle.xctest' passed at 2026-10-21 10:00:00.010.",
    "\t Executed 4 tests, with 0 failures (0 unexpected) in 0.010 (0.010) seconds",
    "Test Suite 'All tests' passed at 2026-10-21 10:00:00.011.",
    "\t Executed 4 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds",
  ].join("\n");
  assert.equal(countTests(log), 4);
});

test("a log where nothing ran fails the step", () => {
  assert.equal(run(emptyXCTest), 1);
  assert.equal(run(""), 1);
  assert.equal(run("✔ Test run with 0 tests in 0 suites passed after 0.001 seconds."), 1);
});

test("a log with tests passes and a missing log is an error", () => {
  assert.equal(run("✔ Test run with 8 tests in 1 suite passed after 0.1 seconds."), 0);
  assert.equal(
    (() => {
      try {
        execFileSync("node", [script, join(tmpdir(), "no-such-require-tests.log")], {
          stdio: "pipe",
        });
        return 0;
      } catch (error) {
        return error.status;
      }
    })(),
    2,
  );
});
