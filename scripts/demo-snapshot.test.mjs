// The committed Demo snapshot is the generator's output: node --test scripts/demo-snapshot.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { build, render, target } from "./demo-snapshot.mjs";

test("the committed snapshot is what the generator writes", () => {
  assert.equal(readFileSync(target, "utf8"), render());
});

test("task ids are unique and every reference resolves", () => {
  const { projects, tasks, tags, folders } = build();
  const ids = new Set(tasks.map((t) => t.id));
  assert.equal(ids.size, tasks.length);
  const projectIDs = new Set(projects.map((p) => p.id));
  const tagIDs = new Set(tags.map((t) => t.id));
  const folderIDs = new Set(folders.map((f) => f.id));
  for (const t of tasks) {
    assert.ok(t.projectId === null || projectIDs.has(t.projectId), t.id);
    assert.ok(t.parentTaskId === null || ids.has(t.parentTaskId), t.id);
    assert.ok(t.repeatOf === null || ids.has(t.repeatOf), t.id);
    assert.ok(t.tagIds.every((id) => tagIDs.has(id)), t.id);
  }
  assert.ok(projects.every((p) => folderIDs.has(p.folderId)));
});

test("the ids other tests pin are present", () => {
  const ids = new Set(build().tasks.map((t) => t.id));
  for (const id of ["tsk-0097", "tsk-0115", "tsk-0115.0", "tsk-0167", "tsk-0171", "tsk-0172"]) {
    assert.ok(ids.has(id), id);
  }
  assert.ok(build().projects.some((p) => p.id === "prj-0046" && p.dueDate !== null));
});
