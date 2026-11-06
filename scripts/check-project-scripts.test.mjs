import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import {
  buildFolders,
  checkProject,
  checkSigning,
  checkTree,
  checkXcconfig,
  forbiddenKeys,
  signingConfig,
} from "./check-project-scripts.mjs";

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

// The tracked files only: the command would also read the owner's git-ignored local xcconfig
// (CLAUDE.md rule 5).
test("the repository's project.yml and tracked signing settings pass", () => {
  const repository = new URL("..", import.meta.url).pathname;
  assert.deepEqual(checkProject(readFileSync(join(repository, "project.yml"), "utf8"), repository), []);
  const tracked = readFileSync(join(repository, signingConfig), "latin1");
  assert.deepEqual(checkXcconfig(tracked, { local: false }), []);
  assert.deepEqual(checkXcconfig(readFileSync(join(repository, "Configs/Signing.example.xcconfig"), "latin1"), { local: true }), []);
});

test("a project in the subset with allowed keys passes", () => {
  withRoot((root) => {
    const text = [
      "﻿# A comment",
      "name: MoonShine # trailing comment",
      "options:",
      "  bundleIdPrefix: dev.demo",
      "  deploymentTarget:",
      '    macOS: "15.0"',
      "packages:",
      "  Core:",
      "    path: Core",
      "configFiles:",
      "  Debug: Configs/Signing.xcconfig",
      "  Release: Configs/Signing.xcconfig",
      "settings:",
      "  base:",
      "    SWIFT_VERSION: '6.0'",
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
  finds(target("    configFiles:\n      Debug: Configs/Signing.xcconfig\n"), 4, "configFiles is not allowed here");
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
  const language = (value) => `options:\n  developmentLanguage: ${value}\n`;
  assert.deepEqual(check(language("a#b")), []);
  assert.deepEqual(check(language("a # postGenCommand: x")), []);
  assert.deepEqual(check("# postGenCommand: x\n"), []);
  assert.deepEqual(check(language("'a # b'")), []);
});

// H1c: the build removes and regenerates `MoonShine.xcodeproj` only, so another name would leave a
// project a session planted in place.
test("the project is named MoonShine", () => {
  assert.deepEqual(check("name: MoonShine\n"), []);
  assert.deepEqual(check("name: 'MoonShine'\n"), []);
  finds("name: Shine\n", 1, "the project is named MoonShine");
  finds("name: moonshine\n", 1, "the project is named MoonShine");
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

// S4-4c-1: signing through Configs/Signing.xcconfig and the owner's local file.

test("configFiles names the signing settings at the top level only", () => {
  const config = (debug, release = signingConfig) => `configFiles:\n  Debug: ${debug}\n  Release: ${release}\n`;
  assert.deepEqual(check(config(signingConfig)), []);
  finds(config("Configs/Other.xcconfig"), 2, `configFiles names ${signingConfig} only`);
  finds(config(signingConfig, "Configs/Signing.local.xcconfig"), 3, "only");
  finds(`configFiles:\n  Profile: ${signingConfig}\n`, 2, "Profile is not allowed here");
  finds("configFiles:\n  Debug:\n    nested: x\n", 3, "takes a single value");
  finds(`settings:\n  configFiles:\n    Debug: ${signingConfig}\n`, 2, "configFiles is not allowed here");
});

test("signing is not a build setting of project.yml", () => {
  for (const name of ["CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE", "DEVELOPMENT_TEAM"]) {
    finds(`settings:\n  base:\n    ${name}: x\n`, 3, `build setting ${name} is not on the allowlist`);
  }
});

const tracked = '// Signing.\nCODE_SIGN_IDENTITY = -\nCODE_SIGN_STYLE = Manual\n#include? "Signing.local.xcconfig"\n';
const local = "CODE_SIGN_IDENTITY = Apple Development\nDEVELOPMENT_TEAM = AB12CD34EF\n";

/// One finding on `line` of `text` whose message contains `words`, and never the text's values.
function findsIn(text, line, words, isLocal = true) {
  const findings = checkXcconfig(text, { local: isLocal });
  assert.equal(findings.length, 1, `${JSON.stringify(text)} → ${JSON.stringify(findings)}`);
  assert.equal(findings[0].line, line, findings[0].message);
  assert.ok(findings[0].message.includes(words), `${findings[0].message} lacks ${words}`);
  for (const secret of ["AB12CD34EF", "OTHER_SWIFT_FLAGS", "/tmp/x", "Elsewhere"]) {
    assert.ok(!findings[0].message.includes(secret), findings[0].message);
  }
}

test("a signing xcconfig holds comments, the three settings and the one include", () => {
  assert.deepEqual(checkXcconfig(tracked, { local: false }), []);
  assert.deepEqual(checkXcconfig(local, { local: true }), []);
  assert.deepEqual(checkXcconfig("", { local: true }), []);
  findsIn(`${local}OTHER_SWIFT_FLAGS = -load-plugin-executable /tmp/x\n`, 3, "a build setting other than");
  findsIn("CC = /tmp/x\n", 1, "a build setting other than");
  findsIn("SWIFT_EXEC = /tmp/x\n", 1, "a build setting other than");
  findsIn("DEVELOPMENT_TEAM = $(AB12CD34EF)\n", 1, "without `$`");
  findsIn("CODE_SIGN_IDENTITY[sdk=macosx*] = Elsewhere\n", 1, "`NAME = value`");
  findsIn("DEVELOPMENT_TEAM=AB12CD34EF\n", 1, "`NAME = value`");
  findsIn('#include "Elsewhere.xcconfig"\n', 1, "`NAME = value`");
  findsIn('#include? "/tmp/x"\n', 1, "`NAME = value`");
  findsIn('#include? "Signing.local.xcconfig"\n', 1, "an include other than", true);
  findsIn(`${tracked}#include? "Signing.local.xcconfig"\n`, 5, "an include other than", false);
  findsIn("  DEVELOPMENT_TEAM = AB12CD34EF\n", 1, "`NAME = value`");
});

test("the tracked xcconfig signs ad hoc only: no team, no other identity or style", () => {
  for (const line of [
    "DEVELOPMENT_TEAM = AB12CD34EF",
    "CODE_SIGN_IDENTITY = Apple Development",
    "CODE_SIGN_IDENTITY = -x",
    "CODE_SIGN_STYLE = Automatic",
  ]) {
    findsIn(`${tracked}${line}\n`, 5, "in the tracked file, a line other than", false);
  }
  // The same lines are the local file's to hold.
  assert.deepEqual(checkXcconfig("CODE_SIGN_STYLE = Automatic\nDEVELOPMENT_TEAM = AB12CD34EF\n", { local: true }), []);
});

test("a signing xcconfig is printable ASCII with LF line breaks", () => {
  for (const [text, line] of [
    ["CODE_SIGN_STYLE = Manual\r\nDEVELOPMENT_TEAM = AB12CD34EF\n", 1],
    ["﻿DEVELOPMENT_TEAM = AB12CD34EF\n", 1],
    ["// a\nDEVELOPMENT_TEAM = AB12CD34EF\u0000\n", 2],
    ["DEVELOPMENT_TEAM = AB12CD34EF OTHER_SWIFT_FLAGS = x\n", 1],
    ["DEVELOPMENT_TEAM = AB12CD34EF\tx\n", 1],
    ["// é\n", 1],
  ]) {
    findsIn(text, line, "printable ASCII");
  }
});

/// A temporary root holding the given files under `Configs/`.
function withSigning(files, body) {
  return withRoot((root) => {
    mkdirSync(join(root, "Configs"));
    for (const [name, text] of Object.entries(files)) writeFileSync(join(root, "Configs", name), text);
    return body(root);
  });
}

const signing = (root) => checkSigning(root).map((finding) => `${finding.file}:${finding.line}: ${finding.message}`);

test("the command reads the tracked file and the local one when present, in a temporary root", () => {
  withSigning({ "Signing.xcconfig": tracked }, (root) => assert.deepEqual(signing(root), []));
  withSigning({ "Signing.xcconfig": tracked, "Signing.local.xcconfig": local }, (root) =>
    assert.deepEqual(signing(root), []),
  );
  withSigning({}, (root) => assert.deepEqual(signing(root), ["Configs/Signing.xcconfig:1: the tracked signing settings are missing"]));
  withSigning({ "Signing.xcconfig": tracked, "Signing.local.xcconfig": "CC = /tmp/x\n" }, (root) => {
    const findings = signing(root);
    assert.equal(findings.length, 1);
    assert.ok(findings[0].startsWith("Configs/Signing.local.xcconfig:1: a build setting other than"), findings[0]);
    assert.ok(!findings[0].includes("/tmp/x"), findings[0]);
  });
});

test("a signing xcconfig that is a symbolic link out of the root, dangling or a folder is a finding", () => {
  const outside = mkdtempSync(join(tmpdir(), "check-project-scripts-outside-"));
  try {
    writeFileSync(join(outside, "x.xcconfig"), local);
    for (const make of [
      (path) => symlinkSync(join(outside, "x.xcconfig"), path),
      (path) => symlinkSync(join(outside, "missing.xcconfig"), path),
      (path) => mkdirSync(path),
    ]) {
      withSigning({ "Signing.xcconfig": tracked }, (root) => {
        make(join(root, "Configs", "Signing.local.xcconfig"));
        assert.deepEqual(signing(root), ["Configs/Signing.local.xcconfig:1: not a regular file inside the repository"]);
      });
    }
    // A link that stays inside the root is read like the file it names.
    withSigning({ "Signing.xcconfig": tracked, "team.txt": local }, (root) => {
      symlinkSync(join(root, "Configs", "team.txt"), join(root, "Configs", "Signing.local.xcconfig"));
      assert.deepEqual(signing(root), []);
    });
  } finally {
    rmSync(outside, { recursive: true, force: true });
  }
});

/// Runs the command on `path`: its exit status and standard output.
function run(path) {
  try {
    return { status: 0, stdout: execFileSync("node", [script, path], { stdio: "pipe", encoding: "utf8" }) };
  } catch (error) {
    return { status: error.status, stdout: String(error.stdout) };
  }
}

// The root holds the clean tracked signing settings, so each exit comes from project.yml alone.
test("the command passes clean input and fails on a finding and on a file that is not UTF-8", () => {
  withSigning({ "Signing.xcconfig": tracked }, (root) => {
    const path = join(root, "project.yml");
    writeFileSync(path, "name: MoonShine\n");
    assert.equal(run(path).status, 0, run(path).stdout);
    writeFileSync(path, "targets:\n  App:\n    postBuildScripts:\n      - script: echo\n");
    const found = run(path);
    assert.equal(found.status, 1);
    assert.ok(found.stdout.includes("project.yml:3: ") && found.stdout.includes("postBuildScripts"), found.stdout);
    writeFileSync(path, Buffer.from([0x6e, 0x61, 0x6d, 0x65, 0x3a, 0x20, 0xe9, 0x0a]));
    const bytes = run(path);
    assert.equal(bytes.status, 1);
    assert.ok(bytes.stdout.includes("project.yml:1: a file that is not UTF-8"), bytes.stdout);
    assert.equal(run(join(root, "absent.yml")).status, 2);
  });
});

// H1c: what the unsandboxed build reads or writes besides project.yml and the xcconfigs.

const tree = (root) => checkTree(root).map((finding) => `${finding.file}: ${finding.message}`);

/// A temporary root with the folders the build reads, and a folder outside it named `secret-target`.
function withTree(body) {
  const outside = mkdtempSync(join(tmpdir(), "secret-target-"));
  try {
    return withRoot((root) => {
      for (const dir of buildFolders) mkdirSync(join(root, dir));
      writeFileSync(join(root, "Adapters", "Package.resolved"), "{}\n");
      return body(root, outside);
    });
  } finally {
    rmSync(outside, { recursive: true, force: true });
  }
}

test("a clean tree passes, with or without DerivedData and the generated project", () => {
  withTree((root) => {
    assert.deepEqual(tree(root), []);
    mkdirSync(join(root, "MoonShine.xcodeproj"));
    mkdirSync(join(root, "DerivedData", "Build", "Products"), { recursive: true });
    mkdirSync(join(root, "Adapters", ".build"));
    symlinkSync(tmpdir(), join(root, "Adapters", ".build", "link"));
    assert.deepEqual(tree(root), []);
  });
});

test("a link in a folder the build reads is a finding, and the finding never names its target", () => {
  for (const dir of buildFolders) {
    withTree((root, outside) => {
      mkdirSync(join(root, dir, "nested"));
      symlinkSync(outside, join(root, dir, "nested", "link"));
      const findings = tree(root);
      assert.deepEqual(findings, [`${dir}/nested/link: a symbolic link where the unsandboxed build reads`]);
      assert.ok(!findings.join("\n").includes("secret-target"));
    });
  }
});

// A missing file is left to the pin step, whose copy fails.
test("Adapters/Package.resolved, when present, is a regular file", () => {
  withTree((root) => {
    rmSync(join(root, "Adapters", "Package.resolved"));
    assert.deepEqual(tree(root), []);
    mkdirSync(join(root, "Adapters", "Package.resolved"));
    assert.deepEqual(tree(root), ["Adapters/Package.resolved: not a regular file"]);
  });
});

test("another project or a workspace at the root is a finding", () => {
  for (const name of ["Shine.xcodeproj", "MoonShine.xcworkspace", "Other.xcworkspace"]) {
    withTree((root) => {
      mkdirSync(join(root, name));
      assert.deepEqual(tree(root), [`${name}: a project or workspace other than MoonShine.xcodeproj`]);
    });
  }
});

test("a link at the top of the build's own folders is a finding", () => {
  for (const name of ["DerivedData", "MoonShine.xcodeproj"]) {
    withTree((root, outside) => {
      symlinkSync(outside, join(root, name));
      assert.deepEqual(tree(root), [`${name}: a symbolic link where the unsandboxed build writes`]);
    });
  }
});

test("a link in DerivedData passes only when it stays inside DerivedData", () => {
  withTree((root, outside) => {
    const products = join(root, "DerivedData", "Build", "Products");
    mkdirSync(products, { recursive: true });
    mkdirSync(join(root, "DerivedData", "SourcePackages", "checkouts", "pkg", "Sources"), { recursive: true });
    // A package's own link, as GRDB ships one.
    symlinkSync("../Sources", join(root, "DerivedData", "SourcePackages", "checkouts", "pkg", "Sources", "self"));
    assert.deepEqual(tree(root), []);
    for (const target of [outside, join(outside, "missing"), "../../../outside", "/"]) {
      const link = join(products, "Debug");
      symlinkSync(target, link);
      const findings = tree(root);
      assert.deepEqual(findings, ["DerivedData/Build/Products/Debug: a symbolic link out of DerivedData"], target);
      assert.ok(!findings.join("\n").includes("secret-target"));
      rmSync(link);
    }
  });
});

test("the command reports the tree's findings", () => {
  withTree((root) => {
    mkdirSync(join(root, "Configs"), { recursive: true });
    writeFileSync(join(root, "Configs", "Signing.xcconfig"), tracked);
    writeFileSync(join(root, "project.yml"), "name: MoonShine\n");
    assert.equal(run(join(root, "project.yml")).status, 0);
    mkdirSync(join(root, "Shine.xcodeproj"));
    const found = run(join(root, "project.yml"));
    assert.equal(found.status, 1);
    assert.ok(found.stdout.includes("Shine.xcodeproj: a project or workspace other than"), found.stdout);
  });
});
