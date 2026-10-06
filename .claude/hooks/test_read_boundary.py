"""Tests for read-boundary.py: python3 -m unittest discover -s .claude/hooks -p 'test_*.py'"""

import json
import os
import re
import subprocess
import tempfile
import unittest

HOOK = os.path.join(os.path.dirname(os.path.realpath(__file__)), "read-boundary.py")
REPO = os.path.realpath(os.path.join(os.path.dirname(HOOK), "..", ".."))
PROJECT = os.path.join(
    os.path.expanduser("~/.claude/projects"), re.sub(r"[^A-Za-z0-9]", "-", REPO))


class ReadBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.env = dict(os.environ, TMPDIR=self.tmp)

    def run_hook(self, payload):
        data = payload if isinstance(payload, str) else json.dumps(payload)
        return subprocess.run(
            ["/usr/bin/env", "python3", HOOK], input=data, capture_output=True, text=True,
            env=self.env, cwd=REPO, timeout=30)

    def call(self, tool, **tool_input):
        return self.run_hook({"tool_name": tool, "tool_input": tool_input, "cwd": REPO})

    def assertAllowed(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def assertDenied(self, result):
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("read-boundary:", result.stderr)

    # Allowed

    def test_files_in_the_repository_existing_or_not(self):
        self.assertAllowed(self.call("Read", file_path=os.path.join(REPO, "CLAUDE.md")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(REPO, "no/such/file.md")))
        self.assertAllowed(self.call("Read", file_path="docs/ROADMAP.md"))

    def test_temporary_folder_and_this_projects_claude_folder(self):
        self.assertAllowed(self.call("Read", file_path=os.path.join(self.tmp, "a.txt")))
        self.assertAllowed(self.call("Read", file_path=os.path.join(PROJECT, "memory", "MEMORY.md")))

    def test_grep_and_glob_inside_the_repository(self):
        self.assertAllowed(self.call("Grep", pattern="TODO"))
        self.assertAllowed(self.call("Grep", pattern="TODO", path="docs", glob="*.md"))
        self.assertAllowed(self.call("Glob", pattern="**/*.swift"))
        self.assertAllowed(self.call("Glob", pattern=os.path.join(REPO, "docs/**/*.md")))

    def test_other_tools_are_not_checked(self):
        self.assertAllowed(self.call("Bash", command="ls ~"))

    # Denied

    def test_home_folder_and_system_files(self):
        self.assertDenied(self.call("Read", file_path=os.path.expanduser("~/.CFUserTextEncoding")))
        self.assertDenied(self.call("Read", file_path="~/.zshrc"))
        self.assertDenied(self.call("Read", file_path="/etc/hosts"))
        self.assertDenied(self.call("Read", file_path=os.path.join(PROJECT + "-other", "x.md")))

    def test_dot_dot_out_of_the_repository(self):
        self.assertDenied(self.call("Read", file_path=os.path.join(REPO, "..", "x.md")))
        self.assertDenied(self.call("Read", file_path="../../x.md"))

    def test_a_symlink_inside_an_allowed_folder_pointing_out(self):
        os.symlink("/etc", os.path.join(self.tmp, "link"))
        self.assertDenied(self.call("Read", file_path=os.path.join(self.tmp, "link", "hosts")))
        self.assertDenied(self.call("Grep", pattern="x", path=os.path.join(self.tmp, "link")))

    def test_grep_and_glob_outside(self):
        self.assertDenied(self.call("Grep", pattern="x", path="~"))
        self.assertDenied(self.call("Grep", pattern="x", glob="/etc/*"))
        self.assertDenied(self.call("Glob", pattern="/Volumes/**/*.md"))
        self.assertDenied(self.call("Glob", pattern="~/**/*.md"))
        self.assertDenied(self.call("Glob", pattern="../../**/*.md"))
        self.assertDenied(self.call("Glob", pattern="docs/**/../../../x"))
        self.assertDenied(self.call("Glob", pattern="*.md", path="/"))

    def test_input_it_cannot_parse_or_check(self):
        self.assertDenied(self.run_hook("not json"))
        self.assertDenied(self.run_hook(""))
        self.assertDenied(self.run_hook({"tool_name": "Read"}))
        self.assertDenied(self.run_hook({"tool_name": "Read", "tool_input": {}}))
        self.assertDenied(self.run_hook({"tool_name": "Read", "tool_input": {"file_path": 3}}))
        self.assertDenied(self.run_hook({"tool_name": "Grep", "tool_input": "x"}))
        self.assertDenied(self.call("Glob", pattern=["*"]))


if __name__ == "__main__":
    unittest.main()
