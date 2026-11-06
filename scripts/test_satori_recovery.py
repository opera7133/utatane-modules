#!/usr/bin/env python3
"""Exercise SATORI save failures through the real Utatane helper, using synthetic dictionaries."""
import argparse
from pathlib import Path
import tempfile
import unittest

from test_cpp_host import Host


class SatoriRecoveryTests(unittest.TestCase):
    helper = None
    library = None

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="SATORI 保存回復 😀 ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.host = None
        self.addCleanup(self.abort)

    def abort(self):
        if self.host is not None:
            self.host.abort()
            self.host = None

    def prepare(self, encrypted=False):
        (self.root / "satori_conf.txt").write_text(
            "＊初期化\n＄セーブデータ暗号化\t" + ("有効" if encrypted else "無効") + "\n", encoding="utf-8")
        (self.root / "dic00.txt").write_text(
            "＊OnSet\n＄確認\t最新状態😀\n：設定。\n"
            "＊OnRead\n：値=（確認）。\n"
            "＊OnReload\n＄辞書リロード\t実行\n：リロード。\n"
            "＊OnSwitch\n＄辞書フォルダ\t追加\n：切替。\n"
            "＊OnSave\n＄手動セーブ\t実行\n：保存。\n", encoding="utf-8")
        extra = self.root / "追加"
        extra.mkdir()
        (extra / "dic00.txt").write_bytes((self.root / "dic00.txt").read_bytes())
        (extra / "dic_extra.txt").write_text("＊OnExtra\n：追加辞書。\n", encoding="utf-8")
        self.extension = "sat" if encrypted else "txt"

    def start(self):
        self.host = Host(self.helper, self.library, self.root, self.root / "shared")

    def send(self, event):
        wire = f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Utatane\r\nSecurityLevel: local\r\nID: {event}\r\n\r\n"
        return self.host.exchange(1, wire.encode()).decode("utf-8")

    def close(self):
        self.host.close()
        self.host = None

    def failure_reload(self, encrypted, block, event):
        self.prepare(encrypted)
        self.start()
        self.assertIn("設定", self.send("OnSet"))
        # Nonempty directories deterministically reject writing/replacing, without timing or permissions.
        target = self.root / ("satori_savedata.tmp" if block == "temporary" else f"satori_savedata.{self.extension}")
        target.mkdir()
        sentinel = target / "keep"
        sentinel.write_bytes(b"original")
        self.send(event)
        self.assertIn("最新状態😀", self.send("OnRead"))
        if event == "OnSwitch":
            self.assertIn("追加辞書", self.send("OnExtra"))
        self.assertEqual(sentinel.read_bytes(), b"original")
        sentinel.unlink()
        target.rmdir()
        self.close()
        saved = self.root / f"satori_savedata.{self.extension}"
        self.assertTrue(saved.is_file())
        self.start()
        self.assertIn("最新状態😀", self.send("OnRead"))
        self.close()

    def test_reload_after_temporary_write_failure(self):
        self.failure_reload(False, "temporary", "OnReload")

    def test_reload_after_replace_failure(self):
        self.failure_reload(False, "replacement", "OnReload")

    def test_encrypted_reload_after_temporary_write_failure(self):
        self.failure_reload(True, "temporary", "OnReload")

    def test_encrypted_reload_after_replace_failure(self):
        self.failure_reload(True, "replacement", "OnReload")

    def test_dictionary_switch_after_replace_failure(self):
        self.failure_reload(False, "replacement", "OnSwitch")

    def test_backup_survives_missing_primary(self):
        self.prepare()
        self.start()
        backup = self.root / "satori_savebackup.txt"
        backup.write_bytes(b"prior backup")
        self.send("OnSet")
        self.send("OnSave")
        self.assertEqual(backup.read_bytes(), b"prior backup")
        self.close()

    def test_unreadable_save_is_preserved_once(self):
        self.preserve_invalid_save(False)

    def test_encrypted_unreadable_save_is_preserved_once(self):
        self.preserve_invalid_save(True)

    def preserve_invalid_save(self, encrypted):
        self.prepare(encrypted)
        saved = self.root / f"satori_savedata.{self.extension}"
        failed = self.root / f"satori_savedata_failed.{self.extension}"
        original = b"not a savedata dictionary\n"
        saved.write_bytes(original)
        (self.root / f"satori_savebackup.{self.extension}").write_bytes(b"invalid backup\n")
        self.start()
        self.assertEqual(failed.read_bytes(), original)
        self.close()
        saved.write_bytes(b"another invalid savedata\n")
        (self.root / f"satori_savebackup.{self.extension}").write_bytes(b"invalid backup\n")
        self.start()
        self.assertEqual(failed.read_bytes(), original)
        self.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    parser.add_argument("--library", required=True, type=Path)
    args = parser.parse_args()
    SatoriRecoveryTests.helper = args.host.resolve()
    SatoriRecoveryTests.library = args.library.resolve()
    unittest.main(argv=[__file__], verbosity=2)
