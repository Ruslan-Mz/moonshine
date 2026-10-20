import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { findScripts, forbiddenKeys } from "./check-project-scripts.mjs";

const script = new URL("./check-project-scripts.mjs", import.meta.url).pathname;

test("the repository's project.yml carries no command", () => {
  execFileSync("node", [script], { stdio: "pipe" });
});

test("every forbidden key is found in block style", () => {
  for (const key of forbiddenKeys) {
    const text = `targets:\n  App:\n    type: application\n    ${key}:\n      - script: cat data/x\n`;
    assert.deepEqual(findScripts(text), [`4: ${key}`], key);
  }
});

test("a key is found in flow style, quoted, or as a list item", () => {
  assert.deepEqual(findScripts('options: {postGenCommand: "cat deny-list.txt"}'), ["1: postGenCommand"]);
  assert.deepEqual(findScripts('    "preBuildScripts": []'), ["1: preBuildScripts"]);
  assert.deepEqual(findScripts("  - include: other.yml"), ["1: include"]);
  assert.deepEqual(findScripts("schemes:\n  App:\n    build:\n      preActions:\n"), ["4: preActions"]);
});

test("comments, values and longer names are not keys", () => {
  assert.deepEqual(findScripts("# preBuildScripts: none here"), []);
  assert.deepEqual(findScripts("name: MoonShine # include: later"), []);
  assert.deepEqual(findScripts("PRODUCT_NAME: postBuildScriptsHelper"), []);
  assert.deepEqual(findScripts("myBuildRules: 1"), []);
});

test("the command fails on a finding", () => {
  const dir = mkdtempSync(join(tmpdir(), "check-project-scripts-"));
  try {
    const path = join(dir, "project.yml");
    writeFileSync(path, "targets:\n  App:\n    postBuildScripts:\n      - script: echo\n");
    assert.throws(() => execFileSync("node", [script, path], { stdio: "pipe" }), { status: 1 });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
