// Tests for check-refs.mjs on an in-memory repository: node --test scripts/
import assert from "node:assert/strict";
import { test } from "node:test";
import { checkReferences } from "./check-refs.mjs";

const fence = "```";
const base = {
  "docs/adr/0001-first.md": "# ADR",
  "docs/note.md": "# Note\n\n## Intro",
  "design/README.md": "Files: `prompts/p.md`.",
  "design/prompts/p.md": "prompt",
  "fixtures/vault/n.md": "[[missing-in-fixture]]",
};

function run(files, allowlist = []) {
  const all = { ...base, ...files };
  return checkReferences(Object.keys(all), (file) => all[file], allowlist);
}

test("valid references produce no hits", () => {
  const { hits, scanned } = run({
    "docs/ok.md": [
      "[link](note.md#intro) [[note]] [[0001-first|alias]] ADR-0001",
      "`docs/note.md` `docs/note.md:3` `docs/note.md#intro` `docs/<name>.md` `docs/adr/0001–0002`",
      "| a | [[note\\|alias]] |",
    ].join("\n"),
  });
  assert.deepEqual(hits, []);
  assert.equal(scanned, 5);
});

test("each rule reports its broken reference once", () => {
  const { hits } = run({
    "docs/bad.md": "[gone](missing.md#x) [[nowhere]] ADR-0099 `docs/nope.md`",
  });
  assert.deepEqual(hits, [
    "docs/bad.md:1  link  missing.md#x",
    "docs/bad.md:1  wikilink  nowhere",
    "docs/bad.md:1  adr  ADR-0099",
    "docs/bad.md:1  path  docs/nope.md",
  ]);
});

test("code spans and fenced blocks are skipped; a fence closes only on its own marker", () => {
  const { hits } = run({
    "docs/code.md": [
      "`[[inside-code]]` `[x](inside.md)`",
      "~~~markdown",
      fence,
      "[[in-fence]] [y](fence.md) ADR-0098",
      "~~~",
      "[after](after-fence.md)",
    ].join("\n"),
  });
  assert.deepEqual(hits, ["docs/code.md:6  link  after-fence.md"]);
});

test("a malformed percent-encoding is a hit, not a crash", () => {
  const { hits } = run({ "docs/pct.md": "[x](100%-plan.md)" });
  assert.deepEqual(hits, ["docs/pct.md:1  link  100%-plan.md"]);
});

test("specs and the method log are exempt from the path rule only", () => {
  const { hits } = run({
    "docs/specs/phase.md": "`docs/to-be-created.md` [x](gone.md)",
    "docs/method/log.md": "`Adapters/Old.swift` ADR-0097",
    "docs/method/log/2026-11.md": "`docs/old.md` ADR-0098",
    "docs/method/log/notes.md": "`docs/old.md`",
  });
  assert.deepEqual(hits, [
    "docs/specs/phase.md:1  link  gone.md",
    "docs/method/log.md:1  adr  ADR-0097",
    "docs/method/log/2026-11.md:1  adr  ADR-0098",
    "docs/method/log/notes.md:1  path  docs/old.md",
  ]);
});

test("an allowlist entry hides its hit, and an unused entry fails", () => {
  const allowlist = [
    { rule: "adr", target: "ADR-0012", reason: "lands later" },
    { rule: "adr", target: "ADR-0013", reason: "already landed" },
  ];
  const { hits } = run({ "docs/a.md": "ADR-0012" }, allowlist);
  assert.deepEqual(hits, [
    "allowlist  adr  ADR-0013  (matches nothing: remove the entry)",
  ]);
});

test("scanning no Markdown file fails", () => {
  const { hits } = checkReferences(["Package.swift"], () => "", []);
  assert.deepEqual(hits, ["no Markdown files scanned"]);
});
