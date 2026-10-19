"""Packaging checks use synthetic dictionaries, never copied plugin fixtures."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import port_balloonselector as port


class BalloonSelectorPortTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        files = {"yaya_plugin_main.txt": "ShowBalloonView\n{\n synthetic\n}\n\n//-------------------------------------------------------\n// バージョン\n".encode(), "yaya_plugin_util.dic": b"StructBalloonList.Index = 0\n", "descript.txt": b"name,Synthetic\nhomeurl,https://example.com/\n",
                 "install.txt": b"type,plugin\n", "LICENSE": b"Synthetic test data\n", "yaya.dll": b"not a real DLL",
                 "yaya.txt": b"dic,synthetic.dic\n", "system/yaya_plugin2.dic": b"synthetic\n", "readme.txt": b"Synthetic test data\n"}
        for name, data in files.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        for arguments in (["init", "-q"], ["add", "."], ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "test"]):
            subprocess.run(["git", "-C", str(self.source), *arguments], check=True, capture_output=True)
        commit = subprocess.check_output(["git", "-C", str(self.source), "rev-parse", "HEAD"], text=True).strip()
        sha = hashlib.sha256(files["yaya_plugin_util.dic"]).hexdigest()
        self.commit_patch = patch.object(port, "UPSTREAM_COMMIT", commit)
        self.hash_patch = patch.object(port, "UTIL_SHA256", sha)
        self.commit_patch.start(); self.hash_patch.start()
        self.main_patch = patch.object(port, "MAIN_SHA256", hashlib.sha256(files["yaya_plugin_main.txt"]).hexdigest())
        self.main_patch.start()
        self.addCleanup(self.main_patch.stop)
        self.addCleanup(self.commit_patch.stop); self.addCleanup(self.hash_patch.stop)

    def test_archive_preserves_identity_license_and_all_directory_entries(self):
        (self.source / "private.tmp").write_bytes(b"must not be distributed")
        output = port.build(self.source, self.root / "plugin.nar")
        with zipfile.ZipFile(output) as archive:
            self.assertNotIn("private.tmp", archive.namelist())
            self.assertEqual(archive.read("LICENSE"), b"Synthetic test data\n")
            self.assertEqual(archive.read("descript.txt"), b"name,Synthetic\n")
            self.assertEqual(archive.read("yaya_plugin_util.dic"), b"StructBalloonList.Index = -1\n")
        second = port.build(self.source, self.root / "second.nar")
        self.assertEqual(output.read_bytes(), second.read_bytes())

    def test_dirty_source_does_not_overwrite_an_existing_archive(self):
        (self.source / "yaya_plugin_util.dic").write_text("changed")
        output = self.root / "plugin.nar"
        output.write_bytes(b"keep")
        with self.assertRaisesRegex(ValueError, "modified"):
            port.build(self.source, output)
        self.assertEqual(output.read_bytes(), b"keep")

    def test_source_revision_and_patch_hash_are_checked(self):
        with patch.object(port, "UPSTREAM_COMMIT", "0" * 40):
            with self.assertRaisesRegex(ValueError, "revision"):
                port.build(self.source, self.root / "plugin.nar")
        with patch.object(port, "UTIL_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "audited source"):
                port.build(self.source, self.root / "plugin.nar")

    def test_archive_cannot_modify_the_upstream_checkout(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            port.build(self.source, self.source / "plugin.nar")
