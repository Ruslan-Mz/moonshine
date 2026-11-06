#!/usr/bin/env node
// `xcodegen generate` and `xcodebuild` run outside the sandbox (CLAUDE.md → Commands), so
// `project.yml` must not carry a command, nor a path that reads outside the repository
// (owner, 2026-10-21, PR #30 round 1; H1a, 2026-10-29). The file is read as a strict YAML
// subset, and anything outside it is a finding, never a skip, so this check and libyaml
// (under XcodeGen) cannot read different keys:
// - UTF-8; a BOM only first; LF or CRLF line breaks only (a lone CR, NEL, LS or PS is one more
//   break for libyaml); no tab and no other control character;
// - `#` starts a comment at the start of a line or after a space, never inside quotes;
// - block mappings and sequences indented by spaces; a sequence is indented under its key;
//   keys plain (`[A-Za-z_][A-Za-z0-9_.-]*`) and unique;
// - values: a plain scalar, a one-line quoted scalar (no backslash in double quotes), or a
//   one-line flow sequence of plain items; no anchors, aliases, tags, flow mappings, block or
//   multi-line scalars, document markers or directives.
// Keys are then checked against an allowlist per path (`schema` below), build-setting names
// against their own; the keys of `forbiddenKeys`, build settings ending in `_EXEC` and `CC`
// are named even if the allowlist ever lists them. A `path` value is relative, has no `..`
// or `$` (XcodeGen expands `${VAR}`), and resolves, after symlinks, inside the repository and
// not to its root.
// `configFiles` is allowed at the top level only, for Debug and Release, and names exactly
// `Configs/Signing.xcconfig` (S4-4c-1, owner 2026-11-05): an xcconfig is a second way to set any
// build setting and to include any file. So the command also reads that file and, when present,
// the git-ignored `Configs/Signing.local.xcconfig` next to it (only the owner writes it): each
// must be a regular file inside the repository after symlinks, in printable ASCII with LF line
// breaks, holding only blank lines, `//` comments and `NAME = value` lines for
// CODE_SIGN_IDENTITY, CODE_SIGN_STYLE and DEVELOPMENT_TEAM, with no `$` and no condition
// (`NAME[sdk=…]`); the tracked file may hold only `CODE_SIGN_IDENTITY = -`,
// `CODE_SIGN_STYLE = Manual` and one `#include? "Signing.local.xcconfig"`, the local file no
// include. Its findings name a line and a kind, never a name or a value from the file: the
// local file holds the owner's team id. The project is named MoonShine, and the command also checks
// the tree the build reads and writes (`checkTree`). The build runs it first (`scripts/xcbuild.sh`);
// locally the copy the guard installer took from main (H1c), never the checkout's.
// Usage: node scripts/check-project-scripts.mjs [file] (default `project.yml`).
// Exit 0 clean, 1 with `file:line: reason` per finding, 2 when the file cannot be read.

import { lstatSync, readdirSync, readFileSync, readlinkSync, realpathSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, isAbsolute, sep } from "node:path";
import { pathToFileURL } from "node:url";

/** Keys that run a command, read another spec or point at a build tool. */
export const forbiddenKeys = [
  "preBuildScripts",
  "postCompileScripts",
  "postBuildScripts",
  "buildScripts",
  "buildRules",
  "buildToolPlugins",
  "preActions",
  "postActions",
  "preGenCommand",
  "postGenCommand",
  "legacy",
  "include",
  "projectReferences",
  "carthageExecutablePath",
];

const buildSettingNames = new Set([
  "SWIFT_VERSION",
  "SWIFT_STRICT_CONCURRENCY",
  // Signing only through `Configs/Signing.xcconfig`, so `project.yml` cannot override it.
  "ENABLE_HARDENED_RUNTIME",
  "SWIFT_EMIT_LOC_STRINGS",
  "LOCALIZATION_PREFERS_STRING_CATALOGS",
  "PRODUCT_BUNDLE_IDENTIFIER",
  "GENERATE_INFOPLIST_FILE",
  "MARKETING_VERSION",
  "CURRENT_PROJECT_VERSION",
]);

// Leaves: a single value, a path, a single value or a flow sequence, build settings.
const VALUE = "value";
const PATH = "path";
const VALUES = "values";
const BUILD = "build settings";
const CONFIG = "signing config";
const NAME = "project name";
const settings = { base: BUILD };
export const signingConfig = "Configs/Signing.xcconfig";
const localConfig = "Configs/Signing.local.xcconfig";
const signingSettings = new Set(["CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE", "DEVELOPMENT_TEAM"]);
// The tracked file signs ad hoc only: a team id or another identity never lands in the public
// repository (owner, 2026-11-06, PR #46 round 1).
const trackedSettings = new Set(["CODE_SIGN_IDENTITY = -", "CODE_SIGN_STYLE = Manual"]);
const schema = {
  name: NAME,
  configFiles: { Debug: CONFIG, Release: CONFIG },
  options: {
    bundleIdPrefix: VALUE,
    deploymentTarget: { macOS: VALUE },
    developmentLanguage: VALUE,
    createIntermediateGroups: VALUE,
  },
  packages: { "*": { path: PATH } },
  settings,
  targets: {
    "*": {
      type: VALUE,
      platform: VALUE,
      sources: [{ path: PATH, buildPhase: VALUE }],
      dependencies: [{ package: VALUE, product: VALUE, target: VALUE }],
      settings,
    },
  },
  schemes: { "*": { build: { targets: { "*": VALUES } }, test: { targets: [VALUE] } } },
};

const plainKey = /^[A-Za-z_][A-Za-z0-9_.-]*$/;
const plainValue = /^(?![&*!|>{[?%@`"'#]|-(?: |$))(?!.*: )(?!.*:$).+$/;
const flowItem = /^[^:?#[\]{}&*!'",\s](?:[^:?#[\]{}&*!'",]*[^:?#[\]{}&*!'",\s])?$/;

class Stop extends Error {}

/** Findings for the text of a `project.yml` whose folder is `root`, as `{ line, message }`. */
export function checkProject(text, root) {
  const findings = [];
  const fail = (line, message) => {
    findings.push({ line, message });
    throw new Stop();
  };
  try {
    walk(parse(text, fail), schema, findings, root);
  } catch (error) {
    if (!(error instanceof Stop)) throw error;
  }
  return findings;
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length;
}

/// The value of one line, after the key or the dash: a node, or null for "a block follows".
function value(raw, line, fail) {
  let text = raw;
  if (text.startsWith("'") || text.startsWith('"')) {
    const end = text.startsWith("'") ? /^'(?:[^']|'')*'/.exec(text) : /^"[^"\\]*"/.exec(text);
    const rest = end ? text.slice(end[0].length) : "";
    if (!end || !/^(?:\s*| +#.*)$/.test(rest)) fail(line, "a value outside the subset");
    return { kind: "value", line, text: end[0].slice(1, -1).replaceAll("''", "'") };
  }
  text = text.replace(/(^| )#.*$/, "").trimEnd();
  if (text === "") return null;
  if (text.startsWith("[")) {
    const items = /^\[(.*)\]$/.exec(text)?.[1].split(",").map((item) => item.trim());
    if (!items || !(items.length === 1 && items[0] === "") && !items.every((item) => flowItem.test(item))) {
      fail(line, "a value outside the subset");
    }
    return { kind: "values", line };
  }
  if (!plainValue.test(text)) fail(line, "a value outside the subset");
  return { kind: "value", line, text };
}

function parse(text, fail) {
  const body = text.startsWith("\uFEFF") ? text.slice(1) : text;
  const checks = [
    [/\r(?!\n)|[\u0085\u2028\u2029]/, "a line break libyaml knows other than LF or CRLF"],
    [/\uFEFF/, "a byte-order mark after the start"],
    [/\t/, "a tab"],
    [/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u0084\u0086-\u009f]/, "a control character"],
  ];
  for (const [pattern, message] of checks) {
    const found = pattern.exec(body);
    if (found) fail(lineOf(body, found.index), message);
  }
  const root = { kind: "map", line: 1, entries: new Map() };
  const stack = [{ indent: 0, node: root }];
  let open = null; // a key or item whose block may follow: { indent, line, attach }
  for (const [index, raw] of body.split(/\r?\n/).entries()) {
    const line = index + 1;
    if (/^ *(?:#.*)?$/.test(raw)) continue;
    if (/^(?:---|\.\.\.)(?: |$)/.test(raw)) fail(line, "a document marker");
    if (raw.startsWith("%")) fail(line, "a directive");
    // libyaml indents by U+0020 only; an NBSP or another space would be content to it.
    const indent = /^ */.exec(raw)[0].length;
    let rest = raw.slice(indent);
    if (/^\s/.test(rest)) fail(line, "whitespace other than spaces before content");
    const item = /^-(?: |$)/.test(rest);
    if (item) rest = rest.slice(2);

    if (open) {
      const block = open;
      open = null;
      if (indent > block.indent) {
        const node = item ? { kind: "seq", line, items: [] } : { kind: "map", line, entries: new Map() };
        block.attach(node);
        stack.push({ indent, node });
      } else if (item && indent === block.indent) {
        fail(line, "a sequence not indented under its key");
      }
    }
    while (stack.at(-1).indent > indent) stack.pop();
    const frame = stack.at(-1);
    if (frame.indent !== indent) fail(line, "an indentation that matches no open block");

    let map = frame.node;
    let keyIndent = indent;
    if (item) {
      if (frame.node.kind !== "seq") fail(line, "a sequence item inside a mapping");
      const keyed = /^([^\s:]+):(?: |$)/.test(rest) || /^\S.*? :(?: |$)/.test(rest);
      if (!keyed) {
        const node = value(rest, line, fail);
        if (node === null) fail(line, "an empty sequence item");
        frame.node.items.push(node);
        continue;
      }
      map = { kind: "map", line, entries: new Map() };
      frame.node.items.push(map);
      keyIndent = indent + 2;
      stack.push({ indent: keyIndent, node: map });
    } else if (frame.node.kind !== "map") {
      fail(line, "a mapping key inside a sequence");
    }
    const colon = rest.search(/:(?: |$)/);
    if (colon < 0) fail(line, "a line that is not `key: value` (libyaml would join it to a multi-line scalar)");
    const key = rest.slice(0, colon);
    if (!plainKey.test(key)) fail(line, "a key that is not a plain key");
    if (map.entries.has(key)) fail(line, `a duplicate key ${key}`);
    const node = value(rest.slice(colon + 1).trimStart(), line, fail);
    map.entries.set(key, { line, node });
    if (node === null) open = { indent: keyIndent, line, attach: (child) => map.entries.set(key, { line, node: child }) };
  }
  return root;
}

function walk(node, rule, findings, root) {
  const report = (line, message) => findings.push({ line, message });
  if (node === null) return;
  if (rule === VALUE || rule === PATH || rule === VALUES || rule === CONFIG || rule === NAME) {
    if (node.kind !== "value" && !(rule === VALUES && node.kind === "values")) {
      report(node.line, "this key takes a single value");
    } else if (rule === NAME && node.text !== "MoonShine") {
      // The build regenerates MoonShine.xcodeproj only (H1c).
      report(node.line, "the project is named MoonShine");
    } else if (rule === CONFIG && node.text !== signingConfig) {
      report(node.line, `configFiles names ${signingConfig} only`);
    } else if (rule === PATH && !insideRepository(node.text, root)) {
      report(node.line, "a path outside the repository (relative, no `..` or `$`, inside it after symlinks, not its root)");
    }
    return;
  }
  if (Array.isArray(rule)) {
    if (node.kind !== "seq") return report(node.line, "this key takes a sequence");
    for (const item of node.items) {
      if (rule[0] !== VALUE && item.kind !== "map") report(item.line, "this sequence takes mapping items");
      else walk(item, rule[0], findings, root);
    }
    return;
  }
  if (node.kind !== "map") return report(node.line, "this key takes a mapping");
  for (const [key, entry] of node.entries) {
    if (forbiddenKeys.includes(key)) {
      report(entry.line, `${key} can run a command or read outside the repository`);
    } else if (rule === BUILD) {
      if (key === "CC" || key.endsWith("_EXEC")) report(entry.line, `build setting ${key} names a tool to run`);
      else if (!buildSettingNames.has(key) && !key.startsWith("INFOPLIST_KEY_")) {
        report(entry.line, `build setting ${key} is not on the allowlist`);
      } else walk(entry.node, VALUE, findings, root);
    } else if (Object.hasOwn(rule, key) || Object.hasOwn(rule, "*")) {
      walk(entry.node, Object.hasOwn(rule, key) ? rule[key] : rule["*"], findings, root);
    } else {
      report(entry.line, `${key} is not allowed here`);
    }
  }
}

/** Findings for the text of a signing xcconfig, as `{ line, message }`. */
export function checkXcconfig(text, { local }) {
  const outside = /[^\x20-\x7e\n]/.exec(text);
  if (outside) return [{ line: lineOf(text, outside.index), message: "a character other than printable ASCII or LF" }];
  const findings = [];
  let includes = 0;
  for (const [index, raw] of text.split("\n").entries()) {
    const line = index + 1;
    if (/^ *$/.test(raw) || raw.startsWith("//")) continue;
    if (raw === '#include? "Signing.local.xcconfig"') {
      includes += 1;
      if (local || includes > 1) findings.push({ line, message: "an include other than the tracked file's one" });
    } else if (!/^[A-Z_][A-Z0-9_]* = [^$]*$/.test(raw)) {
      findings.push({ line, message: "a line other than a comment, the include or `NAME = value` without `$`" });
    } else if (!signingSettings.has(raw.slice(0, raw.indexOf(" ")))) {
      findings.push({ line, message: "a build setting other than CODE_SIGN_IDENTITY, CODE_SIGN_STYLE, DEVELOPMENT_TEAM" });
    } else if (!local && !trackedSettings.has(raw)) {
      findings.push({ line, message: "in the tracked file, a line other than `CODE_SIGN_IDENTITY = -` or `CODE_SIGN_STYLE = Manual`" });
    }
  }
  return findings;
}

/** Findings for the signing xcconfigs under `root`, as `{ file, line, message }`. */
export function checkSigning(root) {
  const findings = [];
  for (const [file, local] of [
    [signingConfig, false],
    [localConfig, true],
  ]) {
    const path = join(root, file);
    try {
      lstatSync(path);
    } catch {
      if (!local) findings.push({ file, line: 1, message: "the tracked signing settings are missing" });
      continue;
    }
    if (!insideRepository(file, root) || !statSync(path).isFile()) {
      findings.push({ file, line: 1, message: "not a regular file inside the repository" });
      continue;
    }
    // Latin-1 maps every byte to one character, so any byte outside ASCII is a finding.
    for (const finding of checkXcconfig(readFileSync(path, "latin1"), { local })) findings.push({ file, ...finding });
  }
  return findings;
}

/** Folders the build reads as they are: `project.yml`'s paths, the packages and the signing settings. */
export const buildFolders = ["Apps", "Adapters", "MoonShineCore", "Configs", "fixtures", "bridge"];
const generatedProject = "MoonShine.xcodeproj";

function lstat(path) {
  try {
    return lstatSync(path);
  } catch {
    return null;
  }
}

/// The links under `dir` as [absolute path, path from the root], not descending into links or `skip`.
function linksUnder(dir, name, skip = new Set()) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries.flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isSymbolicLink()) return [[path, `${name}/${entry.name}`]];
    return entry.isDirectory() && !skip.has(entry.name) ? linksUnder(path, `${name}/${entry.name}`, skip) : [];
  });
}

/**
 * Findings for the tree the unsandboxed build reads and writes (H1c, `scripts/xcbuild.sh`), as
 * `{ file, message }`: a link in a folder it reads (outside `.build/`, which it does not read), a
 * project or workspace beside the generated one, a link at `DerivedData` or the generated project,
 * a link inside `DerivedData` out of it (a package's own links stay inside), and
 * `Adapters/Package.resolved` that is not a regular file. A finding names the link, never its target.
 */
export function checkTree(root) {
  const findings = [];
  const report = (file, message) => findings.push({ file, message });
  const base = realpathSync(root);
  for (const dir of buildFolders) {
    if (lstat(join(base, dir))?.isSymbolicLink()) report(dir, "a symbolic link where the unsandboxed build reads");
    for (const [, name] of linksUnder(join(base, dir), dir, new Set([".build"]))) {
      report(name, "a symbolic link where the unsandboxed build reads");
    }
  }
  const resolved = lstat(join(base, "Adapters", "Package.resolved"));
  if (resolved && !resolved.isFile() && !resolved.isSymbolicLink()) report("Adapters/Package.resolved", "not a regular file");
  for (const name of readdirSync(base).sort()) {
    if (/\.(?:xcodeproj|xcworkspace)$/.test(name) && name !== generatedProject) {
      report(name, `a project or workspace other than ${generatedProject}`);
    }
  }
  for (const name of ["DerivedData", generatedProject]) {
    if (lstat(join(base, name))?.isSymbolicLink()) report(name, "a symbolic link where the unsandboxed build writes");
  }
  const derived = join(base, "DerivedData");
  if (lstat(derived)?.isDirectory()) {
    const inside = (path) => {
      const rest = relative(derived, path);
      return !(rest === ".." || rest.startsWith(`..${sep}`) || isAbsolute(rest));
    };
    for (const [path, name] of linksUnder(derived, "DerivedData")) {
      let real = null;
      try {
        real = realpathSync(path);
      } catch {
        // dangling: its written target decides
      }
      if (!inside(resolve(dirname(path), readlinkSync(path))) || (real !== null && !inside(real))) {
        report(name, "a symbolic link out of DerivedData");
      }
    }
  }
  return findings;
}

function insideRepository(path, root) {
  if (path === "" || /^[/~]/.test(path) || path.includes("$") || path.split("/").includes("..")) return false;
  try {
    const base = realpathSync(root);
    const resolved = relative(base, realpathSync(join(base, path)));
    // Not the root itself: it holds `data/` and the deny-list (owner, 2026-10-30, PR #37 round 1).
    return resolved !== "" && !(resolved === ".." || resolved.startsWith(`..${sep}`) || isAbsolute(resolved));
  } catch {
    return false;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const path = process.argv[2] ?? new URL("../project.yml", import.meta.url).pathname;
  let bytes;
  try {
    bytes = readFileSync(path);
  } catch {
    console.error(`check-project-scripts: cannot read ${path}`);
    process.exit(2);
  }
  let findings;
  try {
    findings = checkProject(new TextDecoder("utf-8", { fatal: true }).decode(bytes), dirname(path));
  } catch {
    findings = [{ line: 1, message: "a file that is not UTF-8" }];
  }
  findings = findings
    .map((finding) => ({ file: "project.yml", ...finding }))
    .concat(checkSigning(dirname(path)), checkTree(dirname(path)));
  if (findings.length) {
    console.log(
      "project.yml, its signing settings and the build tree must not run commands or read or write outside the repository (CLAUDE.md → Commands):",
    );
    for (const finding of findings) {
      console.log(`${finding.line ? `${finding.file}:${finding.line}` : finding.file}: ${finding.message}`);
    }
    process.exit(1);
  }
  console.log("project.yml: in the subset, allowed keys only, paths inside the repository; signing settings and build tree clean");
}
