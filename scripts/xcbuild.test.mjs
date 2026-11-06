// Tests for scripts/xcbuild.sh, the one way to build the Mac app (H1c): node --test scripts/xcbuild.test.mjs
// Each test runs an installed copy (the script and the check, as the guard installer copies them)
// in a temporary repository folder, with stub `xcodegen` and `xcodebuild` and a `node` stub that
// logs and runs this node. Started: /bin/sh, the stubs, node, and the tools the script starts from
// /usr/bin and /bin (dirname, cmp, rm, mkdir, cp) (CLAUDE.md rule 5).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const scripts = dirname(fileURLToPath(import.meta.url));
const files = ["xcbuild.sh", "check-project-scripts.mjs"];
const tracked = "CODE_SIGN_IDENTITY = -\nCODE_SIGN_STYLE = Manual\n";
const xcodebuildArgs = (action) =>
  `xcodebuild -project MoonShine.xcodeproj -scheme MoonShineMac -destination platform=macOS,arch=arm64 -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile ${action}`;

function stub(path, body) {
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
}

/// A repository folder with the build's inputs and its own scripts/, an installed copy of the two
/// scripts, and the stubs.
function setUp() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "xcbuild-")));
  const repo = join(root, "repo");
  const installed = join(root, "guard");
  const bin = join(root, "bin");
  for (const dir of [repo, installed, bin, join(repo, "scripts"), join(repo, "Configs"), join(repo, "Adapters"), join(repo, "Apps")]) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(join(repo, "project.yml"), "name: MoonShine\n");
  writeFileSync(join(repo, "Configs", "Signing.xcconfig"), tracked);
  writeFileSync(join(repo, "Adapters", "Package.resolved"), '{ "pins": [] }\n');
  for (const file of files) {
    cpSync(join(scripts, file), join(repo, "scripts", file));
    cpSync(join(scripts, file), join(installed, file));
  }
  const log = join(root, "log");
  writeFileSync(log, "");
  stub(join(bin, "node"), `echo node >> "$LOG"\nexec '${process.execPath}' "$@"`);
  stub(join(bin, "xcodegen"), `echo "xcodegen $*" >> "$LOG"\nmkdir -p MoonShine.xcodeproj\n[ -z "\${FAIL_XCODEGEN:-}" ]`);
  stub(join(bin, "xcodebuild"), `echo "xcodebuild $*" >> "$LOG"\n[ -z "\${FAIL_XCODEBUILD:-}" ]`);
  stub(join(bin, "xcrun"), `echo "xcrun $*" >> "$LOG"`);
  return { root, repo, installed, bin, log };
}

function run(work, args, { cwd = work.repo, env = {} } = {}) {
  const result = spawnSync("/bin/sh", [join(work.installed, "xcbuild.sh"), ...args], {
    cwd,
    env: { PATH: `${work.bin}:/usr/bin:/bin`, HOME: work.root, LOG: work.log, ...env },
    encoding: "utf8",
  });
  return { ...result, log: readFileSync(work.log, "utf8").split("\n").filter(Boolean) };
}

function withWork(body) {
  const work = setUp();
  try {
    return body(work);
  } finally {
    rmSync(work.root, { recursive: true, force: true });
  }
}

for (const action of ["build", "test"]) {
  test(`${action}: the check, a fresh project, the pin and xcodebuild, in that order`, () => {
    withWork((work) => {
      const result = run(work, [action]);
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(result.log, ["node", `xcodegen generate --spec ${work.repo}/project.yml`, xcodebuildArgs(action)]);
      const pinned = join(work.repo, "MoonShine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved");
      assert.equal(readFileSync(pinned, "utf8"), '{ "pins": [] }\n');
      assert.ok(!result.stderr.includes("warning"), result.stderr);
    });
  });
}

for (const args of [
  [],
  ["build", "test"],
  ["archive"],
  ["build --quiet"],
  ["-allowProvisioningUpdates"],
  ["summary", "/elsewhere"],
]) {
  test(`${JSON.stringify(args)} is refused and runs nothing`, () => {
    withWork((work) => {
      const result = run(work, args);
      assert.equal(result.status, 2);
      assert.ok(result.stderr.includes("usage"), result.stderr);
      assert.deepEqual(result.log, []);
    });
  });
}

test("it runs only from the repository root, and not on a linked project.yml", () => {
  withWork((work) => {
    const below = run(work, ["build"], { cwd: join(work.repo, "Apps") });
    assert.equal(below.status, 2);
    assert.deepEqual(below.log, []);
    writeFileSync(join(work.root, "elsewhere.yml"), "name: MoonShine\n");
    rmSync(join(work.repo, "project.yml"));
    symlinkSync(join(work.root, "elsewhere.yml"), join(work.repo, "project.yml"));
    const linked = run(work, ["build"]);
    assert.equal(linked.status, 2);
    assert.deepEqual(linked.log, []);
  });
});

test("a finding of the check stops the build before XcodeGen", () => {
  withWork((work) => {
    writeFileSync(join(work.repo, "project.yml"), "name: Shine\n");
    const result = run(work, ["build"]);
    assert.equal(result.status, 1);
    assert.ok(result.stdout.includes("the project is named MoonShine"), result.stdout);
    assert.deepEqual(result.log, ["node"]);
  });
});

test("a tree finding stops the build and never names a link's target", () => {
  withWork((work) => {
    const outside = join(work.root, "secret-target");
    mkdirSync(outside);
    symlinkSync(outside, join(work.repo, "Apps", "Resources"));
    mkdirSync(join(work.repo, "Shine.xcodeproj"));
    const result = run(work, ["test"]);
    assert.equal(result.status, 1);
    assert.ok(result.stdout.includes("Apps/Resources: a symbolic link"), result.stdout);
    assert.ok(result.stdout.includes("Shine.xcodeproj: a project or workspace other than"), result.stdout);
    assert.ok(!`${result.stdout}${result.stderr}`.includes("secret-target"));
    assert.deepEqual(result.log, ["node"]);
  });
});

test("a failing XcodeGen runs no xcodebuild", () => {
  withWork((work) => {
    const result = run(work, ["build"], { env: { FAIL_XCODEGEN: "1" } });
    assert.notEqual(result.status, 0);
    assert.deepEqual(result.log, ["node", `xcodegen generate --spec ${work.repo}/project.yml`]);
  });
});

test("xcodebuild's failure is the script's", () => {
  withWork((work) => {
    const result = run(work, ["test"], { env: { FAIL_XCODEBUILD: "1" } });
    assert.equal(result.status, 1);
    assert.equal(result.log.at(-1), xcodebuildArgs("test"));
  });
});

test("whatever a session planted in the generated project is gone before XcodeGen runs", () => {
  withWork((work) => {
    const scheme = join(work.repo, "MoonShine.xcodeproj/xcuserdata/me.xcuserdatad/xcschemes/MoonShineMac.xcscheme");
    mkdirSync(dirname(scheme), { recursive: true });
    writeFileSync(scheme, "<Scheme><BuildAction><PreActions/></BuildAction></Scheme>\n");
    assert.equal(run(work, ["build"]).status, 0);
    assert.ok(!existsSync(scheme));
  });
});

test("an edited checkout copy warns and never runs: the installed copy does", () => {
  withWork((work) => {
    // The checkout's check would pass anything; the installed one still finds the name.
    writeFileSync(join(work.repo, "scripts", "check-project-scripts.mjs"), "process.exit(0);\n");
    appendFileSync(join(work.repo, "scripts", "xcbuild.sh"), "\n# edited\n");
    writeFileSync(join(work.repo, "project.yml"), "name: Shine\n");
    const result = run(work, ["build"]);
    assert.equal(result.status, 1);
    for (const file of files) {
      assert.ok(result.stderr.includes(`the installed ${file} differs from this checkout's scripts/${file}`), result.stderr);
    }
    assert.ok(result.stderr.includes("Reinstall the guard after the change is merged"), result.stderr);
    assert.ok(result.stdout.includes("the project is named MoonShine"), result.stdout);
  });
});

// PR #47 round 1.

test("a missing Adapters/Package.resolved stops the build before xcodebuild", () => {
  withWork((work) => {
    rmSync(join(work.repo, "Adapters", "Package.resolved"));
    const result = run(work, ["build"]);
    assert.notEqual(result.status, 0);
    assert.ok(!result.log.some((line) => line.startsWith("xcodebuild")), result.log.join("\n"));
  });
});

// /usr/bin and /bin hold no node on macOS; a runner that has one there cannot run this test.
const nodeInSystemFolders = ["/usr/bin/node", "/bin/node"].some((path) => existsSync(path));

test("without node on PATH the build stops with a reinstall hint", { skip: nodeInSystemFolders && "node in /usr/bin or /bin" }, () => {
  withWork((work) => {
    rmSync(join(work.bin, "node"));
    const result = run(work, ["build"]);
    assert.equal(result.status, 2);
    assert.ok(result.stderr.includes("node is not on PATH"), result.stderr);
    assert.ok(result.stderr.includes("reinstall the guard"), result.stderr);
    assert.deepEqual(result.log, []);
  });
});

/// Result bundles under DerivedData/Logs/Test, each older than the next.
function withResults(work, names) {
  const folder = join(work.repo, "DerivedData", "Logs", "Test");
  mkdirSync(folder, { recursive: true });
  names.forEach((name, index) => {
    mkdirSync(join(folder, name));
    const time = new Date(Date.UTC(2026, 10, 6, 12, index));
    utimesSync(join(folder, name), time, time);
  });
  return folder;
}

test("summary reads the newest result bundle, runs no check and no build", () => {
  withWork((work) => {
    const folder = withResults(work, ["Test-B.xcresult", "Test-C.xcresult", "Test-A.xcresult"]);
    const result = run(work, ["summary"]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.log, [
      `xcrun xcresulttool get test-results summary --path ${join(folder, "Test-A.xcresult")} --compact`,
    ]);
  });
});

test("summary without results says to run the tests first", () => {
  withWork((work) => {
    const result = run(work, ["summary"]);
    assert.equal(result.status, 2);
    assert.ok(result.stderr.includes("no test results"), result.stderr);
    assert.deepEqual(result.log, []);
  });
});

test("summary refuses a link anywhere on the bundle's path or inside it, and never names a target", () => {
  const cases = [
    ["DerivedData", (work, outside) => {
      rmSync(join(work.repo, "DerivedData"), { recursive: true });
      symlinkSync(outside, join(work.repo, "DerivedData"));
    }],
    ["DerivedData/Logs", (work, outside) => {
      rmSync(join(work.repo, "DerivedData", "Logs"), { recursive: true });
      symlinkSync(outside, join(work.repo, "DerivedData", "Logs"));
    }],
    ["DerivedData/Logs/Test", (work, outside) => {
      rmSync(join(work.repo, "DerivedData", "Logs", "Test"), { recursive: true });
      symlinkSync(outside, join(work.repo, "DerivedData", "Logs", "Test"));
    }],
    ["the newest result bundle", (work, outside, folder) => {
      const link = join(folder, "Test-Z.xcresult");
      symlinkSync(outside, link);
      const time = new Date(Date.UTC(2026, 10, 7));
      utimesSync(outside, time, time);
    }],
    ["the newest result bundle", (work, outside, folder) => {
      symlinkSync(join(outside, "Info.plist"), join(folder, "Test-A.xcresult", "Info.plist"));
    }],
  ];
  for (const [named, plant] of cases) {
    withWork((work) => {
      const folder = withResults(work, ["Test-A.xcresult"]);
      const outside = join(work.root, "secret-target");
      mkdirSync(join(outside, "Logs", "Test", "Test-S.xcresult"), { recursive: true });
      plant(work, outside, folder);
      const result = run(work, ["summary"]);
      assert.equal(result.status, 2, `${named}: ${result.stderr}`);
      assert.ok(result.stderr.includes(named), result.stderr);
      assert.ok(!`${result.stdout}${result.stderr}`.includes("secret-target"), result.stderr);
      assert.deepEqual(result.log, []);
    });
  }
});
