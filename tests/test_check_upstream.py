"""Update detection without network access or repository mutation."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_upstream import github_repo, inspect, main, newest_releases, targets, version_key


def release(tag, preview=False, draft=False):
    return {"tag_name": tag, "prerelease": preview, "draft": draft,
            "html_url": "https://github.com/example/project/releases/tag/" + tag,
            "published_at": "2026-10-08T00:00:00Z"}


MODULE = {"id": "yaya", "displayName": "YAYA", "kinds": ["shiori"], "origin": "upstream-port",
          "delivery": "binary", "version": "Tc574-9", "revision": 2,
          "source": {"commit": "fork"}, "upstream": {"url": "https://github.com/example/project"}}


class FakeAPI:
    def __init__(self, ahead=0, releases=None, error=False):
        self.ahead, self.releases, self.error = ahead, releases or [], error

    def get(self, endpoint, paginate=False):
        if self.error:
            raise RuntimeError("API unavailable")
        if "/releases?" in endpoint:
            return self.releases
        if "/commits/" in endpoint:
            return {"sha": "head"}
        if "/compare/" in endpoint:
            return {"ahead_by": self.ahead, "behind_by": 8, "status": "diverged",
                    "html_url": "https://github.com/example/project/compare/fork...head", "commits": []}
        return {"default_branch": "main"}


class UpstreamTests(unittest.TestCase):
    def test_numeric_versions_not_publication_order(self):
        stable, preview, ignored = newest_releases(
            [release("Tc603-9"), release("Tc603-10"), release("Tc574-99"),
             release("Tc603-11", preview=True), release("Tc603-12", draft=True)], r"Tc6\d{2}-\d+")
        self.assertEqual(stable["tag_name"], "Tc603-10")
        self.assertEqual(preview["tag_name"], "Tc603-11")
        self.assertEqual(ignored, [])

    def test_semver_and_upstream_numeric_equivalence(self):
        self.assertEqual(version_key("Mc203-4"), version_key("2.3.4"))
        self.assertGreater(version_key("v0.1.5"), version_key("0.1.4"))
        self.assertGreater(version_key("v1.0.0"), version_key("v1.0.0-rc.10"))
        self.assertGreater(version_key("v1.0.0-rc.10"), version_key("v1.0.0-rc.2"))

    def test_fork_only_commits_do_not_appear_as_upstream_updates(self):
        row = inspect(MODULE, {"branch": "500", "tags": r"Tc5\d{2}-\d+"},
                      FakeAPI(releases=[release("Tc574-9"), release("Tc606-2")]))
        self.assertIsNone(row["error"])
        self.assertFalse(row["update"])
        self.assertEqual(row["branch_commits"], 0)

    def test_unreleased_branch_updates_and_preview_are_visible(self):
        row = inspect(MODULE, {"branch": "500"}, FakeAPI(ahead=2, releases=[release("Tc574-10", preview=True)]))
        self.assertFalse(row["stable_update"])
        self.assertTrue(row["preview_update"])
        self.assertTrue(row["update"])
        self.assertEqual(row["branch_commits"], 2)

    def test_stale_subtree_baseline_is_an_error(self):
        row = inspect(MODULE, {"baseline": "old", "baseline_for_source": "different"}, FakeAPI())
        self.assertIsNotNone(row["error"])
        self.assertFalse(row["update"])

    def test_api_failure_is_not_reported_as_up_to_date(self):
        row = inspect(MODULE, {}, FakeAPI(error=True))
        self.assertIn("API unavailable", row["error"])

    def test_native_saori_and_instruction_only_entries_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "catalog/modules"
            directory.mkdir(parents=True)
            entries = [MODULE, {**MODULE, "id": "local", "source": {"kind": "local"}},
                       {**MODULE, "id": "independent", "origin": "independent"},
                       {**MODULE, "id": "saori", "kinds": ["saori"]},
                       {**MODULE, "id": "manual", "delivery": "instructions-only"}]
            for entry in entries:
                (directory / (entry["id"] + ".json")).write_text(json.dumps(entry))
            self.assertEqual([m["id"] for m in targets(root)], ["yaya"])

    def test_public_repository_urls_only(self):
        self.assertEqual(github_repo("https://github.com/owner/name.git"), "owner/name")
        for url in ("https://evil.example/owner/name", "https://github.com/owner/name/tree/main"):
            with self.assertRaises(ValueError):
                github_repo(url)

    def test_cli_exit_codes_and_continues_after_a_failure(self):
        ok = {"id": "yaya", "error": None, "update": True}
        failed = {"id": "other", "error": "unavailable", "update": False}
        with patch("check_upstream.targets", return_value=[MODULE, {**MODULE, "id": "other"}]), \
                patch("check_upstream.inspect", side_effect=[ok, failed]) as inspected, \
                patch("check_upstream.show"):
            self.assertEqual(main(["--fail-on-update"]), 2)
            self.assertEqual(inspected.call_count, 2)
        with patch("check_upstream.targets", return_value=[MODULE]), \
                patch("check_upstream.inspect", return_value=ok), patch("check_upstream.show"):
            self.assertEqual(main([]), 0)
            self.assertEqual(main(["--fail-on-update"]), 1)
