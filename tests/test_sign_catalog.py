"""Verify that a release catalog is complete and signs its exact index bytes."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from catalog import generate
from sign_catalog import public_key, sign, verify


@unittest.skipUnless(shutil.which("openssl"), "OpenSSL is required")
class SignedCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "development"
        self.stable = self.root / "staging"
        self.private = self.root / "private.pem"
        self.public = self.root / "public.pem"
        generate(self.source, [])
        subprocess.run(["openssl", "genpkey", "-algorithm", "Ed25519", "-out", str(self.private)],
                       check=True, stdout=subprocess.DEVNULL)
        public_key(self.private, self.public)

    def test_signed_snapshot_verifies_and_detects_index_change(self):
        sign(self.source, self.stable, self.private)
        verify(self.stable, self.public)
        self.assertEqual((self.stable / "index.sig").stat().st_size, 64)
        with (self.stable / "index.json").open("ab") as index:
            index.write(b" ")
        with self.assertRaisesRegex(ValueError, "signature"):
            verify(self.stable, self.public)

    def test_unsigned_snapshot_cannot_smuggle_extra_files(self):
        (self.source / "secret.txt").write_text("private")
        with self.assertRaisesRegex(ValueError, "unexpected"):
            sign(self.source, self.stable, self.private)
        self.assertFalse(self.stable.exists())

    def test_stable_requires_ui_verification(self):
        with self.assertRaisesRegex(ValueError, "Utatane UI verification|missing a binary|ABI verification"):
            sign(self.source, self.stable, self.private, channel="stable")
        self.assertFalse(self.stable.exists())


if __name__ == "__main__":
    unittest.main()
