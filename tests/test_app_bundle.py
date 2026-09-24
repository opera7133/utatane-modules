from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import bundle_kagari


class AppBundleTests(unittest.TestCase):
    def test_build_cache_tracks_architecture_and_toolchain(self):
        with patch.object(bundle_kagari.subprocess, "check_output", return_value=b"toolchain-one"):
            original = bundle_kagari.build_key(["arm64"])
            self.assertNotEqual(original, bundle_kagari.build_key(["arm64", "x86_64"]))
        with patch.object(bundle_kagari.subprocess, "check_output", return_value=b"toolchain-two"):
            self.assertNotEqual(original, bundle_kagari.build_key(["arm64"]))
