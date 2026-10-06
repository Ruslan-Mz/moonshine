"""Tests for read-boundary.py: python3 -m unittest discover -s .claude/hooks -p 'test_*.py'"""

import json
import os
import re
import subprocess
import tempfile
import unittest

HOOK = os.path.join(os.path.dirname(os.path.realpath(__file__)), "read-boundary.py")
REPO = os.path.realpath(os.path.join(os.path.dirname(HOOK), "..", ".."))
SLUG = re.sub(r"[^A-Za-z0-9]", "-", REPO)
PROJECT = os.path.join(os.path.expanduser("~/.claude/projects"), SLUG)
SESSION = "11111111-2222-3333-4444-555555555555"
OTHER = "99999999-8888-7777-6666-555555555555"
TMP_SESSION = f"/private/tmp/claude-{os.getuid()}/{SLUG}/{SESSION}"


class ReadBoundaryTests(unittest.TestCase):
    def run_hook(self, payload):
        data = payload if isinstance(payload, str) else json.dumps(payload)
        return subprocess.run(
            ["/usr/bin/env", "python3", HOOK], input=data, capture_output=True, text=True,
            cwd=REPO, timeout=30)

    def call(self, tool, **tool_input):
        return self.run_hook({
            "session_id": SESSION, "cwd": REPO,
            "transcript_path": os.path.join(PROJECT, SESSION + ".jsonl"),
            "scratchpad_dir": os.path.join(TMP_SESSION, "scratchpad"),
            "tool_name": tool, "tool_input": tool_input,
        })

    def assertAllowed(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def assertDenied(self, result, reason="read-boundary:"):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(reason, result.stderr)

    # Allowed

    def test_files_in_the_repository_existing_or_not(self):
        self.assertAllowed(self.call("Read", file_path=os.path.join(REPO, "CLAUDE.md")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(REPO, "no/such/file.md")))
        self.assertAllowed(self.call("Read", file_path="docs/ROADMAP.md"))

    def test_this_sessions_folders_and_the_project_memory(self):
        self.assertAllowed(self.call("Read", file_path=os.path.join(TMP_SESSION, "scratchpad", "a.txt")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(TMP_SESSION, "tasks", "b.output")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(PROJECT, "memory", "MEMORY.md")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(PROJECT, SESSION, "tool-results", "x.txt")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(PROJECT, SESSION, "subagents", "a.jsonl")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(PROJECT, SESSION + ".jsonl")))

    def test_grep_and_glob_with_a_folder_in_path_and_a_relative_pattern(self):
        self.assertAllowed(self.call("Grep", pattern="TODO"))
        self.assertAllowed(self.call("Grep", pattern="TODO", path="docs", glob="*.md"))
        self.assertAllowed(self.call("Grep", pattern="TODO", glob="*.{swift,md}"))
        self.assertAllowed(self.call("Glob", pattern="**/*.swift"))
        self.assertAllowed(self.call("Glob", pattern="docs/**/*.md", path=REPO))
        self.assertAllowed(self.call("Glob", pattern="{docs,design}/**/*.md"))
        self.assertAllowed(self.call("Glob", pattern="*.md", path=os.path.join(TMP_SESSION, "scratchpad")))

    def test_other_tools_are_not_checked(self):
        self.assertAllowed(self.call("Bash", command="ls ~"))

    # Denied: outside the boundary

    def test_home_folder_and_system_files(self):
        self.assertDenied(self.call("Read", file_path=os.path.expanduser("~/.CFUserTextEncoding")))
        self.assertDenied(self.call("Read", file_path="~/.zshrc"))
        self.assertDenied(self.call("Read", file_path="/etc/hosts"))

    def test_other_sessions_and_other_projects(self):
        self.assertDenied(self.call("Read", file_path=os.path.join(PROJECT, OTHER + ".jsonl")))
        self.assertDenied(self.call("Read", file_path=os.path.join(PROJECT, OTHER, "tool-results", "x.txt")))
        self.assertDenied(self.call("Grep", pattern="x", path=PROJECT))
        self.assertDenied(self.call("Read", file_path=os.path.join(PROJECT + "-other", "memory", "x.md")))
        tmp_other = f"/private/tmp/claude-{os.getuid()}/{SLUG}/{OTHER}/scratchpad/a.txt"
        self.assertDenied(self.call("Read", file_path=tmp_other))
        self.assertDenied(self.call("Read", file_path=f"/private/tmp/claude-{os.getuid()}/other/a.txt"))
        self.assertDenied(self.call("Read", file_path=os.path.join(os.environ.get("TMPDIR", "/tmp"), "a.txt")))

    def test_dot_dot_out_of_the_repository(self):
        self.assertDenied(self.call("Read", file_path=os.path.join(REPO, "..", "x.md")))
        self.assertDenied(self.call("Read", file_path="../../x.md"))

    def test_a_symlink_inside_an_allowed_folder_pointing_out(self):
        # A temporary folder inside the repository (an allowed root), so it runs in CI too.
        scratch = tempfile.mkdtemp(dir=REPO, prefix=".read-boundary-test-")
        try:
            os.symlink("/etc", os.path.join(scratch, "link"))
            self.assertDenied(self.call("Read", file_path=os.path.join(scratch, "link", "hosts")))
            self.assertDenied(self.call("Grep", pattern="x", path=os.path.join(scratch, "link")))
        finally:
            os.unlink(os.path.join(scratch, "link"))
            os.rmdir(scratch)

    def test_grep_path_outside(self):
        self.assertDenied(self.call("Grep", pattern="x", path="~"))
        self.assertDenied(self.call("Glob", pattern="*.md", path="/"))

    # Denied: every bypass from the PR #11 review, and their neighbours

    def test_absolute_or_home_patterns_in_any_spelling(self):
        for pattern in ["/**/*.md", "/U*/x/**/*.md", "/[V]olumes/**", "/{Users,Volumes}/**", "/etc",
                        "/etc/*", "/Volumes/**/*.md", "{/etc,/Users}/**", "{docs,/etc}/*", "~/**/*.md",
                        "~", "{~,docs}/*"]:
            with self.subTest(pattern=pattern):
                self.assertDenied(self.call("Glob", pattern=pattern))
                self.assertDenied(self.call("Grep", pattern="x", glob=pattern))

    def test_dot_dot_in_any_spelling(self):
        for pattern in ["../../**/*.md", "docs/**/../../../x", "{..,x}/{..,y}/*", "{docs,..}/*",
                        "[.][.]/*", ".[.]/*", "[.]./*", "??/*", "docs/[.][.]/x", "[^x][^x]/*",
                        "[!x][!x]/*", "[,-0][,-0]/*", "*./*", "[].][.]/*"]:
            with self.subTest(pattern=pattern):
                self.assertDenied(self.call("Glob", pattern=pattern))
                self.assertDenied(self.call("Grep", pattern="x", glob=pattern))

    def test_the_denial_says_how_to_search_instead(self):
        result = self.call("Glob", pattern="/etc/*")
        self.assertIn("pass the folder in `path` and a relative pattern", result.stderr)

    # Not denied by name: the hook has one job, nothing outside the allowed roots (owner,
    # PR #11 round 2). Real data is kept out by CLAUDE.md rule 5 and .gitignore until S4.

    def test_names_inside_the_repository_are_not_denied(self):
        self.assertAllowed(self.call("Read", file_path=os.path.join(REPO, "data", "x.txt")))
        self.assertAllowed(self.call("Glob", pattern="data/*"))
        self.assertAllowed(self.call("Glob", pattern="*.md"))
        self.assertAllowed(self.call("Glob", pattern="[a-z]*/**/*.{swift,md}"))

    # Denied: input it cannot parse or check

    def test_input_it_cannot_parse_or_check(self):
        self.assertDenied(self.run_hook("not json"))
        self.assertDenied(self.run_hook(""))
        self.assertDenied(self.run_hook({"tool_name": "Read"}))
        self.assertDenied(self.run_hook({"tool_name": "Read", "tool_input": {}}))
        self.assertDenied(self.call("Read", file_path=""), "Read without a file_path")
        self.assertDenied(self.call("Read"), "could not check the call")
        self.assertDenied(self.run_hook({"tool_name": "Read", "session_id": SESSION, "cwd": REPO,
                                         "tool_input": {"file_path": 3}}))
        self.assertDenied(self.run_hook({"tool_name": "Read", "cwd": REPO,
                                         "tool_input": {"file_path": "CLAUDE.md"}}))
        self.assertDenied(self.run_hook({"tool_name": "Read", "session_id": "../x", "cwd": REPO,
                                         "tool_input": {"file_path": "CLAUDE.md"}}))
        self.assertDenied(self.run_hook({"tool_name": "Grep", "session_id": SESSION, "tool_input": "x"}))
        self.assertDenied(self.call("Glob", pattern=["*"]))
        self.assertDenied(self.call("Glob", pattern="{a,b"))
        self.assertDenied(self.call("Glob", pattern="a\\/b"))
        self.assertDenied(self.call("Glob", pattern="{" * 12 + "a,b" + "}" * 12 + "{a,b}" * 12))


if __name__ == "__main__":
    unittest.main()
