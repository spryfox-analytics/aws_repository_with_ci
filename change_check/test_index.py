"""Unit tests of the change check, without AWS: python3 -m unittest discover change_check"""

import io
import sys
import types
import unittest
import zipfile
from unittest import mock

# The Lambda runtime brings boto3; the tests replace it, so they need no AWS SDK.
sys.modules.setdefault("boto3", types.SimpleNamespace(client=lambda _name: mock.MagicMock()))

import index  # noqa: E402  pylint: disable=wrong-import-position


def archive(contents):
    """ZIP archive holding the given files, plus a directory entry as the source ZIPs have them."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zip_file:
        zip_file.writestr("backend/", "")
        for name, content in contents.items():
            zip_file.writestr(name, content)
    return buffer.getvalue()


BEFORE = {
    "backend/app.py": "app",
    "core/model.py": "model",
    "security/auth.py": "auth",
    "frontend/index.ts": "ui",
    "README.md": "readme",
}


class RelevantDirectories(unittest.TestCase):
    def test_directory_alone(self):
        self.assertEqual(index.relevant_directories({"directory": "backend"}), ["backend"])

    def test_union_in_order_without_duplicates(self):
        parameters = {"directory": "backend", "additional_directories": ["core", "backend", "security/", "core"]}
        self.assertEqual(index.relevant_directories(parameters), ["backend", "core", "security"])

    def test_whole_repository_without_directory(self):
        self.assertEqual(index.relevant_directories({"directory": None, "additional_directories": ["core"]}), [])

    def test_parameters_of_v3_7(self):
        self.assertEqual(index.relevant_directories({"pipeline": "p", "directory": "backend", "execution": "x"}), ["backend"])


class Listing(unittest.TestCase):
    def test_keeps_files_below_any_prefix(self):
        names = index.listing(archive(BEFORE), ["backend/", "core/"]).keys()
        self.assertEqual(sorted(names), ["backend/app.py", "core/model.py"])

    def test_empty_prefix_is_the_whole_repository(self):
        self.assertEqual(sorted(index.listing(archive(BEFORE), [""]).keys()), sorted(BEFORE))

    def test_prefix_does_not_match_a_sibling_with_the_same_start(self):
        names = index.listing(archive({"core/a.py": "a", "core-legacy/b.py": "b"}), ["core/"]).keys()
        self.assertEqual(list(names), ["core/a.py"])


class ChangedFiles(unittest.TestCase):
    def test_added_removed_and_modified(self):
        before = {"a": 1, "b": 2, "c": 3}
        current = {"a": 1, "b": 20, "d": 4}
        self.assertEqual(index.changed_files(current, before), ["b", "c", "d"])

    def test_nothing_changed(self):
        self.assertEqual(index.changed_files({"a": 1}, {"a": 1}), [])


class ShouldRun(unittest.TestCase):
    """should_run against a previous source of BEFORE and a current source of BEFORE plus changes."""

    def decide(self, changes, **parameters):
        current = {**BEFORE, **changes}
        bodies = {"current": archive(current), "previous": archive(BEFORE)}
        parameters = {"pipeline": "my-pipeline", "execution": "#{codepipeline.PipelineExecutionId}", **parameters}
        with mock.patch.object(index, "last_successful_source", return_value=("e-1", "bucket", "previous")), \
             mock.patch.object(index, "files", side_effect=lambda _b, key, prefixes: index.listing(bodies[key], prefixes)):
            return index.should_run(parameters, "bucket", "current")

    def test_skips_when_only_other_directories_changed(self):
        run, reason = self.decide({"frontend/index.ts": "new"}, directory="backend", additional_directories=["core", "security"])
        self.assertFalse(run, reason)
        self.assertIn("backend/, core/, security/", reason)

    def test_runs_when_an_additional_directory_changed(self):
        run, reason = self.decide({"security/auth.py": "new"}, directory="backend", additional_directories=["core", "security"])
        self.assertTrue(run, reason)
        self.assertIn("security/auth.py", reason)

    def test_runs_when_the_directory_changed(self):
        run, _ = self.decide({"backend/new.py": "new"}, directory="backend", additional_directories=["core"])
        self.assertTrue(run)

    def test_additional_directory_change_ignored_without_listing_it(self):
        run, _ = self.decide({"core/model.py": "new"}, directory="backend")
        self.assertFalse(run)

    def test_whole_repository_without_directory(self):
        run, _ = self.decide({"README.md": "new"})
        self.assertTrue(run)

    def test_names_an_additional_directory_without_files(self):
        run, reason = self.decide({}, directory="backend", additional_directories=["shared"])
        self.assertFalse(run)
        self.assertIn("no files in shared/", reason)

    def test_runs_when_no_directory_holds_files(self):
        run, _ = self.decide({}, directory="missing", additional_directories=["gone"])
        self.assertTrue(run)


if __name__ == "__main__":
    unittest.main()
