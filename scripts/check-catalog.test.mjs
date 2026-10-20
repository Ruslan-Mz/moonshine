import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bannedWords, checkCatalog } from "./check-catalog.mjs";

const script = new URL("./check-catalog.mjs", import.meta.url).pathname;
const glossary = readFileSync(new URL("../design/tone-glossary.md", import.meta.url), "utf8");
const banned = bannedWords(glossary);

const unit = (value) => ({ stringUnit: { state: "translated", value } });
const plain = (en, ru) => ({ localizations: { en: unit(en), ru: unit(ru) } });
const plural = (en, ru) => ({
  localizations: {
    en: { variations: { plural: Object.fromEntries(Object.entries(en).map(([k, v]) => [k, unit(v)])) } },
    ru: { variations: { plural: Object.fromEntries(Object.entries(ru).map(([k, v]) => [k, unit(v)])) } },
  },
});
const catalog = (strings) => ({ sourceLanguage: "en", strings, version: "1.0" });

const days = plural(
  { one: "%lld day", other: "%lld days" },
  { one: "%lld день", few: "%lld дня", many: "%lld дней", other: "%lld дня" },
);

test("the glossary's banned words are read per language", () => {
  assert.ok(banned.en.includes("overdue"));
  assert.ok(banned.en.includes("streak broken"));
  assert.ok(banned.ru.includes("просрочено"));
  assert.ok(banned.ru.includes("провалено"));
  assert.ok(banned.ru.includes("ты должен"));
  assert.ok(banned.it.includes("sei indietro"));
});

test("a clean catalog has no finding", () => {
  assert.deepEqual(checkCatalog(catalog({ Later: plain("Later", "Позже"), "%lld days": days }), banned), []);
});

test("a banned word in a translation, a variation or the source key is found", () => {
  const findings = checkCatalog(
    catalog({
      "Overdue tasks": plain("Tasks", "Задачи"),
      Status: plain("Status", "Просрочено"),
      "%lld items": plural(
        { one: "%lld item", other: "%lld missed items" },
        { one: "%lld", few: "%lld", many: "%lld", other: "%lld" },
      ),
    }),
    banned,
  );
  assert.deepEqual(findings, [
    'Overdue tasks [en]: banned word "overdue"',
    'Status [ru]: banned word "просрочено"',
    '%lld items [en]: banned word "missed"',
  ]);
});

test("a phrase matches whole words only", () => {
  assert.deepEqual(checkCatalog(catalog({ Translate: plain("Translate later", "Позже") }), banned), []);
  assert.deepEqual(checkCatalog(catalog({ Behind: plain("Behind", "Сзади") }), banned), [
    'Behind [en]: banned word "behind"',
  ]);
});

test("every Russian plural category is required, and a plural in one language needs one in all", () => {
  const missingFew = plural(
    { one: "%lld task", other: "%lld tasks" },
    { one: "%lld задача", many: "%lld задач", other: "%lld задачи" },
  );
  const onlyEnglish = {
    localizations: {
      en: { variations: { plural: { one: unit("%lld task"), other: unit("%lld tasks") } } },
      ru: unit("%lld задач"),
    },
  };
  assert.deepEqual(checkCatalog(catalog({ a: missingFew, b: onlyEnglish }), banned), [
    'a [ru]: plural "few" missing',
    "b [ru]: no plural variations",
  ]);
});

test("the command fails on a finding and passes a clean folder", () => {
  const dir = mkdtempSync(join(tmpdir(), "check-catalog-"));
  try {
    mkdirSync(join(dir, "clean"));
    mkdirSync(join(dir, "dirty"));
    writeFileSync(join(dir, "clean", "Localizable.xcstrings"), JSON.stringify(catalog({ "%lld days": days })));
    writeFileSync(join(dir, "dirty", "Localizable.xcstrings"), JSON.stringify(catalog({ Late: plain("Late", "Поздно") })));
    const status = (folder) => {
      try {
        execFileSync("node", [script, join(dir, folder)], { stdio: "pipe" });
        return 0;
      } catch (error) {
        return error.status;
      }
    };
    assert.equal(status("clean"), 0);
    assert.equal(status("dirty"), 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
