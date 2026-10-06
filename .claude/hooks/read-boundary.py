#!/usr/bin/python3
"""PreToolUse hook for Read, Grep and Glob: deny any path outside the read boundary.

The sandbox's `denyRead` limits Bash only; Claude's built-in file tools follow permission rules
and hooks instead. Allowed roots: this repository, the temporary folders ($TMPDIR and the Claude
sandbox's /private/tmp/claude-<uid>, which holds the session scratchpad), this project's own
folder under ~/.claude/projects, and the Xcode developer folder (toolchain and SDKs).

Paths are resolved with realpath first (symlinks, then `..`). Exit 2 blocks the call; any other
failure (unparseable input, a missing field, an exception) also exits 2, because Claude Code
treats every other non-zero exit as a non-blocking error.
"""

import json
import os
import re
import subprocess
import sys

TOOLS = {"Read", "Grep", "Glob"}
GLOB_CHARS = re.compile(r"[*?\[{]")


def deny(reason):
    print(f"read-boundary: {reason}", file=sys.stderr)
    sys.exit(2)


def resolve(path, base):
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(base, path)
    return os.path.realpath(path)


def repository():
    return os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", ".."))


def allowed_roots():
    repo = repository()
    roots = [
        repo,
        os.path.join(os.path.expanduser("~/.claude/projects"), re.sub(r"[^A-Za-z0-9]", "-", repo)),
        f"/private/tmp/claude-{os.getuid()}",
    ]
    if os.environ.get("TMPDIR"):
        roots.append(os.environ["TMPDIR"])
    try:
        developer = subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True, timeout=5
        ).stdout.strip()
        if developer:
            roots.append(developer)
    except (OSError, subprocess.SubprocessError):
        pass  # No Xcode (e.g. Linux CI): no toolchain root.
    return [os.path.realpath(root) for root in roots]


def inside(path, roots):
    return any(path == root or path.startswith(root.rstrip("/") + "/") for root in roots)


def pattern_base(pattern):
    """The folder a glob pattern starts from, and whether `..` follows a wildcard."""
    parts = pattern.split("/")
    fixed = []
    for index, part in enumerate(parts):
        if GLOB_CHARS.search(part):
            return "/".join(fixed) or ".", ".." in parts[index:]
        fixed.append(part)
    return "/".join(fixed[:-1]) or ".", False


def candidates(tool, tool_input, cwd):
    """The resolved paths a call would read from."""
    if tool == "Read":
        path = tool_input["file_path"]
        if not isinstance(path, str) or not path:
            deny("Read without a file_path")
        return [resolve(path, cwd)]
    path = tool_input.get("path") or cwd
    if not isinstance(path, str):
        deny(f"{tool} with a non-string path")
    root = resolve(path, cwd)
    paths = [root]
    key = "pattern" if tool == "Glob" else "glob"
    pattern = tool_input.get(key)
    if pattern is not None:
        if not isinstance(pattern, str):
            deny(f"{tool} with a non-string {key}")
        folder, climbs = pattern_base(pattern)
        if climbs:
            deny(f"{tool} {key} climbs with '..' after a wildcard")
        paths.append(resolve(folder, root))
    return paths


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
        roots = allowed_roots()
        for path in candidates(tool, tool_input, cwd):
            if not inside(path, roots):
                deny(f"{tool} outside the repository, temporary folders, this project's "
                     "Claude folder and the Xcode toolchain")
    except SystemExit:
        raise
    except BaseException:  # noqa: BLE001 - fail closed on anything unexpected
        deny("could not check the call")
    sys.exit(0)


if __name__ == "__main__":
    main()
