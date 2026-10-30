// Tests for the guard's matcher (folding, vault paths, deny-list parsing): node --test scripts/matcher.test.mjs
// Every entry is invented. Vault forms are built from parts so this file passes the guard itself.
import assert from "node:assert/strict";
import { test } from "node:test";
import { fold, match, parseDenyList } from "./guard/matcher.mjs";

const vault = "Obsidian" + "V";
const link = "obsidian" + "://";
const entries = parseDenyList("Zephyrine Quolltail\nмирон ёлкин\nselkie\n", fail);

function fail(message) {
  throw new Error(message);
}

function stops(text, expected) {
  assert.throws(() => parseDenyList(text, fail), (error) => {
    assert.ok(error.message.includes(expected), error.message);
    for (const word of ["quolltail", "selkie"]) assert.ok(!error.message.toLowerCase().includes(word), error.message);
    return true;
  });
}

for (const [name, text] of [
  ["NFKC (fullwidth letters)", "ｚｅｐｈｙｒｉｎｅ ｑｕｏｌｌｔａｉｌ"],
  ["a zero-width space inside", "Zephy\u200Brine Quolltail"],
  ["a soft hyphen inside", "Zephy\u00ADrine Quolltail"],
  ["a combining grapheme joiner inside", "Zephy\u034Frine Quolltail"],
  ["a variation selector inside", "Zephy\uFE0Frine Quolltail"],
  ["a no-break space", "Zephyrine\u00A0Quolltail"],
  ["a narrow no-break space", "Zephyrine\u202FQuolltail"],
  ["a tab", "Zephyrine\tQuolltail"],
  ["a doubled space", "Zephyrine  Quolltail"],
  ["upper case", "ZEPHYRINE QUOLLTAIL"],
  ["е in the text for ё in the entry", "Мирон Елкин"],
  ["a decomposed ё", "мирон е\u0308лкин"],
]) {
  test(`an entry is found through ${name}`, () => {
    assert.equal(match(`note: ${text} here`, entries), "a deny-list entry");
  });
}

test("ё in the text matches е in the entry", () => {
  assert.equal(match("сёлки", parseDenyList("селки\n", fail)), "a deny-list entry");
});

test("fold collapses Unicode spaces and maps ё to е", () => {
  assert.equal(fold("A\u00A0\u202F\t  Ё"), "a е");
});

for (const [name, text] of [
  ["an &amp;file= link", `${link}open?vault=x&amp;file=Projects%2FPlan`],
  ["a filepath= link", `${link}advanced-uri?vault=x&filepath=Projects%2FPlan`],
  ["the vault/<name>/ shorthand", `${link}vault/x/Projects/Plan`],
  ["a zero-width space in the vault folder name", `~/Obsidian\u200BV/Projects/Plan.md`],
  ["a fullwidth slash after the vault folder", `~/${vault}\uFF0FProjects`],
  ["a file= link", `${link}open?vault=x&file=Projects`],
]) {
  test(`${name} is a vault path`, () => {
    assert.equal(match(text, entries), "a vault path");
  });
}

for (const [name, text] of [
  ["a … template", `\`${link}open?vault=…&file=…\``],
  ["a ... template", `\`${link}open?vault=...&file=...\``],
  ["file= before a backtick", `\`${link}open?vault=x&file=\``],
  ["the default location", `the vault (\`~/${vault}\`)`],
]) {
  test(`${name} passes`, () => {
    assert.equal(match(text, entries), null);
  });
}

for (const [name, separator] of [
  ["\\r\\n", "\r\n"],
  ["a lone \\r", "\r"],
  ["U+2028", "\u2028"],
  ["U+2029", "\u2029"],
]) {
  test(`the deny-list splits on ${name}`, () => {
    const list = parseDenyList(`alpha one${separator}beta two${separator}`, fail);
    assert.deepEqual(list, ["alpha one", "beta two"]);
  });
}

for (const [name, text, line] of [
  ["a control character", "alpha\nbe\u0007ta\n", 2],
  ["a tab", "alpha\tbeta\n", 1],
  ["NEL", "alpha\u0085beta\n", 1],
  ["U+FFFD (an invalid byte)", "alpha\n\nbeta\uFFFD\n", 3],
]) {
  test(`the deny-list stops on ${name}, naming the line only`, () => {
    stops(text, `line ${line}`);
  });
}

test("a deny-list with no entries stops", () => {
  stops("\n  \n\u200B\n", "no entries");
});

test("blank lines and spaces around entries are dropped", () => {
  assert.deepEqual(parseDenyList("\n  Alpha  \n\nbeta\n", fail), ["alpha", "beta"]);
});
