// The last step of scripts/xcbuild.sh: runs xcodebuild (under caffeinate when the script found it)
// in its own process group, within a time limit (P-GX, owner 2026-11-28: a test run sat for 4.5 h
// after the lid closed and its test host lost the display). node's timers are monotonic, and on
// macOS they do not advance while the Mac sleeps, so the limit counts awake minutes. Exit 5 is the
// limit, decided by its own timer, never by the wall clock; otherwise the command's own status, or
// 128 + n for a signal. A signal to the runner goes to the whole group first, and the runner exits
// only after the command has. Installed next to xcbuild.sh, like the project check.
// Tests: node --test scripts/xcbuild.test.mjs
import { spawn } from "node:child_process";
import { constants } from "node:os";

const limitMs = 1_800_000;
const graceMs = 10_000;
// Tests lower the limit, in whole seconds; any other value, or one not below the limit, is ignored.
const asked = process.env.MOONSHINE_XCBUILD_TEST_LIMIT ?? "";
const runMs = /^[1-9][0-9]{0,3}$/.test(asked) ? Math.min(limitMs, Number(asked) * 1000) : limitMs;

const [command, ...args] = process.argv.slice(2);
if (!command) {
  process.stderr.write("usage: xcbuild-run.mjs <command> [<argument>…]\n");
  process.exit(2);
}

const child = spawn(command, args, { detached: true, stdio: "inherit" });
const group = (signal) => {
  try {
    process.kill(-child.pid, signal);
  } catch {
    // gone already
  }
};
let timedOut = false;
let stopping = null;
const timers = [];
const stop = (signal) => {
  group(signal);
  timers.push(setTimeout(() => group("SIGKILL"), graceMs));
};
timers.push(
  setTimeout(() => {
    timedOut = true;
    stop("SIGTERM");
  }, runMs),
);
for (const name of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(name, () => {
    stopping ??= name;
    stop(name);
  });
}
child.on("error", () => {
  process.stderr.write(`xcbuild: ${command} could not be started.\n`);
  process.exit(2);
});
child.on("exit", (code, signal) => {
  timers.forEach(clearTimeout);
  if (timedOut || stopping) group("SIGKILL");
  if (timedOut) {
    const named = runMs === limitMs ? "30 awake minutes" : `${runMs / 1000} awake seconds, lowered for a test`;
    process.stderr.write(
      `xcbuild: stopped at the time limit of ${named}; nothing more ran. A closed lid or a test host that cannot start leaves a run waiting (CLAUDE.md → Commands).\n`,
    );
    process.exit(5);
  }
  if (stopping) process.exit(128 + constants.signals[stopping]);
  process.exit(code ?? 128 + constants.signals[signal]);
});
