"""Verify that a release catalog is complete and signs its exact index bytes."""

from pathlib import Path
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from catalog import generate
from fetch_snapshot import fetch
from sign_catalog import apply_ui_evidence, promote, public_key, sign, verify


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

    def test_stable_requires_binaries_and_abi_verification(self):
        with self.assertRaisesRegex(ValueError, "missing a binary|ABI verification"):
            sign(self.source, self.stable, self.private, channel="stable")
        self.assertFalse(self.stable.exists())

    def test_ui_evidence_is_bound_to_exact_archive_and_revision(self):
        artifact = {"sha256": "a" * 64, "version": "1.2", "revision": 3,
                    "verification": {"nativeABI": ["arm64"], "utataneUI": []}}
        index = {"modules": [{"id": "example", "artifacts": [artifact]}]}
        record = {"sha256": "a" * 64, "module": "example", "version": "1.2",
                  "revision": 3, "checks": ["Utatane 0.2.9: boot and double-click"]}
        apply_ui_evidence(index, {"schemaVersion": 1, "artifacts": [record]})
        self.assertEqual(artifact["verification"]["utataneUI"], record["checks"])
        artifact["verification"]["utataneUI"] = []
        with self.assertRaisesRegex(ValueError, "does not match"):
            apply_ui_evidence(index, {"schemaVersion": 1, "artifacts": [{**record, "revision": 2}]})
        with self.assertRaisesRegex(ValueError, "does not match any artifact"):
            apply_ui_evidence(index, {"schemaVersion": 1, "artifacts": [{**record, "sha256": "b" * 64}]})

    def test_promotion_still_requires_complete_binaries(self):
        sign(self.source, self.stable, self.private)
        evidence = self.root / "ui-verification.json"
        evidence.write_text('{"schemaVersion":1,"artifacts":[]}')
        with self.assertRaisesRegex(ValueError, "missing a binary"):
            promote(self.stable, self.root / "stable", self.private, evidence)

    def test_fetches_only_files_named_by_a_signed_index(self):
        sign(self.source, self.stable, self.private)
        base = "https://example.test/modules/preview/"

        def local_response(request, timeout):
            self.assertEqual(timeout, 60)
            self.assertEqual(request.get_header("User-agent"), "Utatane-Modules-Catalog/1.0")
            name = request.full_url.removeprefix(base)
            response = io.BytesIO((self.stable / name).read_bytes())
            response.status = 200
            response.url = request.full_url
            return response

        destination = self.root / "fetched"
        with patch("fetch_snapshot.urlopen", side_effect=local_response):
            fetch(base, destination, self.public)
        verify(destination, self.public)


if __name__ == "__main__":
    unittest.main()
