#!/usr/bin/env node
// Checks references in the repository's Markdown, offline and without dependencies:
//   1. relative links [text](path)           → the file or folder exists (#anchor ignored)
//   2. [[wikilinks]] outside code             → a note with that name exists
//   3. every ADR-NNNN mention                 → docs/adr/NNNN-*.md exists
//   4. repo paths in inline code (`docs/…`)   → the path exists (from the repository root or
//                                               from the file's own folder)
// Only tracked files count (git-ignored paths are neither scanned nor targets); fixtures/
// and node_modules/ are not scanned. Run from the repository root: node scripts/check-refs.mjs

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

// Every exception, with its reason. Remove an entry as soon as its reason is gone.
const ALLOWLIST = [
  { rule: "adr", target: "ADR-0012", reason: "lands with the draft-3 docs PR" },
  {
    rule: "wikilink",
    target: "0012-calendar-eventkit-read-only-per-device",
    reason: "lands with the draft-3 docs PR",
  },
];

const tracked = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" })
  .split("\0")
  .filter(Boolean);
const trackedSet = new Set(tracked);
const folders = new Set(
  tracked.flatMap((file) =>
    path
      .dirname(file)
      .split("/")
      .map((_, i, parts) => parts.slice(0, i + 1).join("/")),
  ),
);
const topLevel = new Set(
  tracked
    .filter((file) => file.includes("/"))
    .map((file) => file.split("/")[0]),
);
const notes = new Set(
  tracked
    .filter((file) => file.endsWith(".md"))
    .flatMap((file) => [file.slice(0, -3), path.basename(file, ".md")]),
);
const adrs = new Set(
  tracked
    .map((file) => /^docs\/adr\/(\d{4})-.*\.md$/.exec(file)?.[1])
    .filter(Boolean),
);
const exists = (repoPath) =>
  trackedSet.has(repoPath) || folders.has(repoPath.replace(/\/$/, ""));

const scanned = tracked.filter(
  (file) => file.endsWith(".md") && !/^(fixtures|node_modules)\//.test(file),
);
const hits = [];
const report = (file, line, rule, target) => {
  const allowed = ALLOWLIST.find(
    (entry) => entry.rule === rule && entry.target === target,
  );
  if (!allowed) hits.push(`${file}:${line}  ${rule}  ${target}`);
};

for (const file of scanned) {
  let inFence = false;
  readFileSync(file, "utf8")
    .split("\n")
    .forEach((text, index) => {
      const line = index + 1;
      if (/^\s*(```|~~~)/.test(text)) {
        inFence = !inFence;
        return;
      }
      if (inFence) return;
      const codeSpans = [...text.matchAll(/`([^`]+)`/g)].map(
        (match) => match[1],
      );
      const prose = text.replace(/`[^`]*`/g, "");

      // 1. Relative links.
      for (const [, target] of prose.matchAll(
        /\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
      )) {
        if (/^([a-z][a-z0-9+.-]*:|#)/i.test(target)) continue;
        const relative = decodeURI(target.split("#")[0]);
        const resolved = path.posix.normalize(
          path.posix.join(path.posix.dirname(file), relative),
        );
        if (!exists(resolved)) report(file, line, "link", target);
      }
      // 2. Wikilinks.
      for (const [, target] of prose.matchAll(
        /\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]/g,
      )) {
        if (!notes.has(target.trim()))
          report(file, line, "wikilink", target.trim());
      }
      // 3. ADR numbers, in prose and in code.
      for (const [mention, number] of text.matchAll(/\bADR-(\d{4})\b/g)) {
        if (!adrs.has(number)) report(file, line, "adr", mention);
      }
      // 4. Repository paths in inline code: one token, starting with a tracked top-level folder,
      //    without placeholder characters (a dash range such as 0001–0008 is not a path); a
      //    trailing :line is ignored. A folder's README may write paths relative to itself.
      for (const span of codeSpans) {
        if (
          /[\s<>*{}…$()[\]|?–—]/.test(span) ||
          !topLevel.has(span.split("/")[0]) ||
          !span.includes("/")
        )
          continue;
        const candidate = span.replace(/:\d+(-\d+)?$/, "");
        const fromFile = path.posix.normalize(
          path.posix.join(path.posix.dirname(file), candidate),
        );
        if (!exists(candidate) && !exists(fromFile))
          report(file, line, "path", span);
      }
    });
}

if (hits.length) {
  console.log(`${hits.length} unresolved reference(s):\n${hits.join("\n")}`);
  process.exit(1);
}
console.log(`References OK in ${scanned.length} files.`);
