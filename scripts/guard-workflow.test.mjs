// Pins the rules that make .github/workflows/guard.yml safe to run with a secret on pull requests
// (pull_request_target): main's code only, no credentials kept, the deny-list only through the
// `guard` environment, nothing from the event inside a `run:` line, the PR's text never in `env:`
// (the runner prints it in the public log), and no concurrency group. A pull request cannot
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
    // Any spacing after a list dash: `-   run:` is a step too.
    const dash = /^-\s+/.exec(line)?.[0] ?? "";
    const key = /^([A-Za-z_][\w-]*):/.exec(line.slice(dash.length))?.[1];
    result.push({ line, keys: stack.map((entry) => entry.key), key });
    if (key) stack.push({ indent: indent + dash.length, key });
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

test("one job, in the guard environment, with no concurrency group, so no run is cancelled", () => {
  assert.deepEqual(
    all.filter(({ keys }) => keys.length === 1 && keys[0] === "jobs").map(({ key }) => key),
    ["guard"],
  );
  assert.ok(under("jobs", "guard").some(({ line }) => line === "environment: guard"));
  // A group keeps one pending run and cancels it when a newer one arrives, whatever
  // cancel-in-progress says, so any group can leave a range of main unscanned.
  assert.ok(!all.some(({ key, line }) => key === "concurrency" || /\bconcurrency\b/.test(line)));
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
    assert.ok(inEnv, `\${{ }} outside env: ${line}`);
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

test("the PR's branch name, title and body never reach env, whose values the log prints", () => {
  // Every env line pinned whole, key and value: no other expression can put the PR's text there.
  assert.deepEqual(
    all.filter(({ keys }) => keys.at(-1) === "env").map(({ line }) => line),
    [
      "PR: ${{ github.event.pull_request.number }}",
      "EVENT: ${{ github.event_name }}",
      "BASE: refs/remotes/origin/main",
      "HEAD: ${{ github.event.pull_request.head.sha }}",
      "HEAD_REPO: ${{ github.event.pull_request.head.repo.full_name }}",
      "REPOSITORY: ${{ github.repository }}",
      "BEFORE: ${{ github.event.before }}",
      "AFTER: ${{ github.event.after }}",
      "DENY_LIST: ${{ secrets.DENY_LIST }}",
    ],
  );
  assert.ok(!/head_ref|toJSON\(|PR_TITLE|PR_BODY|HEAD_REF/i.test(text));
});

test("every line of the steps has a known key, so no step escapes the pins", () => {
  // A quoted key, a flow mapping or an unknown key would hide a step from the parser above.
  const known = {
    steps: ["name", "if", "env", "run", "uses", "with"],
    with: ["ref", "persist-credentials", "fetch-depth"],
    env: ["PR", "EVENT", "BASE", "HEAD", "HEAD_REPO", "REPOSITORY", "BEFORE", "AFTER", "DENY_LIST"],
  };
  const steps = under("jobs", "guard", "steps");
  assert.ok(steps.length > 0);
  for (const { line, keys, key } of steps) {
    assert.ok(key, `a line the parser cannot key: ${line}`);
    assert.ok(known[keys.at(-1)]?.includes(key), `unknown key under ${keys.at(-1)}: ${line}`);
  }
});

test("the run lines are exactly the fetch as data and main's scan, with no block scalars", () => {
  // Pinned whole: any other command (a reset or switch to the fetched head, a restore from it)
  // would let the next step run the PR's own files with the secret in their environment.
  assert.deepEqual(
    all.filter(({ key }) => key === "run").map(({ line }) => line),
    ['run: git fetch --no-tags origin "+refs/pull/$PR/head:refs/remotes/pr/head"', "run: node scripts/ci/guard-scan.mjs"],
  );
  for (const { line } of all) assert.ok(!/:\s*[|>][-+0-9]*\s*$/.test(line), `no block scalars: ${line}`);
});
