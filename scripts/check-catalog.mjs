#!/usr/bin/env node
// Checks every String Catalog (`*.xcstrings`) under the given folders (ADR-0009 § Confirmation;
// owner, 2026-10-21, PR #30 round 1):
// - no banned word of `design/tone-glossary.md` § "Banned words (intentions, lines, plans)" in
//   any string of its language, the English source keys included; a phrase matches as whole
//   words, case ignored ("late" does not match "later");
// - every plural entry has the categories its language needs: en one, other; ru one, few,
//   many, other; a key with a plural in one language has a plural in every language.
// The literal-string check of the same Confirmation comes with S4-3c.
// Usage: node scripts/check-catalog.mjs [folder…] (default `Apps`). Exit 0 clean, 1 with
// `file: key [language]: rule` per finding, 2 when the glossary or a catalog cannot be read.

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";
import { pathToFileURL } from "node:url";

export const pluralCategories = { en: ["one", "other"], ru: ["one", "few", "many", "other"] };

/** Banned phrases per lowercase language code, from the glossary's banned-words table. */
export function bannedWords(glossary) {
  const start = glossary.indexOf("## Banned words (intentions, lines, plans)");
  if (start < 0) throw new Error("no banned-words table");
  const section = glossary.slice(start).split(/\n## /)[0];
  const banned = {};
  for (const line of section.split("\n")) {
    const cells = line.split("|").map((cell) => cell.trim());
    if (cells.length < 4 || !/^[A-Z]{2}$/.test(cells[1])) continue;
    banned[cells[1].toLowerCase()] = cells[2]
      .split(/\s+[·/]\s+/)
      .map((phrase) => phrase.trim())
      .filter(Boolean);
  }
  if (Object.keys(banned).length === 0) throw new Error("empty banned-words table");
  return banned;
}

function phraseMatcher(phrase) {
  const escaped = phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "\\s+");
  return new RegExp(`(?<![\\p{L}\\p{N}])${escaped}(?![\\p{L}\\p{N}])`, "iu");
}

/** Every string value under a localization: its unit and all variations, recursively. */
function values(node) {
  if (!node || typeof node !== "object") return [];
  const found = [];
  if (typeof node.stringUnit?.value === "string") found.push(node.stringUnit.value);
  for (const kind of Object.values(node.variations ?? {})) {
    for (const variant of Object.values(kind ?? {})) found.push(...values(variant));
  }
  if (node.substitutions) {
    for (const substitution of Object.values(node.substitutions)) found.push(...values(substitution));
  }
  return found;
}

/** Findings for one parsed catalog, as `key [language]: rule`. */
export function checkCatalog(catalog, banned) {
  const findings = [];
  const source = catalog.sourceLanguage ?? "en";
  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    const localizations = entry.localizations ?? {};
    const texts = Object.fromEntries(
      Object.entries(localizations).map(([language, node]) => [language, values(node)]),
    );
    texts[source] = [...(texts[source] ?? []), key];
    for (const [language, strings] of Object.entries(texts)) {
      for (const phrase of banned[language] ?? []) {
        if (strings.some((text) => phraseMatcher(phrase).test(text))) {
          findings.push(`${key} [${language}]: banned word "${phrase}"`);
        }
      }
    }
    const plurals = Object.entries(localizations).filter(([, node]) => node.variations?.plural);
    if (plurals.length === 0) continue;
    for (const language of Object.keys(pluralCategories)) {
      const plural = localizations[language]?.variations?.plural;
      if (!plural) {
        findings.push(`${key} [${language}]: no plural variations`);
        continue;
      }
      for (const category of pluralCategories[language]) {
        if (!plural[category]) findings.push(`${key} [${language}]: plural "${category}" missing`);
      }
    }
  }
  return findings;
}

function catalogsUnder(folder) {
  if (!existsSync(folder)) return [];
  if (statSync(folder).isFile()) return folder.endsWith(".xcstrings") ? [folder] : [];
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) return [];
    const path = join(folder, entry.name);
    return entry.isDirectory() ? catalogsUnder(path) : path.endsWith(".xcstrings") ? [path] : [];
  });
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const root = new URL("..", import.meta.url).pathname;
  const folders = process.argv.slice(2);
  let banned;
  try {
    banned = bannedWords(readFileSync(join(root, "design/tone-glossary.md"), "utf8"));
  } catch (error) {
    console.error(`check-catalog: cannot read the banned words: ${error.message}`);
    process.exit(2);
  }
  const catalogs = (folders.length ? folders : [join(root, "Apps")]).flatMap(catalogsUnder);
  const findings = [];
  for (const path of catalogs) {
    let catalog;
    try {
      catalog = JSON.parse(readFileSync(path, "utf8"));
    } catch {
      console.error(`check-catalog: cannot read ${relative(root, path)}`);
      process.exit(2);
    }
    for (const finding of checkCatalog(catalog, banned)) {
      findings.push(`${relative(root, path)}: ${finding}`);
    }
  }
  if (findings.length) {
    console.log(findings.join("\n"));
    process.exit(1);
  }
  console.log(`String Catalogs: clean (${catalogs.length})`);
}
