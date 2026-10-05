// Tests for check-core-imports.sh on throwaway folders: node --test scripts/check-core-imports.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "check-core-imports.sh");

function check(files) {
  const dir = mkdtempSync(join(tmpdir(), "core-imports-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return spawnSync("bash", [script, dir], { encoding: "utf8" });
}

test("allowed imports pass", () => {
  const result = check({
    "Sources/A.swift": "import Foundation\nimport Testing\n@testable import MoonShineCore\nimport GRDBX\n",
    ".build/checkouts/B.swift": "import GRDB\n",
  });
  assert.equal(result.status, 0, result.stdout);
});

test("every forbidden module fails in every import form", () => {
  const forms = (name) => [`import ${name}`, `@testable import ${name}`, `  @preconcurrency import ${name}`, `import struct ${name}.X`];
  for (const name of ["AppKit", "Cocoa", "Carbon", "Quartz", "SwiftUI", "SwiftUICore", "OSAKit", "GRDB", "EventKit", "Yams"]) {
    for (const line of forms(name)) {
      const result = check({ "Sources/A.swift": `import Foundation\n${line}\n` });
      assert.equal(result.status, 1, line);
      assert.match(result.stdout, /A\.swift:2:/, line);
    }
  }
});
