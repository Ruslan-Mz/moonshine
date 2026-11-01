// Pins the rules that make .github/workflows/guard.yml safe to run with a secret on pull requests
// (pull_request_target): main's code only, no credentials kept, the deny-list only through the
// `guard` environment, and nothing from the event inside a `run:` line. A pull request cannot
// change the workflow its own guard run uses, so these rules are kept by review and by this test.
// node --test scripts/guard-workflow.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const path = join(dirname(fileURLToPath(import.meta.url)), "..", ".github", "workflows", "guard.yml");
const text = readFileSync(path, "utf8");

/// Each line of the workflow with the chain of mapping keys it sits under (YAML block style, as the
/// workflow is written; comments and blank lines left out).
function lines() {
  const result = [];
  const stack = [];
  for (const raw of text.split("\n")) {
    if (/^\s*(#|$)/.test(raw)) continue;
    const indent = raw.length - raw.trimStart().length;
    while (stack.length > 0 && stack.at(-1).indent >= indent) stack.pop();
    const line = raw.trim();
    const key = /^(?:- )?([A-Za-z_][\w-]*):/.exec(line)?.[1];
    result.push({ line, keys: stack.map((entry) => entry.key), key });
    if (key) stack.push({ indent: indent + (line.startsWith("- ") ? 2 : 0), key });
  }
  return result;
}

const all = lines();
const under = (...keys) => all.filter(({ keys: chain }) => keys.every((key, index) => chain[index] === key));

test("it runs on pull_request_target and on pushes to main only", () => {
  const triggers = all.filter(({ keys }) => keys.length === 1 && keys[0] === "on").map(({ key }) => key);
  assert.deepEqual(triggers, ["pull_request_target", "push"]);
  assert.deepEqual(
    under("on", "push").map(({ line }) => line),
    ["branches: [main]"],
  );
});

test("the only permission is reading contents, for the whole workflow", () => {
  assert.deepEqual(
    under("permissions").map(({ line }) => line),
    ["contents: read"],
  );
  assert.equal(all.filter(({ key }) => key === "permissions").length, 1);
});

test("one job, in the guard environment, with runs never cancelled", () => {
  assert.deepEqual(
    all.filter(({ keys }) => keys.length === 1 && keys[0] === "jobs").map(({ key }) => key),
    ["guard"],
  );
  assert.ok(under("jobs", "guard").some(({ line }) => line === "environment: guard"));
  assert.ok(under("concurrency").some(({ line }) => line === "cancel-in-progress: false"));
});

test("the checkout is main's, pinned by commit, without kept credentials", () => {
  const uses = all.filter(({ key }) => key === "uses");
  assert.equal(uses.length, 1);
  assert.match(uses[0].line, /^- uses: actions\/checkout@[0-9a-f]{40} /);
  const options = all.filter(({ keys }) => keys.at(-1) === "with").map(({ line }) => line);
  assert.ok(options.includes("ref: main"));
  assert.ok(options.includes("persist-credentials: false"));
});

test("values from the event and the secret reach the steps through env only", () => {
  for (const { line, keys } of all) {
    if (!line.includes("${{")) continue;
    const inEnv = keys.at(-1) === "env";
    const allowed = inEnv || keys[0] === "concurrency";
    assert.ok(allowed, `\${{ }} outside env: ${line}`);
  }
  for (const { line, keys } of all) {
    if (/github\.event\.pull_request\.head|secrets\./.test(line)) assert.equal(keys.at(-1), "env", line);
  }
  const secrets = all.filter(({ line }) => line.includes("secrets."));
  assert.deepEqual(
    secrets.map(({ line }) => line),
    ["DENY_LIST: ${{ secrets.DENY_LIST }}"],
  );
});

test("no run line installs or executes anything from the pull request", () => {
  const runs = all.filter(({ key }) => key === "run").map(({ line }) => line);
  assert.ok(runs.length > 0);
  for (const line of runs) {
    assert.ok(!/\bnpm\b|\bnpx\b|checkout|\$\{\{/.test(line), line);
    assert.ok(/^- run: |^run: /.test(line) && !line.endsWith("|"), `one-line run steps only: ${line}`);
  }
});
