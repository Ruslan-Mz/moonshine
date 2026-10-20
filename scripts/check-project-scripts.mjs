#!/usr/bin/env node
// `xcodegen generate` and `xcodebuild` run outside the sandbox (CLAUDE.md → Commands), so a
// shell command written into `project.yml` would run with no read barrier. This check fails
// when the spec can carry one (owner, 2026-10-21, PR #30 round 1): build-script phases
// (`preBuildScripts`, `postCompileScripts`, `postBuildScripts`, aggregate `buildScripts`),
// script build rules (`buildRules`), build tool plugins (`buildToolPlugins`), scheme pre- and
// post-actions (`preActions`, `postActions`), XcodeGen's own commands (`preGenCommand`,
// `postGenCommand`), legacy targets (`legacy`, which run a build tool) and `include`, which
// would bring in another spec this check does not read. A key is found in block and flow
// style, quoted or not; comments are skipped.
// Usage: node scripts/check-project-scripts.mjs [file] (default `project.yml`).
// Exit 0 clean, 1 with `file:line: key` per finding, 2 when the file cannot be read.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

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
];

const keyPattern = new RegExp(
  `(?:^|[\\s{,\\-])["']?(${forbiddenKeys.join("|")})["']?\\s*:`,
  "g",
);

/** Findings as `line: key`, 1-based. */
export function findScripts(text) {
  const findings = [];
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.replace(/(^|\s)#.*$/, "");
    for (const match of line.matchAll(keyPattern)) findings.push(`${index + 1}: ${match[1]}`);
  }
  return findings;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const path = process.argv[2] ?? new URL("../project.yml", import.meta.url).pathname;
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    console.error(`check-project-scripts: cannot read ${path}`);
    process.exit(2);
  }
  const findings = findScripts(text);
  if (findings.length) {
    console.log("project.yml must not run commands (CLAUDE.md → Commands):");
    for (const finding of findings) console.log(`project.yml:${finding}`);
    process.exit(1);
  }
  console.log("project.yml: no build scripts");
}
