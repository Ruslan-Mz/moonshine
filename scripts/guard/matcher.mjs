// What the push and post guard looks for (CLAUDE.md rule 5): a line of the owner's deny-list, or a
// path inside the vault; and text it cannot scan (binary data, invalid UTF-8). Shared by
// pre-push.mjs and gh-post.mjs; scripts/install-guard.sh copies the guard folder outside the
// checkout, with a config.json naming the deny-list and the scratchpad roots. A result is a kind,
// never the matched text: guard output reaches the terminal and session logs.
import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

// A path into the vault folder, an absolute path to it, or an Obsidian link that names a note. The
// default location alone, as the docs write it (`~/` + the folder), and link templates with `…`
// (folded to `...`) pass. `[/]`, not `\/`: an escaped slash counts as `/`, so `\/` would make this
// file match itself. The patterns run on folded text.
const vaultPaths = [
  /obsidianv[/]\S/,
  /[/]users[/][^/\s]+[/]obsidianv(?!\w)/,
  /obsidian:[/][/]\S*?[?&](?:amp;)?(?:file|path|filepath)=(?!\.\.\.)[^&\s`'"]/,
  /obsidian:[/][/]vault[/][^/\s]+[/]\S/,
];

/// Entries and text alike: NFKC, lower case, no invisible characters, one kind of space, е for ё.
export function fold(text) {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\p{Default_Ignorable_Code_Point}\p{Cf}]/gu, "")
    .replace(/\s+/gu, " ")
    .replace(/ё/g, "е");
}

/// Escaped spellings of `/` (JSON `\/`, URL `%2F`) count as `/` for the vault check.
function unescapeSlashes(text) {
  return text.replace(/\\\//g, "/").replace(/%2f/gi, "/");
}

/// The installed config.json next to this file: { denyList, scratchRoots }. `stop` is called with
/// a message (no path) and must not return.
export function config(stop) {
  let value;
  try {
    value = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "config.json"), "utf8"));
  } catch {
    stop("No readable config.json next to the guard; run scripts/install-guard.sh.");
  }
  const absolute = (path) => typeof path === "string" && isAbsolute(path);
  if (!absolute(value?.denyList)) stop("config.json names no absolute deny-list path; run scripts/install-guard.sh.");
  const roots = value.scratchRoots;
  if (!Array.isArray(roots) || roots.length === 0 || !roots.every(absolute)) {
    stop("config.json names no absolute scratchpad roots; run scripts/install-guard.sh.");
  }
  return value;
}

/// The deny-list entries, folded. A line holding a control character or U+FFFD (what an invalid
/// byte reads as) stops, with its line number only.
export function parseDenyList(text, stop) {
  const entries = [];
  text.split(/\r\n|[\n\r\u2028\u2029]/).forEach((line, index) => {
    if (/[\p{Cc}\uFFFD]/u.test(line)) {
      stop(`The deny-list has a control character or an invalid byte on line ${index + 1}.`);
    }
    const entry = fold(line).trim();
    if (entry !== "") entries.push(entry);
  });
  if (entries.length === 0) stop("The deny-list has no entries.");
  return entries;
}

/// The entries of the deny-list named in config.json.
export function denyList(stop) {
  const path = config(stop).denyList;
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    stop("The deny-list named in config.json cannot be read.");
  }
  return parseDenyList(text, stop);
}

/// What a text matches, as a kind, or null.
export function match(text, entries) {
  const folded = fold(text);
  if (entries.some((entry) => folded.includes(entry))) return "a deny-list entry";
  const plain = unescapeSlashes(folded);
  if (vaultPaths.some((pattern) => pattern.test(plain))) return "a vault path";
  return null;
}

const utf8 = new TextDecoder("utf-8", { fatal: true });

/// Why bytes cannot be scanned as text, or null: a NUL or another C0 control besides tab, line
/// feed, form feed and carriage return (binary data, UTF-16), or bytes that are not UTF-8.
export function unreadable(bytes) {
  if (/[\x00-\x08\x0b\x0e-\x1f]/.test(bytes.toString("latin1"))) return "binary data";
  try {
    utf8.decode(bytes);
  } catch {
    return "invalid UTF-8";
  }
  return null;
}

/// A file name safe to print: quoted (control characters escaped), or a placeholder when the name
/// itself matches.
export function printable(path, entries) {
  return match(path, entries) ? "a file whose name matches" : JSON.stringify(path);
}
