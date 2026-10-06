// Tests for check-core-imports.sh on throwaway folders: node --test scripts/check-core-imports.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "check-core-imports.sh");
const forbidden = ["AppKit", "Cocoa", "Carbon", "Quartz", "SwiftUI", "SwiftUICore", "OSAKit", "GRDB", "EventKit", "Yams"];

function run(dir) {
  return spawnSync("bash", [script, dir], { encoding: "utf8" });
}

function check(files) {
  const dir = mkdtempSync(join(tmpdir(), "core-imports-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return run(dir);
}

test("allowed imports pass", () => {
  const result = check({
    "Sources/A.swift": "import Foundation\nimport Testing\n@testable import MoonShineCore\npublic import Foundation\nimport GRDBX\n",
    ".build/checkouts/B.swift": "import GRDB\n",
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /clean/);
});

test("every forbidden module fails in every import form", () => {
  const forms = (name) => [
    `import ${name}`,
    `  import ${name}`,
    `@testable import ${name}`,
    `@preconcurrency import ${name}`,
    `@_exported import ${name}`,
    `@_spi(Private) import ${name}`,
    `@_spi(Private) @preconcurrency internal import ${name}`,
    `@preconcurrency public import ${name}`,
    ...["public", "package", "internal", "fileprivate", "private"].map((access) => `${access} import ${name}`),
    `import struct ${name}.X`,
    `public import class ${name}.X`,
    `import Foundation; import ${name}`,
    `import \`${name}\``,
    `import /* x */ ${name}`,
    `import struct /* x */ \`${name}\`.X`,
  ];
  for (const name of forbidden) {
    for (const line of forms(name)) {
      const result = check({ "Sources/A.swift": `import Foundation\n${line}\n` });
      assert.equal(result.status, 1, line);
      assert.match(result.stdout, /A\.swift:2:/, line);
    }
  }
});

test("a folder that cannot be searched fails instead of reporting clean", () => {
  const result = run(join(tmpdir(), "core-imports-missing-folder"));
  assert.equal(result.status, 2, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /clean/);
});

test("an unreadable subfolder fails instead of reporting clean", () => {
  const dir = mkdtempSync(join(tmpdir(), "core-imports-"));
  mkdirSync(join(dir, "Locked"));
  writeFileSync(join(dir, "Locked", "A.swift"), "import AppKit\n");
  chmodSync(join(dir, "Locked"), 0o000);
  try {
    const result = run(dir);
    assert.equal(result.status, 2, result.stdout + result.stderr);
    assert.doesNotMatch(result.stdout, /clean/);
  } finally {
    chmodSync(join(dir, "Locked"), 0o755);
  }
});
