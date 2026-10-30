#!/usr/bin/env node
// Builds `fixtures/omnifocus.snapshot.json`, the Demo-mode OmniFocus snapshot, from the invented
// dataset of `design/demo-data.md` (owner, 2026-10-28, S4-DD). Every number the design gives is
// pinned by `Adapters/Tests/OmniFocusAdapterTests/DemoDataGoldenTests.swift`; this script only
// writes the tasks that produce them. Edit the tables below, then run
// `node scripts/demo-snapshot.mjs` and the Swift tests. `scripts/demo-snapshot.test.mjs` checks
// that the committed file is this script's output.
//
// Kept on purpose (contract cases other tests pin by id): `prj-0046`, the one project with a due
// date, three folders deep; `tsk-0097`, a completed task inheriting that due date; `tsk-0115` and
// its occurrence `tsk-0115.0`; `tsk-0167`, a flagged task with its own due date; `tsk-0171`, a
// group whose child `tsk-0172` inherits its planned date. `tasks[0]` has `"noteLength": 0`.
import { writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const OFFSET = "+03:00"; // Europe/Moscow, no daylight saving time

/** `2026-10-01T09:00:00+03:00` from a date `2026-10-01` and a time `09:00`. */
const at = (date, time) => `${date}T${time}:00${OFFSET}`;

/** The date `days` after `date` (both `YYYY-MM-DD`). */
function addDays(date, days) {
  const d = new Date(`${date}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

const TODAY = "2026-10-01";
const NOW = at(TODAY, "16:20");
/** Mondays of ISO weeks 33–40 of 2026. */
const WEEKS = [33, 34, 35, 36, 37, 38, 39, 40].map((week, i) => ({
  week,
  monday: addDays("2026-08-10", 7 * i),
}));
const DAILY = { ruleString: "FREQ=DAILY", scheduleType: "regularly", anchorDateKey: "deferDate" };

const folders = [
  ["fld-0001", "Foundation", null],
  ["fld-0002", "Profession", null],
  ["fld-0003", "AI", "fld-0002"],
  ["fld-0004", "Workshops", "fld-0003"],
  ["fld-0005", "Research", "fld-0002"],
  ["fld-0006", "Music", null],
  ["fld-0007", "Strings", "fld-0006"],
  ["fld-0008", "Keys", "fld-0006"],
  ["fld-0009", "Art", null],
  ["fld-0010", "Languages", null],
  ["fld-0011", "Study", null],
  ["fld-0012", "Family", null],
  ["fld-0013", "Home", null],
].map(([id, name, parentId]) => ({ id, name, parentId, status: "active" }));

const tagList = [
  ["tag-0001", "practice", null],
  ["tag-0002", "calisthenics", null],
  ["tag-0003", "исследование", null],
  ["tag-0004", "violin", null],
  ["tag-0005", "piano", null],
  ["tag-0006", "calligraphy", null],
  ["tag-0007", "italian", null],
  ["tag-0008", "japanese", null],
  ["tag-0009", "anchor", null],
  ["tag-0010", "deadline", null],
  ["tag-0011", "Энергия", null],
  ["tag-0012", "Низкая", "tag-0011"],
  ["tag-0013", "Контекст", null],
  ["tag-0014", "Дом", "tag-0013"],
];
const tags = tagList.map(([id, name, parentId]) => ({ id, name, parentId, status: "active" }));
const tagID = Object.fromEntries(tagList.map(([id, name]) => [name, id]));

/** Projects in the design's order of lines; `key` is how the task tables below name them. */
const projectList = [
  { key: "daily", id: "prj-0001", name: "Daily practice", folder: "fld-0001", tags: ["practice"] },
  { key: "mobility", id: "prj-0002", name: "Daily mobility", folder: "fld-0001", tags: ["calisthenics"] },
  { key: "pullups", id: "prj-0003", name: "Pull-up progression", folder: "fld-0001", tags: ["calisthenics"] },
  { key: "technique", id: "prj-0004", name: "Daily technique", folder: "fld-0007", tags: ["violin"] },
  { key: "partita", id: "prj-0005", name: "Bach Partita No. 2", folder: "fld-0007", tags: ["violin"] },
  { key: "etudes", id: "prj-0006", name: "Études", folder: "fld-0007", tags: ["violin"], sequential: true },
  { key: "recital", id: "prj-0007", name: "Recital prep", folder: "fld-0007", tags: ["violin"] },
  { key: "textbook", id: "prj-0008", name: "Linear algebra textbook", folder: "fld-0011", tags: [] },
  { key: "deck", id: "prj-0009", name: "Definitions deck", folder: "fld-0011", tags: [] },
  // The 🤖 line maps these three by project name.
  { key: "eval", id: "prj-0010", name: "Eval toolkit", folder: "fld-0003", tags: [] },
  { key: "reading", id: "prj-0011", name: "Paper reading", folder: "fld-0003", tags: [] },
  { key: "workshop", id: "prj-0046", name: "Workshop 2026", folder: "fld-0004", tags: [], due: at("2026-10-16", "17:00") },
  { key: "drift", id: "prj-0012", name: "Drift paper draft", folder: "fld-0005", tags: ["исследование"] },
  { key: "evenings", id: "prj-0013", name: "Evenings", folder: "fld-0012", tags: [] },
  { key: "weekends", id: "prj-0014", name: "Weekends", folder: "fld-0012", tags: [] },
  { key: "kids", id: "prj-0015", name: "Kids", folder: "fld-0012", tags: [] },
  { key: "familyProjects", id: "prj-0016", name: "Family projects", folder: "fld-0012", tags: [] },
  { key: "italian", id: "prj-0017", name: "Italian B1", folder: "fld-0010", tags: ["italian"] },
  { key: "japanese", id: "prj-0018", name: "Japanese basics", folder: "fld-0010", tags: ["japanese"] },
  { key: "pianoUpkeep", id: "prj-0019", name: "Repertoire upkeep", folder: "fld-0008", tags: ["piano"] },
  { key: "brush", id: "prj-0020", name: "Brush lettering basics", folder: "fld-0009", tags: ["calligraphy"], status: "onHold", sequential: true },
  { key: "household", id: "prj-0021", name: "Household", folder: "fld-0013", tags: [] },
];
const projectByKey = Object.fromEntries(projectList.map((p) => [p.key, p]));
const projects = projectList.map((p) => ({
  id: p.id,
  name: p.name,
  folderId: p.folder,
  status: p.status ?? "active",
  sequential: p.sequential ?? false,
  singleActions: false,
  tagIds: p.tags.map((t) => tagID[t]),
  deferDate: null,
  dueDate: p.due ?? null,
  plannedDate: null,
  completionDate: null,
  nextReviewDate: at("2026-10-05", "09:00"),
}));

const tasks = [];
let nextNumber = 1;
const reserved = new Set(["tsk-0097", "tsk-0115", "tsk-0167", "tsk-0171", "tsk-0172"]);
function newID() {
  let id;
  do id = `tsk-${String(nextNumber++).padStart(4, "0")}`;
  while (reserved.has(id));
  return id;
}

/**
 * One task. Dates: `planned`, `defer`, `due` are own dates; the effective ones are the own date,
 * else the parent's, else (due only) the project's.
 */
function task(project, name, options = {}) {
  const p = project ? projectByKey[project] : null;
  const parent = options.parent ? tasks.find((t) => t.id === options.parent) : null;
  const own = { planned: options.planned ?? null, defer: options.defer ?? null, due: options.due ?? null };
  const record = {
    id: options.id ?? newID(),
    name,
    projectId: p?.id ?? null,
    parentTaskId: parent?.id ?? null,
    tagIds: (options.tags ?? []).map((t) => tagID[t]),
    status: options.done ? "completed" : (options.status ?? (p?.status === "onHold" ? "blocked" : "available")),
    flagged: options.flagged ?? false,
    effectiveFlagged: options.flagged ?? false,
    deferDate: own.defer,
    plannedDate: own.planned,
    dueDate: own.due,
    effectiveDeferDate: own.defer ?? parent?.effectiveDeferDate ?? null,
    effectiveDueDate: own.due ?? parent?.effectiveDueDate ?? p?.due ?? null,
    effectivePlannedDate: own.planned ?? parent?.effectivePlannedDate ?? null,
    estimatedMinutes: options.estimate ?? null,
    completionDate: options.done ?? null,
    added: options.added ?? at("2026-06-01", "10:00"),
    modified: options.done ?? at("2026-09-30", "20:00"),
    repetition: options.repeat ? DAILY : null,
    repeatOf: options.repeatOf ?? null,
    noteLength: 0,
  };
  tasks.push(record);
  return record;
}

/** A repeating task; its completed occurrences are made by `session`. */
const repeats = {};
function repeating(key, project, name, estimate, options = {}) {
  repeats[key] = task(project, name, { ...options, estimate, repeat: true });
  return repeats[key];
}
let occurrenceIndex = {};
function session(key, done, options = {}) {
  const live = repeats[key];
  const n = (occurrenceIndex[key] = (occurrenceIndex[key] ?? -1) + 1);
  return task(live.projectId ? projectList.find((p) => p.id === live.projectId).key : null, live.name, {
    id: `${live.id}.${n}`,
    tags: tagList.filter(([id]) => live.tagIds.includes(id)).map(([, name]) => name),
    estimate: live.estimatedMinutes,
    repeat: true,
    repeatOf: live.id,
    done,
    added: at(addDays(done.slice(0, 10), -1), "06:00"),
    ...options,
  });
}

const planned = (date) => at(date, "09:00"); // the default planned time: date only
const deferred = (date) => at(date, "06:00"); // the default defer time
const todayPlanned = planned(TODAY);

// ── Open tasks and live repeats, in the order of the design's Today table ────────────────
// Repeats done today have their next copy deferred to tomorrow (not available); open repeats
// are deferred to today.
const tomorrow = deferred(addDays(TODAY, 1));

repeating("morning", "daily", "Morning session", 90, { tags: ["anchor"], defer: tomorrow, status: "blocked" });
repeating("evening", "daily", "Evening session", 60, { tags: ["anchor"], defer: deferred(TODAY) });
task("daily", "Plan the retreat day", { planned: planned("2026-10-10"), estimate: 30 });

repeating("violin15", "technique", "Violin 15 min", 15, { tags: ["anchor"], defer: tomorrow, status: "blocked" });
repeating("scales", "technique", "Scales & arpeggios — G minor, 3 octaves", 20, { defer: tomorrow, status: "blocked" });
task("partita", "Allemande, bars 1–16 at ♩ = 60", { planned: at(TODAY, "20:30"), flagged: true, estimate: 45 });
task("partita", "Record bars 1–8, listen back with the score", { planned: todayPlanned, estimate: 15 });
task("partita", "Sarabande — first read-through", { planned: planned("2026-10-06"), estimate: 30 });
task("etudes", "Kreutzer No. 2 — détaché, slow bow", { planned: todayPlanned, estimate: 25 });
task("etudes", "Kreutzer No. 3 — legato", { estimate: 25, status: "blocked" });
task("recital", "Send recital repertoire list to teacher", { tags: ["violin", "deadline"], due: at(TODAY, "18:00"), estimate: 10 });
task("recital", "Book rehearsal room for November", { tags: ["violin"], due: at("2026-10-02", "12:00"), estimate: 10 });
task("recital", "Choose an encore piece", { tags: ["violin"], estimate: 30 });
task("recital", "Restring with the new set", { tags: ["violin"], estimate: 20 });
task("recital", "Vibrato drill — slow, with the metronome", { tags: ["violin"], planned: planned("2026-10-07"), estimate: 15 });

task("textbook", "Chapter 3.A — exercises 1–6", { planned: todayPlanned, flagged: true, estimate: 60 });
task("textbook", "Re-derive rank–nullity from memory", { planned: todayPlanned, estimate: 20 });
task("textbook", "Find a problem book for ch. 4", { estimate: 15 });
task("textbook", "Write a one-page summary of ch. 2", { estimate: 45 });
repeating("deck", "deck", "Definitions deck — 15 cards", 10, { planned: at(TODAY, "12:00") });
repeating("proof", "textbook", "Proof practice — one theorem", 30, { defer: tomorrow, status: "blocked" });

task("eval", "Eval harness — deterministic seeds", { planned: todayPlanned, flagged: true, estimate: 90 });
task("reading", "Notes on conformal prediction intervals", { planned: todayPlanned, estimate: 40 });
task("workshop", "Submit workshop abstract", {
  id: "tsk-0167",
  tags: ["deadline"],
  flagged: true,
  due: at(TODAY, "23:59"),
  estimate: 30,
});
task("eval", "Refactor tokenizer benchmark script", { planned: planned("2026-09-29"), estimate: 45 });

task("drift", "Outline section 3 — method", { planned: todayPlanned, flagged: true, estimate: 45 });
task("drift", "Export 12 weeks of session logs", { planned: todayPlanned, estimate: 30 });
task("drift", "Email co-author about the dataset licence", { planned: planned("2026-09-28"), estimate: 10 });

repeating("walk", "mobility", "Walk 30 min", 30, { tags: ["anchor"], defer: tomorrow, status: "blocked" });
repeating("mobilityDrill", "mobility", "Mobility — hips & shoulders", 15, { defer: tomorrow, status: "blocked" });
repeating("pull", "pullups", "Pull session — 5 × 5 band-assisted + negatives", 40, {
  id: "tsk-0115",
  defer: deferred(TODAY),
});
repeating("longWalk", "mobility", "Long walk — 90 min", 90, { defer: deferred("2026-10-05"), status: "blocked" });
task("pullups", "Buy parallettes", { estimate: 15 });

repeating("reading", "evenings", "Evening reading with the kids", 20, { tags: ["anchor"], defer: deferred(TODAY) });
task("weekends", "Plan Saturday trip to the lake", { planned: todayPlanned, estimate: 15, done: at(TODAY, "12:45") });
task("kids", "Book dentist appointment for the kids", { planned: planned("2026-09-26"), estimate: 5 });
task("familyProjects", "Photo book for 2026", { estimate: 90 });

// 🇮🇹: the tray's two lessons first, so "Lesson 15" is the line's next step.
task("italian", "Lesson 15 — passato prossimo", { estimate: 30 });
task("italian", "Podcast episode 12, with transcript", { estimate: 25 });
repeating("podcast", "italian", "Italian podcast — 20 min", 20, { defer: deferred("2026-09-01") });

task("japanese", "Hiragana row あ–お", { planned: planned("2026-10-05"), estimate: 10 });
task("japanese", "Install a kana flashcard app", { planned: planned("2026-10-06"), estimate: 5 });

repeating("piano", "pianoUpkeep", "Play through one piece", 20, { defer: deferred("2026-08-27") });

task("brush", "Basic strokes sheet", { estimate: 30, tags: ["Низкая"] });
task("brush", "Lowercase alphabet", { estimate: 45 });

// Life ops: three in Household, two in the inbox, all planned today; three more undated.
task("household", "Pay electricity bill", { planned: todayPlanned, estimate: 5 });
task("household", "Return parcel at the post office", { planned: todayPlanned, estimate: 20, tags: ["Дом"] });
task("household", "Compare car insurance quotes", { planned: todayPlanned, estimate: 30 });
task(null, "Process inbox — 3 items", { planned: todayPlanned, estimate: 15 });
task(null, "Order printer toner", { planned: todayPlanned, estimate: 5 });
task(null, "Idea: metronome app", {});
task(null, "Look up bow rehair price", {});
task(null, "Сдать анализы", {});
// A group planned next Monday: its children inherit the date.
task("household", "Prepare the garage sale", { id: "tsk-0171", planned: planned("2026-10-05") });
task("household", "Sort the boxes", { id: "tsk-0172", parent: "tsk-0171", estimate: 60 });
task("household", "Price tags", { parent: "tsk-0171", estimate: 30 });

// ── Today's completions (`design/demo-data.md` § Draft-3: Mobility 07:30, Scales 15:00) ───
session("morning", at(TODAY, "07:40"));
session("mobilityDrill", at(TODAY, "07:50"), { planned: at(TODAY, "07:30") });
session("walk", at(TODAY, "08:40"));
session("violin15", at(TODAY, "14:55"));
session("scales", at(TODAY, "15:25"), { planned: at(TODAY, "15:00") });

// ── History W33–W40: § Weekly stats, Draft-4's 🧘 row, Draft-5's W40 notes ───────────────
// Sessions (rhythm) and one-offs (progress) per week; W40 counts exclude today's completions
// above and fall on Mon–Wed.
const history = {
  core: { rhythm: [12, 13, 11, 9, 12, 13, 14, 7], repeats: ["morning", "evening"] },
  violin: { rhythm: [6, 5, 2, 1, 3, 6, 6, 2], progress: [1, 2, 0, 0, 1, 2, 1, 1], repeats: ["violin15", "scales"], project: "partita", title: (i) => `Partita — passage ${i}` },
  math: { rhythm: [2, 3, 2, 1, 2, 2, 3, 0], progress: [2, 1, 2, 1, 2, 2, 1, 0], repeats: ["deck"], project: "textbook", title: (i) => `Exercises, set ${i}` },
  ai: { progress: [3, 4, 2, 3, 3, 4, 2, 3], project: "eval", title: (i) => `Eval run ${i} — write-up` },
  research: { progress: [1, 2, 1, 0, 1, 2, 1, 0], project: "drift", title: (i) => `Drift paper — note ${i}` },
  calisthenics: { rhythm: [4, 4, 3, 2, 3, 4, 4, 0], progress: [0, 1, 0, 0, 0, 1, 0, 0], repeats: ["walk", "mobilityDrill", "pull"], project: "pullups", title: (i) => `Max test ${i}` },
  family: { rhythm: [5, 6, 4, 6, 5, 5, 4, 3], progress: [1, 0, 1, 1, 0, 2, 1, 0], repeats: ["reading"], project: "kids", title: (i) => `Family errand ${i}` },
  italian: { rhythm: [3, 2, 1, 0, 0, 0, 0, 0], progress: [1, 1, 0, 0, 0, 0, 0, 0], repeats: ["podcast"], project: "italian", title: (i) => `Lesson ${11 + i}` },
  piano: { rhythm: [2, 1, 1, 0, 0, 0, 0, 0], repeats: ["piano"] },
  lifeOps: { progress: [2, 1, 2, 1, 2, 1, 2, 1], project: "household", title: (i) => `Household chore ${i}` },
};

/** `count` completion times spread over `days` days from `monday`, from 08:00, 90 min apart. */
function spread(monday, count, days) {
  const perDay = {};
  return Array.from({ length: count }, (_, i) => {
    const day = Math.floor((i * days) / count);
    const slot = (perDay[day] = (perDay[day] ?? -1) + 1);
    const minutes = 8 * 60 + 90 * slot + (day % 3) * 10;
    const time = `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
    return at(addDays(monday, day), time);
  });
}

let firstAI = true;
for (const [line, h] of Object.entries(history)) {
  let oneOff = 0;
  WEEKS.forEach(({ week, monday }, w) => {
    const days = week === 40 ? 3 : 7;
    spread(monday, h.rhythm?.[w] ?? 0, days).forEach((done, i) => session(h.repeats[i % h.repeats.length], done));
    // One-offs late in the day, after the sessions.
    spread(monday, h.progress?.[w] ?? 0, days).forEach((done) => {
      oneOff += 1;
      const late = done.replace(/T\d\d:\d\d/, (m) => `T${String(Number(m.slice(1, 3)) + 10).padStart(2, "0")}:${m.slice(4, 6)}`);
      if (line === "ai" && firstAI) {
        // The completed task that inherits its project's due date.
        firstAI = false;
        task("workshop", "Draft the workshop proposal", { id: "tsk-0097", estimate: 60, done: late });
      } else {
        task(h.project, h.title(oneOff), { estimate: 30, done: late, tags: h.project === "recital" ? ["violin"] : [] });
      }
    });
  });
}

// W40 extras the table spreads cannot place: 📐 Monday's proof (the session), the last 📐, 🤖
// and 🔬 completions on Wed, Wed and Tue (Draft-5, Lines: yesterday, yesterday, 2 days ago),
// 💪's two long walks on Mon and Wed, and 🇮🇹 / 🎹 last on Wed 2 Sep, as one-offs (W36 rhythm
// is 0 in the design; progress `…` leaves room).
session("proof", at("2026-09-28", "07:00"));
task("textbook", "Exercises, set 14", { estimate: 30, done: at("2026-09-30", "21:00") });
task("drift", "Drift paper — note 10", { estimate: 30, done: at("2026-09-29", "21:00") });
session("longWalk", at("2026-09-28", "18:00"));
session("longWalk", at("2026-09-30", "18:00"));
task("italian", "Lesson 14 review", { estimate: 30, done: at("2026-09-02", "19:00") });
task("pianoUpkeep", "Nocturne — fingering review", { estimate: 20, done: at("2026-09-02", "20:00") });

/** The snapshot document, as the bridge writes it. */
export function build() {
  return {
    schemaVersion: 1,
    source: "omnifocus",
    mode: "full",
    generatedAt: NOW,
    timeZone: "Europe/Moscow",
    defaultTimes: { due: "17:00", defer: "06:00", planned: "09:00" },
    // The bridge's window at this "now": the Monday of the ISO week holding the day 84 days back.
    window: { completedSince: "2026-07-06" },
    folders,
    tags,
    projects,
    tasks,
  };
}

/** The file's text: one-space indent, as committed. */
export function render() {
  return `${JSON.stringify(build(), null, 1)}\n`;
}

export const target = fileURLToPath(new URL("../fixtures/omnifocus.snapshot.json", import.meta.url));

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  writeFileSync(target, render());
  console.log(`wrote ${target}: ${tasks.length} tasks`);
}
