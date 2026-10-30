#!/usr/bin/python3
"""PreToolUse hook for Read, Grep and Glob: deny any read outside the read boundary.

The sandbox's `denyRead` limits Bash only; Claude's built-in file tools follow permission rules
and hooks instead. This hook has one job: nothing outside these roots.
- this repository;
- this session's own files: its folder and transcript under ~/.claude/projects/<project> (tool
  results and subagents live there), and its folder under /private/tmp/claude-<uid>/<project> on
  macOS or /tmp/claude-<uid>/<project> on Linux (a cloud session) (scratchpad, background task
  output);
- the project's `memory/` folder;
- the Xcode developer folder (toolchain and SDKs).
Earlier sessions are outside: a reviewer that can read the author's transcript is not independent.

It does not deny names inside an allowed root (such as `data/`): a deny-by-name rule has no end
of spellings (case on APFS, Unicode forms, patterns), and `**/*` reaches the files anyway. Real
data in the repository is kept out of agents by CLAUDE.md rule 5 and .gitignore only, until S4
moves it out (docs/specs/phase-1-see.md, S4).

Paths are resolved with realpath first (symlinks, then `..`). A Glob pattern or a Grep glob is
allowed only when every brace expansion is relative (no leading `/` or `~`) and has no segment
that can match `..`; the search root comes only from `path`.

Exit 2 blocks the call. Any failure (unparseable input, a missing field, an exception) also exits
2, because Claude Code treats every other non-zero exit as a non-blocking error.
"""

import json
import os
import re
import subprocess
import sys

TOOLS = {"Read", "Grep", "Glob"}
SESSION_ID = re.compile(r"[A-Za-z0-9-]{1,128}")
MAX_EXPANSIONS = 256
HINT = "pass the folder in `path` and a relative pattern (no leading / or ~, no ..)"


def deny(reason):
    print(f"read-boundary: {reason}", file=sys.stderr)
    sys.exit(2)


def resolve(path, base):
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(base, path)
    return os.path.realpath(path)


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def allowed_roots(event):
    repo = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))
    session = event.get("session_id")
    if not isinstance(session, str) or not SESSION_ID.fullmatch(session):
        deny("no usable session_id in the hook input")
    project = os.path.join(os.path.expanduser("~/.claude/projects"), slug(repo))
    roots = [
        repo,
        os.path.join(project, "memory"),
        os.path.join(project, session),
        os.path.join(project, session + ".jsonl"),
        os.path.join(f"/private/tmp/claude-{os.getuid()}", slug(repo), session),
        # Linux; on macOS /tmp is a link to /private/tmp, so this is the root above.
        os.path.join(f"/tmp/claude-{os.getuid()}", slug(repo), session),
    ]
    try:
        developer = subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
        if developer:
            roots.append(developer)
    except (OSError, subprocess.SubprocessError):
        pass  # No Xcode (e.g. Linux CI): no toolchain root.
    return [os.path.realpath(root) for root in roots]


def under(path, root):
    return path == root or path.startswith(root.rstrip("/") + "/")


def expand_braces(pattern, budget):
    """Every brace expansion of `pattern`; ValueError when unbalanced or too many."""
    depth = 0
    start = None
    for index, char in enumerate(pattern):
        if char == "{":
            if depth == 0:
                start = index
            depth += 1
        elif char == "}":
            if depth == 0:
                raise ValueError("unbalanced braces")
            depth -= 1
            if depth == 0:
                alternatives, level, piece = [], 0, ""
                for inner in pattern[start + 1:index]:
                    if inner == "," and level == 0:
                        alternatives.append(piece)
                        piece = ""
                        continue
                    level += {"{": 1, "}": -1}.get(inner, 0)
                    piece += inner
                alternatives.append(piece)
                results = []
                for alternative in alternatives:
                    results += expand_braces(
                        pattern[:start] + alternative + pattern[index + 1:], budget)
                    if len(results) > budget:
                        raise ValueError("too many brace expansions")
                return results
    if depth:
        raise ValueError("unbalanced braces")
    return [pattern]


def atoms(segment):
    """A glob segment as atoms: '*', '?', a set test for one character, or a literal."""
    result, index = [], 0
    while index < len(segment):
        char = segment[index]
        if char in "*?":
            result.append(char)
            index += 1
            continue
        if char == "[":
            end = index + 1
            negated = end < len(segment) and segment[end] in "!^"  # both are negation in globs
            end += 1 if negated else 0
            end += 1 if end < len(segment) and segment[end] == "]" else 0
            close = segment.find("]", end)
            if close != -1:
                body = segment[index + 1 + (1 if negated else 0):close]
                result.append((negated, body))
                index = close + 1
                continue
        result.append(char)
        index += 1
    return result


def matches_dot(atom):
    if atom in ("*", "?"):
        return True
    if isinstance(atom, tuple):
        negated, body = atom
        hit = any(body[i] <= "." <= body[i + 2] for i in range(len(body) - 2) if body[i + 1] == "-")
        return ("." in body or hit) != negated
    return atom == "."


def can_match_dot_dot(segment):
    """Whether a glob segment can match the name `..`. A segment of stars only is exempt: glob
    engines never return `.` or `..` for `*` or `**`."""
    if set(segment) <= {"*"}:
        return False
    states = {0}  # how many dots of ".." are matched
    for atom in atoms(segment):
        following = set()
        for state in states:
            if atom == "*":  # zero or more of the remaining dots
                following |= set(range(state, 3))
            elif state < 2 and matches_dot(atom):
                following.add(state + 1)
        states = following
    return 2 in states


def check_pattern(tool, key, pattern):
    if not isinstance(pattern, str):
        deny(f"{tool} with a non-string {key}")
    if "\\" in pattern:
        deny(f"{tool} {key} with an escape; {HINT}")
    try:
        expansions = expand_braces(pattern, MAX_EXPANSIONS)
    except ValueError as error:
        deny(f"{tool} {key}: {error}")
    for expansion in expansions:
        if expansion.startswith(("/", "~")):
            deny(f"{tool} {key} is absolute; {HINT}")
        if any(can_match_dot_dot(segment) for segment in expansion.split("/") if segment):
            deny(f"{tool} {key} can climb with '..'; {HINT}")


def checked_path(tool, tool_input, cwd):
    """The resolved path a call reads from; patterns are checked on the way."""
    if tool == "Read":
        path = tool_input["file_path"]
        if not isinstance(path, str) or not path:
            deny("Read without a file_path")
        return resolve(path, cwd)
    path = tool_input.get("path") or cwd
    if not isinstance(path, str):
        deny(f"{tool} with a non-string path")
    key = "pattern" if tool == "Glob" else "glob"
    if tool_input.get(key) is not None:
        check_pattern(tool, key, tool_input[key])
    return resolve(path, cwd)


def main():
    try:
        event = json.load(sys.stdin)
        tool = event["tool_name"]
        if tool not in TOOLS:
            sys.exit(0)
        tool_input = event["tool_input"]
        cwd = event.get("cwd") or os.getcwd()
        if not isinstance(tool_input, dict) or not isinstance(cwd, str):
            deny("unexpected input shape")
        roots = allowed_roots(event)
        if not any(under(checked_path(tool, tool_input, cwd), root) for root in roots):
            deny(f"{tool} outside the repository, this session's folders, the project memory and "
                 "the Xcode toolchain")
    except SystemExit:
        raise
    except BaseException:  # noqa: BLE001 - fail closed on anything unexpected
        deny("could not check the call")
    sys.exit(0)


if __name__ == "__main__":
    main()
