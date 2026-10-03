// MoonShine OmniFocus bridge: read-only export of the snapshot contract v0.2
// (docs/discovery/snapshot-contract.md).
//
//   osascript -l JavaScript bridge/snapshot.js full
//   osascript -l JavaScript bridge/snapshot.js incremental <ISO 8601 cutoff>
//   osascript -l JavaScript bridge/snapshot.js probe
//
// stdout: one JSON document (snapshot or change probe), or {"error":"notRunning"}.
// stderr: "moonshine-bridge omnifocus_ms=<n>", the time the export held OmniFocus.
// The snapshot carries task titles: never paste its output anywhere.
// Never launches OmniFocus and never writes to it.

ObjC.import('Foundation');

function run(argv) {
  // By bundle id: the name "OmniFocus" can resolve to an installed OmniFocus 3.
  const app = Application('com.omnigroup.OmniFocus4');
  if (!app.running()) return JSON.stringify({ error: 'notRunning' });
  const mode = argv[0] || 'full';
  const modifiedSince = mode === 'incremental' ? argv[1] || null : null;
  if (!['full', 'incremental', 'probe'].includes(mode) || (mode === 'incremental') !== !!modifiedSince) {
    throw new Error('usage: snapshot.js full | incremental <ISO 8601 cutoff> | probe');
  }
  const request = { mode, modifiedSince, timeZone: ObjC.unwrap($.NSTimeZone.localTimeZone.name) };
  const result = app.evaluateJavascript(`(${exportFromOmniFocus.toString()})(${JSON.stringify(request)})`);
  const split = result.indexOf('\n');
  console.log(`moonshine-bridge omnifocus_ms=${result.slice(0, split)}`);
  return result.slice(split + 1);
}

// Runs inside OmniFocus (Omni Automation). Returns "<ms>\n<json>".
function exportFromOmniFocus(request) {
  const started = Date.now();
  const pad = (n) => String(n).padStart(2, '0');
  const iso = (date) => {
    if (!date) return null;
    const offset = -date.getTimezoneOffset();
    const abs = Math.abs(offset);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
      `${offset < 0 ? '-' : '+'}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
  };
  const finish = (body) => {
    const json = JSON.stringify(body);
    return `${Date.now() - started}\n${json}`;
  };
  const now = new Date();
  const header = { schemaVersion: 1, source: 'omnifocus', mode: request.mode };

  if (request.mode === 'probe') {
    let latest = 0;
    const tasks = flattenedTasks;
    for (const task of tasks) latest = Math.max(latest, task.modified ? task.modified.getTime() : 0);
    return finish({
      ...header, generatedAt: iso(now), taskCount: tasks.length,
      latestModified: latest ? iso(new Date(latest)) : null,
    });
  }

  // Window: Monday of the ISO week twelve weeks ago, local midnight.
  const windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 84);
  windowStart.setDate(windowStart.getDate() - ((windowStart.getDay() + 6) % 7));
  const since = request.modifiedSince ? new Date(request.modifiedSince) : null;
  const inWindow = (date) => !!date && date >= windowStart;
  const changed = (task) => {
    for (let item = task; item; item = item.parent) {
      if (item.modified && item.modified >= since) return true;
    }
    const project = task.containingProject;
    return !!project && !!project.task.modified && project.task.modified >= since;
  };

  const folderDropped = (folder) => {
    for (let item = folder; item; item = item.parent) {
      if (item.status === Folder.Status.Dropped) return true;
    }
    return false;
  };
  const projectStatus = (project) => {
    const status = project.status;
    if (status === Project.Status.Active) return 'active';
    if (status === Project.Status.OnHold) return 'onHold';
    if (status === Project.Status.Done) return 'done';
    return 'dropped';
  };
  const isLive = (project) =>
    ['active', 'onHold'].includes(projectStatus(project)) && !folderDropped(project.parentFolder);
  // Whether `taskStatus` reports tasks inside a dropped project or folder as dropped is
  // undocumented, so drops are derived from the containers too.
  const statusCache = new Map();
  const taskStatus = (task) => {
    const id = task.id.primaryKey;
    if (!statusCache.has(id)) statusCache.set(id, readStatus(task));
    return statusCache.get(id);
  };
  const readStatus = (task) => {
    const status = task.taskStatus;
    if (status === Task.Status.Completed) return 'completed';
    const project = task.containingProject;
    if (status === Task.Status.Dropped || task.effectiveDropDate ||
      (project && (projectStatus(project) === 'dropped' || folderDropped(project.parentFolder)))) {
      return 'dropped';
    }
    if (status === Task.Status.Blocked) return 'blocked';
    return 'available';
  };
  // Would the task be in a full snapshot? (contract §Selection)
  const eligibleCache = new Map();
  const eligible = (task) => {
    const id = task.id.primaryKey;
    if (!eligibleCache.has(id)) {
      const status = taskStatus(task);
      const project = task.containingProject;
      eligibleCache.set(id, status === 'completed' ? inWindow(task.completionDate)
        : status !== 'dropped' && (!project || isLive(project)));
    }
    return eligibleCache.get(id);
  };
  const isRootTask = (task) => !!task.project;

  const tasks = [];
  for (const task of flattenedTasks) {
    if (isRootTask(task)) continue;
    const selected = since
      ? (eligible(task) || taskStatus(task) === 'dropped') && changed(task)
      : eligible(task);
    if (selected) tasks.push(task);
  }
  const parentOf = (task) => {
    const parent = task.parent;
    if (!parent || isRootTask(parent)) return null;
    return eligible(parent) || (since && taskStatus(parent) === 'dropped') ? parent.id.primaryKey : null;
  };
  const repeatOf = (task) => {
    const match = /^(.+)\.\d+$/.exec(task.id.primaryKey);
    const live = match ? Task.byIdentifier(match[1]) : null;
    return live && eligible(live) ? match[1] : null;
  };
  const RepetitionType = Task.RepetitionScheduleType || {};
  const AnchorKey = Task.AnchorDateKey || {};
  const repetition = (task) => {
    const rule = task.repetitionRule;
    if (!rule) return null;
    const type = rule.scheduleType;
    const anchor = rule.anchorDateKey;
    return {
      ruleString: rule.ruleString,
      scheduleType: type === RepetitionType.Regularly ? 'regularly'
        : type === RepetitionType.FromCompletion ? 'fromCompletion' : 'none',
      anchorDateKey: anchor === AnchorKey.DeferDate ? 'deferDate'
        : anchor === AnchorKey.PlannedDate ? 'plannedDate' : 'dueDate',
      catchUpAutomatically: !!rule.catchUpAutomatically,
    };
  };
  // plannedDate / effectivePlannedDate need OmniFocus 4.7 / 4.7.1: absent key = older version.
  const planned = (item, key) => (item[key] === undefined ? {} : { [key]: iso(item[key]) });

  const projects = new Map();
  for (const project of flattenedProjects) {
    const status = projectStatus(project);
    if (isLive(project) || (status === 'done' && inWindow(project.completionDate))) {
      projects.set(project.id.primaryKey, project);
    }
  }
  for (const task of tasks) {
    const project = task.containingProject;
    if (project) projects.set(project.id.primaryKey, project);
  }
  const folders = new Map();
  for (const folder of flattenedFolders) {
    if (!folderDropped(folder)) folders.set(folder.id.primaryKey, folder);
  }
  for (const project of projects.values()) {
    for (let folder = project.parentFolder; folder; folder = folder.parent) {
      folders.set(folder.id.primaryKey, folder);
    }
  }

  const time = (key) => {
    const match = /^(\d{1,2}):(\d{2})/.exec(String(settings.objectForKey(key) || ''));
    return match ? `${pad(Number(match[1]))}:${match[2]}` : null;
  };
  const due = time('DefaultDueTime');
  const defer = time('DefaultStartTime');
  const plannedTime = time('DefaultPlannedTime');
  const defaultTimes = due && defer ? { due, defer, ...(plannedTime ? { planned: plannedTime } : {}) } : undefined;

  return finish({
    ...header,
    ...(since ? { modifiedSince: iso(since) } : {}),
    generatedAt: iso(now),
    timeZone: request.timeZone,
    ...(defaultTimes ? { defaultTimes } : {}),
    window: { completedSince: iso(windowStart).slice(0, 10) },
    folders: [...folders.values()].map((folder) => ({
      id: folder.id.primaryKey,
      name: folder.name,
      parentId: folder.parent ? folder.parent.id.primaryKey : null,
      status: folder.status === Folder.Status.Dropped ? 'dropped' : 'active',
    })),
    tags: flattenedTags.map((tag) => ({
      id: tag.id.primaryKey,
      name: tag.name,
      parentId: tag.parent ? tag.parent.id.primaryKey : null,
      status: tag.status === Tag.Status.OnHold ? 'onHold'
        : tag.status === Tag.Status.Dropped ? 'dropped' : 'active',
    })),
    projects: [...projects.values()].map((project) => ({
      id: project.id.primaryKey,
      name: project.name,
      folderId: project.parentFolder ? project.parentFolder.id.primaryKey : null,
      status: projectStatus(project),
      sequential: project.sequential,
      singleActions: project.containsSingletonActions,
      tagIds: project.tags.map((tag) => tag.id.primaryKey),
      deferDate: iso(project.deferDate),
      dueDate: iso(project.dueDate),
      ...planned(project, 'plannedDate'),
      completionDate: iso(project.completionDate),
      nextReviewDate: iso(project.nextReviewDate),
    })),
    tasks: tasks.map((task) => ({
      id: task.id.primaryKey,
      name: task.name,
      projectId: task.containingProject ? task.containingProject.id.primaryKey : null,
      parentTaskId: parentOf(task),
      tagIds: task.tags.map((tag) => tag.id.primaryKey),
      status: taskStatus(task),
      flagged: task.flagged,
      effectiveFlagged: task.effectiveFlagged,
      deferDate: iso(task.deferDate),
      dueDate: iso(task.dueDate),
      ...planned(task, 'plannedDate'),
      effectiveDeferDate: iso(task.effectiveDeferDate),
      effectiveDueDate: iso(task.effectiveDueDate),
      ...planned(task, 'effectivePlannedDate'),
      estimatedMinutes: task.estimatedMinutes,
      completionDate: taskStatus(task) === 'completed' ? iso(task.completionDate) : null,
      added: iso(task.added),
      modified: iso(task.modified),
      repetition: repetition(task),
      repeatOf: repeatOf(task),
      noteLength: task.note ? task.note.length : 0,
    })),
  });
}
