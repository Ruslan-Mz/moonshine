#!/usr/bin/python3
"""PreToolUse hook for Read, Grep and Glob: deny any read outside the read boundary.

The sandbox's `denyRead` limits Bash only; Claude's built-in file tools follow permission rules
and hooks instead. Allowed roots:
- this repository, except `data/` and any `deny-list.txt` (real data, never read by agents);
- this session's own files: its folder and transcript under ~/.claude/projects/<project> (tool
  results and subagents live there), and its folder under /private/tmp/claude-<uid>/<project>
  (scratchpad, background task output);
- the project's `memory/` folder;
- the Xcode developer folder (toolchain and SDKs).
Earlier sessions are outside: a reviewer that can read the author's transcript is not independent.

Paths are resolved with realpath first (symlinks, then `..`). A Glob pattern or a Grep glob is
allowed only when every brace expansion is relative (no leading `/` or `~`), has no segment that
can match `..`, and names no denied folder; the search root comes only from `path`.

Exit 2 blocks the call. Any failure (unparseable input, a missing field, an exception) also exits
2, because Claude Code treats every other non-zero exit as a non-blocking error.
"""

import fnmatch
import json
import os
import re
import subprocess
import sys

TOOLS = {"Read", "Grep", "Glob"}
SESSION_ID = re.compile(r"[A-Za-z0-9-]{1,128}")
DENIED_NAMES = ("data", "deny-list.txt")
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


def boundary(event):
    """The allowed roots and the denied paths for this call."""
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
    ]
    try:
        developer = subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
        if developer:
            roots.append(developer)
    except (OSError, subprocess.SubprocessError):
        pass  # No Xcode (e.g. Linux CI): no toolchain root.
    denied = [os.path.join(repo, "data")]
    return [os.path.realpath(root) for root in roots], [os.path.realpath(d) for d in denied]


def under(path, root):
    return path == root or path.startswith(root.rstrip("/") + "/")


def check_path(path, roots, denied, tool):
    if not any(under(path, root) for root in roots):
        deny(f"{tool} outside the repository, this session's folders, the project memory and "
             "the Xcode toolchain")
    if any(under(path, d) for d in denied) or os.path.basename(path) == "deny-list.txt":
        deny(f"{tool} of real data (data/, deny-list.txt)")


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


def can_match(segment, name):
    return re.fullmatch(fnmatch.translate(segment), name) is not None


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
        segments = expansion.split("/")
        for position, segment in enumerate(segments):
            if segment in ("", ".", "*", "**"):
                continue
            if can_match(segment, ".."):
                deny(f"{tool} {key} can climb with '..'; {HINT}")
            last = position == len(segments) - 1
            if (not last and can_match(segment, "data")) or can_match(segment, "deny-list.txt"):
                if "*" not in segment or segment == "deny-list.txt":
                    deny(f"{tool} {key} names real data (data/, deny-list.txt)")


def checked_paths(tool, tool_input, cwd):
    """The resolved paths a call reads from; patterns are checked on the way."""
    if tool == "Read":
        path = tool_input["file_path"]
        if not isinstance(path, str) or not path:
            deny("Read without a file_path")
        return [resolve(path, cwd)]
    path = tool_input.get("path") or cwd
    if not isinstance(path, str):
        deny(f"{tool} with a non-string path")
    key = "pattern" if tool == "Glob" else "glob"
    if tool_input.get(key) is not None:
        check_pattern(tool, key, tool_input[key])
    return [resolve(path, cwd)]


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
        roots, denied = boundary(event)
        for path in checked_paths(tool, tool_input, cwd):
            check_path(path, roots, denied, tool)
    except SystemExit:
        raise
    except BaseException:  # noqa: BLE001 - fail closed on anything unexpected
        deny("could not check the call")
    sys.exit(0)


if __name__ == "__main__":
    main()
