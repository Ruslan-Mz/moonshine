// What the push and post guard looks for (CLAUDE.md rule 5): a line of the owner's deny-list, or a
// path inside the vault. Shared by pre-push.mjs and gh-post.mjs; scripts/install-guard.sh copies all
// three outside the checkout. A result is a kind, never the matched text: guard output reaches the
// terminal and session logs.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

// A path into the vault folder, an absolute path to it, or an Obsidian link that names a note. The
// default location alone, as the docs write it (`~/` + the folder), and link templates with `…` pass.
// `[/]`, not `\/`: an escaped slash counts as `/`, so `\/` would make this file match itself.
const vaultPaths = [
  /obsidianv[/]\S/i,
  /[/]users[/][^/\s]+[/]obsidianv(?!\w)/i,
  /obsidian:[/][/]\S*?[?&](?:file|path)=[^&\s`'"…]/i,
];

export function fold(text) {
  return text.normalize("NFC").toLowerCase();
}

/// Escaped spellings of `/` (JSON `\/`, URL `%2F`) count as `/` for the vault check.
function unescapeSlashes(text) {
  return text.replace(/\\\//g, "/").replace(/%2f/gi, "/");
}

/// The deny-list entries, folded. `stop` is called with a message (no entry text) and must not return.
export function denyList(stop) {
  const result = spawnSync("git", ["config", "--path", "--get", "moonshine.denyList"], { encoding: "utf8" });
  const path = result.status === 0 ? result.stdout.trim() : "";
  if (path === "") stop("Set the deny-list path: git config moonshine.denyList <absolute path>.");
  let text;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    stop("The deny-list named by moonshine.denyList cannot be read.");
  }
  const entries = text
    .split(/\r?\n/)
    .map((line) => fold(line.trim()))
    .filter((line) => line !== "");
  if (entries.length === 0) stop("The deny-list named by moonshine.denyList has no entries.");
  return entries;
}

/// What a text matches, as a kind, or null.
export function match(text, entries) {
  const folded = fold(text);
  if (entries.some((entry) => folded.includes(entry))) return "a deny-list entry";
  const plain = unescapeSlashes(text);
  if (vaultPaths.some((pattern) => pattern.test(plain))) return "a vault path";
  return null;
}

/// A file name safe to print: quoted (control characters escaped), or a placeholder when the name
/// itself matches.
export function printable(path, entries) {
  return match(path, entries) ? "a file whose name matches" : JSON.stringify(path);
}
