import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { checkProject, forbiddenKeys } from "./check-project-scripts.mjs";

const script = new URL("./check-project-scripts.mjs", import.meta.url).pathname;

/// A temporary repository root with the folders the snippets below name.
function withRoot(body) {
  const root = mkdtempSync(join(tmpdir(), "check-project-scripts-"));
  try {
    for (const dir of ["Sources", "Core", "outside"]) mkdirSync(join(root, dir));
    return body(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

/// The findings for `text` as `line: message`.
function check(text, root = "/nonexistent") {
  return checkProject(text, root).map((finding) => `${finding.line}: ${finding.message}`);
}

/// Asserts one finding on `line` whose message contains `words`.
function finds(text, line, words, root) {
  const findings = check(text, root);
  assert.equal(findings.length, 1, `${JSON.stringify(text)} → ${JSON.stringify(findings)}`);
  assert.ok(findings[0].startsWith(`${line}: `), findings[0]);
  assert.ok(findings[0].includes(words), `${findings[0]} lacks ${words}`);
}

const target = (lines) => `targets:\n  App:\n    type: application\n${lines}`;

test("the repository's project.yml passes", () => {
  execFileSync("node", [script], { stdio: "pipe" });
});

test("a project in the subset with allowed keys passes", () => {
  withRoot((root) => {
    const text = [
      "﻿# A comment",
      "name: Demo # trailing comment",
      "options:",
      "  bundleIdPrefix: dev.demo",
      "  deploymentTarget:",
      '    macOS: "15.0"',
      "packages:",
      "  Core:",
      "    path: Core",
      "settings:",
      "  base:",
      "    CODE_SIGN_IDENTITY: '-'",
      "    INFOPLIST_KEY_NSAppleEventsUsageDescription: Reads tasks",
      "targets:",
      "  App:",
      "    type: application",
      "    sources:",
      "      - path: Sources",
      "        buildPhase: resources",
      "    dependencies:",
      "      - package: Core",
      "        product: Core",
      "schemes:",
      "  App:",
      "    build:",
      "      targets:",
      "        App: all",
      "        AppTests: [test]",
      "    test:",
      "      targets:",
      "        - AppTests",
      "",
    ].join("\r\n");
    assert.deepEqual(check(text, root), []);
  });
});

test("each forbidden key is found in block style and as a list item", () => {
  for (const key of forbiddenKeys) {
    const reason = `${key} can run a command or read outside the repository`;
    finds(target(`    ${key}:\n      - script: cat data/x\n`), 4, reason);
    finds(target(`    dependencies:\n      - ${key}: x\n`), 5, reason);
  }
});

test("build settings ending in _EXEC and CC are forbidden", () => {
  for (const name of ["SWIFT_EXEC", "LD_EXEC", "CC"]) {
    finds(`settings:\n  base:\n    ${name}: /tmp/x\n`, 3, `build setting ${name} names a tool to run`);
  }
});

test("keys of Object.prototype are not allowed", () => {
  for (const key of ["constructor", "toString", "hasOwnProperty", "__proto__"]) {
    finds(`${key}: x\n`, 1, `${key} is not allowed here`);
    finds(`options:\n  ${key}: x\n`, 2, `${key} is not allowed here`);
  }
});

test("configFiles, projectReferences and carthageExecutablePath are forbidden", () => {
  finds(target("    configFiles:\n      Debug: x.xcconfig\n"), 4, "configFiles");
  finds("projectReferences:\n  Other:\n    path: x.xcodeproj\n", 1, "projectReferences");
  finds("options:\n  carthageExecutablePath: /tmp/x\n", 2, "carthageExecutablePath");
});

test("a build setting outside the allowlist is a finding", () => {
  finds("settings:\n  base:\n    OTHER_LDFLAGS: -lx\n", 3, "OTHER_LDFLAGS");
});

test("an unknown key is a finding at every level", () => {
  finds("postGen: x\n", 1, "postGen");
  finds("options:\n  usesTabs: true\n", 2, "usesTabs");
  finds("packages:\n  Core:\n    url: https://x\n", 3, "url");
  finds(target("    scheme: App\n"), 4, "scheme");
  withRoot((root) => finds(target("    sources:\n      - path: Sources\n        type: folder\n"), 6, "type", root));
  finds(target("    dependencies:\n      - sdk: x.framework\n"), 5, "sdk");
  finds("schemes:\n  App:\n    run:\n      config: Debug\n", 3, "run");
  finds("settings:\n  configs:\n    Debug: x\n", 2, "configs");
});

test("keys that are not plain are findings", () => {
  finds('"pre\\u0042uildScripts": x\n', 1, "plain key");
  finds("'name': x\n", 1, "plain key");
  finds("? name\n: x\n", 1, "not `key: value`");
  finds("<<: *base\n", 1, "plain key");
  finds("name : x\n", 1, "plain key");
});

test("anchors, aliases, tags, flow mappings and block scalars are findings", () => {
  finds("name: &a x\n", 1, "value");
  finds("name: *a\n", 1, "value");
  finds("name: !!str x\n", 1, "value");
  finds("options: {postGenCommand: x}\n", 1, "value");
  finds("name: |\n  x\n", 1, "value");
  finds("name: >\n  x\n", 1, "value");
  finds('name: "a\\nb"\n', 1, "value");
});

test("a multi-line scalar is a finding", () => {
  finds("name: first\n  postGenCommand: x\n", 2, "indentation");
  finds("options:\n  bundleIdPrefix\n  createIntermediateGroups\n", 2, "not `key: value`");
  finds("settings:\n  base:\n    SWIFT_VERSION\n", 3, "not `key: value`");
});

test("indentation other than spaces is a finding", () => {
  for (const space of [" ", "　"]) {
    finds(`options:\n${space}${space}bundleIdPrefix: x\n`, 2, "whitespace other than spaces");
    finds(target(`  ${space}${space}settings:\n    type: application\n`), 4, "whitespace other than spaces");
    finds(`name: x\n${space}#: y\n`, 2, "whitespace other than spaces");
  }
});

test("line breaks libyaml knows beyond LF and CRLF are findings", () => {
  for (const separator of [" ", "\u0085", " ", "\r"]) {
    finds(`name: MoonShine${separator}postGenCommand: cat x\n`, 1, "line break");
  }
});

test("a BOM after the start, a tab and a control character are findings", () => {
  finds("name: a﻿b\n", 1, "byte-order mark");
  finds("name:\tx\n", 1, "tab");
  finds("name: a\u0007b\n", 1, "control character");
});

test("a flow sequence holds only plain items", () => {
  finds("schemes:\n  App:\n    build:\n      targets:\n        App: [a: b]\n", 5, "value");
  finds("schemes:\n  App:\n    build:\n      targets:\n        App: [test, &x y]\n", 5, "value");
});

test("# starts a comment only at the start of a line or after a space", () => {
  assert.deepEqual(check("name: a#b\n"), []);
  assert.deepEqual(check("name: a # postGenCommand: x\n"), []);
  assert.deepEqual(check("# postGenCommand: x\n"), []);
  assert.deepEqual(check("name: 'a # b'\n"), []);
});

test("document markers and directives are findings", () => {
  finds("---\nname: x\n", 1, "document marker");
  finds("name: x\n...\n", 2, "document marker");
  finds("%YAML 1.1\nname: x\n", 1, "directive");
});

test("structure: duplicates, compact sequences, values under a leaf", () => {
  finds("name: a\nname: b\n", 2, "duplicate");
  finds(target("    sources:\n    - path: Sources\n"), 5, "sequence");
  finds(target("    platform:\n      nested: x\n"), 5, "takes a single value");
  withRoot((root) =>
    finds(target("    sources:\n      - path: Sources\n        buildPhase:\n          - x\n"), 7, "takes a single value", root),
  );
  finds(target("    sources:\n      - Sources\n"), 5, "mapping");
});

// Each rejected path below exists inside the root, so only the rule under test rejects it.
test("a path must be relative, without .. or $, and resolve inside the repository", () => {
  withRoot((root) => {
    for (const dir of ["~", "${HOME}"]) mkdirSync(join(root, dir));
    const at = (path) => target(`    sources:\n      - path: ${path}\n`);
    assert.deepEqual(check(at("Sources"), root), []);
    assert.deepEqual(check(at("Core"), root), []);
    finds(at("/Sources"), 5, "path", root);
    finds(at("~"), 5, "path", root);
    finds(at("Sources/../Core"), 5, "path", root);
    finds(at("${HOME}"), 5, "path", root);
    finds(at("missing"), 5, "path", root);
    finds(`packages:\n  Core:\n    path: ../${basename(root)}/Core\n`, 3, "path", root);
    symlinkSync(tmpdir(), join(root, "Sources", "link"));
    finds(at("Sources/link"), 5, "path", root);
  });
});

test("the repository root is not a path (owner, 2026-10-30)", () => {
  withRoot((root) => {
    for (const path of [".", "./"]) finds(target(`    sources:\n      - path: ${path}\n`), 5, "not its root", root);
  });
});

test("the command fails on a finding and on a file that is not UTF-8", () => {
  const dir = mkdtempSync(join(tmpdir(), "check-project-scripts-"));
  try {
    const path = join(dir, "project.yml");
    writeFileSync(path, "targets:\n  App:\n    postBuildScripts:\n      - script: echo\n");
    assert.throws(() => execFileSync("node", [script, path], { stdio: "pipe" }), { status: 1 });
    writeFileSync(path, Buffer.from([0x6e, 0x61, 0x6d, 0x65, 0x3a, 0x20, 0xe9, 0x0a]));
    assert.throws(() => execFileSync("node", [script, path], { stdio: "pipe" }), { status: 1 });
    assert.throws(() => execFileSync("node", [script, join(dir, "absent.yml")], { stdio: "pipe" }), {
      status: 2,
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
