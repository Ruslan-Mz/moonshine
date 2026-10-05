#!/usr/bin/env node
// Checks references in the repository's Markdown, offline and without dependencies:
//   1. relative links [text](path)           → the file or folder exists (#anchor ignored)
//   2. [[wikilinks]] outside code             → a note with that name exists
//   3. every ADR-NNNN mention                 → docs/adr/NNNN-*.md exists
//   4. repo paths in inline code (`docs/…`)   → the path exists (from the repository root or
//                                               from the file's own folder)
// Only tracked files count (git-ignored paths are neither scanned nor targets); fixtures/
// and node_modules/ are not scanned. Fenced code blocks are skipped by every rule.
// Run anywhere in the repository: node scripts/check-refs.mjs. Tests: check-refs.test.mjs.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

// Every exception, with its reason. An entry that no longer matches anything fails the check,
// so it is removed as soon as its reason is gone.
export const ALLOWLIST = [];

// Files where rule 4 does not apply: specs name files still to be created, and the
// append-only method log names files that were renamed or deleted later.
const PATH_RULE_EXEMPT = [/^docs\/specs\//, /^docs\/method\/log\.md$/];

/**
 * @param {string[]} tracked repository-relative paths of all tracked files
 * @param {(file: string) => string} read the content of a tracked file
 * @returns {{ scanned: number, hits: string[] }} unresolved references and unused allowlist entries
 */
export function checkReferences(tracked, read, allowlist = ALLOWLIST) {
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
  const used = new Set();
  const report = (file, line, rule, target) => {
    const allowed = allowlist.find(
      (entry) => entry.rule === rule && entry.target === target,
    );
    if (allowed) used.add(allowed);
    else hits.push(`${file}:${line}  ${rule}  ${target}`);
  };

  for (const file of scanned) {
    // CommonMark: a fence closes only with the same character, at least as long, no info string.
    let fence = null;
    read(file)
      .split("\n")
      .forEach((text, index) => {
        const line = index + 1;
        const marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(text);
        if (fence) {
          const closes =
            marker &&
            marker[1][0] === fence.char &&
            marker[1].length >= fence.length &&
            marker[2].trim() === "";
          if (closes) fence = null;
          return;
        }
        if (marker) {
          fence = { char: marker[1][0], length: marker[1].length };
          return;
        }
        const codeSpans = [...text.matchAll(/`([^`]+)`/g)].map(
          (match) => match[1],
        );
        const prose = text.replace(/`[^`]*`/g, "");

        // 1. Relative links; a target that is not valid percent-encoding is a hit, not a crash.
        for (const [, target] of prose.matchAll(
          /\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
        )) {
          if (/^([a-z][a-z0-9+.-]*:|#)/i.test(target)) continue;
          let relative;
          try {
            relative = decodeURI(target.split("#")[0]);
          } catch {
            report(file, line, "link", target);
            continue;
          }
          const resolved = path.posix.normalize(
            path.posix.join(path.posix.dirname(file), relative),
          );
          if (!exists(resolved)) report(file, line, "link", target);
        }
        // 2. Wikilinks; inside a table the alias separator is escaped as \|.
        for (const [, target] of prose.matchAll(
          /\[\[([^\]|#\\]+)(?:\\?[#|][^\]]*)?\]\]/g,
        )) {
          if (!notes.has(target.trim()))
            report(file, line, "wikilink", target.trim());
        }
        // 3. ADR numbers, in prose and in inline code.
        for (const [mention, number] of text.matchAll(/\bADR-(\d{4})\b/g)) {
          if (!adrs.has(number)) report(file, line, "adr", mention);
        }
        // 4. Repository paths in inline code: one token, starting with a tracked top-level
        //    folder, without placeholder characters (a dash range such as 0001–0008 is not a
        //    path); a trailing #anchor or :line is ignored. A folder's README may write paths
        //    relative to itself.
        if (PATH_RULE_EXEMPT.some((pattern) => pattern.test(file))) return;
        for (const span of codeSpans) {
          if (
            /[\s<>*{}…$()[\]|?–—]/.test(span) ||
            !topLevel.has(span.split("/")[0]) ||
            !span.includes("/")
          )
            continue;
          const candidate = span
            .replace(/#.*$/, "")
            .replace(/:\d+(-\d+)?$/, "");
          const fromFile = path.posix.normalize(
            path.posix.join(path.posix.dirname(file), candidate),
          );
          if (!exists(candidate) && !exists(fromFile))
            report(file, line, "path", span);
        }
      });
  }

  for (const entry of allowlist) {
    if (!used.has(entry)) {
      hits.push(
        `allowlist  ${entry.rule}  ${entry.target}  (matches nothing: remove the entry)`,
      );
    }
  }
  if (scanned.length === 0) hits.push("no Markdown files scanned");
  return { scanned: scanned.length, hits };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  }).trim();
  const tracked = execFileSync("git", ["ls-files", "-z"], {
    cwd: root,
    encoding: "utf8",
  })
    .split("\0")
    .filter(Boolean);
  const { scanned, hits } = checkReferences(tracked, (file) =>
    readFileSync(path.join(root, file), "utf8"),
  );
  if (hits.length) {
    console.log(`${hits.length} unresolved reference(s):\n${hits.join("\n")}`);
    process.exit(1);
  }
  console.log(`References OK in ${scanned} files.`);
}
