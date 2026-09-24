import copy
import io
import json
from pathlib import Path
import shutil
import stat
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from jsonschema import ValidationError
from build import extract_sources, verified_archive
from catalog import ROOT, main as catalog_main, check_source, generate, modules, read_json, relative_path, safe_extract, sha256, verify_package, write_json


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for directory in ("schemas", "catalog/modules", "docs", "recipes", "site"):
            shutil.copytree(ROOT / directory, self.root / directory)

    def edit(self, identity, update):
        path = self.root / f"catalog/modules/{identity}.json"
        value = read_json(path)
        update(value)
        write_json(path, value)

    def test_cli_accepts_glob_expansion_and_repeated_package_flags(self):
        with patch("sys.argv", ["catalog.py", "generate", "--output", "snapshot",
                                "--package", "first.zip", "second.zip", "--package", "third.zip"]), \
             patch("catalog.generate") as generate_mock, patch("builtins.print"):
            catalog_main()
        generate_mock.assert_called_once_with(Path("snapshot").resolve(),
            [Path(name).resolve() for name in ("first.zip", "second.zip", "third.zip")], abi_reports=[])

    def test_binary_and_instructions_only_coexist(self):
        entries = modules(self.root, check_sources=False)
        self.assertEqual({x["delivery"] for x in entries}, {"binary", "instructions-only"})

    def test_local_sources_are_validated_without_a_submodule(self):
        entry = read_json(self.root / "catalog/modules/misaka-native.json")
        with self.assertRaisesRegex(ValueError, "local native source"):
            check_source(entry, self.root)
        (self.root / "native").mkdir()
        (self.root / "native/Package.swift").write_text("// fixture")
        check_source(entry, self.root)

    def test_local_source_path_cannot_escape(self):
        self.edit("misaka-native", lambda x: x["source"].update(path="../native"))
        with self.assertRaises(ValidationError):
            modules(self.root, check_sources=False)

    def test_local_source_cannot_mix_submodule_fields(self):
        self.edit("misaka-native", lambda x: x["source"].update(commit="0" * 40))
        with self.assertRaises(ValidationError):
            modules(self.root, check_sources=False)

    def test_binary_cannot_omit_pinned_source(self):
        self.edit("kagari", lambda x: x.pop("source"))
        with self.assertRaises(ValidationError):
            modules(self.root, check_sources=False)

    def test_instructions_only_cannot_acquire_build_recipe(self):
        self.edit("aosora", lambda x: x.update(recipe="recipes/kagari/build.sh"))
        with self.assertRaises(ValidationError):
            modules(self.root, check_sources=False)

    def test_unknown_fields_do_not_hide_typo(self):
        self.edit("kagari", lambda x: x.update(minimumOs="10.0"))
        with self.assertRaises(ValidationError):
            modules(self.root, check_sources=False)

    def test_duplicate_ids_rejected(self):
        shutil.copyfile(self.root / "catalog/modules/kagari.json", self.root / "catalog/modules/duplicate.json")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            modules(self.root, check_sources=False)

    def test_instructions_cannot_escape_repository(self):
        self.edit("aosora", lambda x: x.update(instructions="../outside.md"))
        with self.assertRaises(ValueError):
            modules(self.root, check_sources=False)

    def test_unbuilt_module_is_not_offered_as_download(self):
        with patch("catalog.check_source"):
            generate(self.root / "snapshot", [], root=self.root)
        index = read_json(self.root / "snapshot/index.json")
        self.assertFalse(index["signed"])
        entries = {entry["id"]: entry for entry in index["modules"]}
        self.assertEqual(entries["kagari"]["availability"], "not-built")
        self.assertEqual(entries["aosora"]["availability"], "instructions-only")
        self.assertEqual(entries["aosora"]["artifacts"], [])
        self.assertTrue((self.root / "snapshot/docs/aosora.md").is_file())
        page = (self.root / "snapshot/index.html").read_text()
        self.assertIn('href="./catalog.css"', page)
        self.assertIn('src="./catalog.js"', page)
        self.assertTrue((self.root / "snapshot/catalog.css").is_file())
        self.assertTrue((self.root / "snapshot/catalog.js").is_file())

    def test_existing_catalog_not_replaced(self):
        destination = self.root / "snapshot"
        destination.mkdir()
        marker = destination / "old"
        marker.write_text("keep")
        with patch("catalog.check_source"), self.assertRaisesRegex(ValueError, "already exists"):
            generate(destination, [], root=self.root)
        self.assertEqual(marker.read_text(), "keep")


class ArchiveTests(unittest.TestCase):
    def test_relative_paths(self):
        for value in ("../bad", "/absolute", "a/../bad", "a\\bad", "C:/bad", "a//bad", "."):
            with self.subTest(value=value), self.assertRaises(ValueError):
                relative_path(value)

    def test_zip_rejects_symlink_traversal_and_duplicates(self):
        for kind in ("link", "traversal", "duplicate"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                archive = root / "bad.zip"
                with zipfile.ZipFile(archive, "w") as out:
                    if kind == "link":
                        item = zipfile.ZipInfo("module/link")
                        item.external_attr = (stat.S_IFLNK | 0o777) << 16
                        out.writestr(item, "../../escape")
                    elif kind == "traversal":
                        out.writestr("../escape", "bad")
                    else:
                        out.writestr("module/a", "a")
                        with self.assertWarns(UserWarning):
                            out.writestr("module/a", "b")
                with self.assertRaises(ValueError):
                    safe_extract(archive, root / "out")
                self.assertFalse((root / "escape").exists())

    def test_source_tar_rejects_link_and_escape(self):
        for kind in ("link", "traversal"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                archive = root / "bad.tar"
                with tarfile.open(archive, "w") as out:
                    item = tarfile.TarInfo("source/link" if kind == "link" else "../escape")
                    if kind == "link":
                        item.type = tarfile.SYMTYPE
                        item.linkname = "../../escape"
                    out.addfile(item, io.BytesIO())
                with self.assertRaises(ValueError):
                    extract_sources(archive, root / "out")

    def test_cached_download_is_reverified(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / "dependency.tar.gz"
            archive.write_bytes(b"original")
            dependency = {"archive": archive.name, "sha256": sha256(archive)}
            self.assertEqual(verified_archive(dependency, root), archive)
            archive.write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "Corrupt"):
                verified_archive(dependency, root)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.entry = read_json(ROOT / "catalog/modules/kagari.json")
        self.payload = {name: b"synthetic package fixture" for name in self.entry["requiredFiles"]}
        self.manifest = {
            "schemaVersion": 1,
            **{k: copy.deepcopy(self.entry[k]) for k in ("id", "version", "revision", "abi", "minimumOS", "source")},
            "architectures": ["arm64"], "signing": "ad-hoc",
            "verification": {"nativeABI": ["arm64"], "utataneUI": []},
            "build": {"repositoryCommit": None, "dirty": True, "clang": "test", "sdk": "test", "macOS": "test", "inputHashes": {}},
            "files": {},
        }
        import hashlib
        self.manifest["files"] = {name: hashlib.sha256(data).hexdigest() for name, data in self.payload.items()}

    def package(self):
        archive = self.root / "package.zip"
        with zipfile.ZipFile(archive, "w") as out:
            out.writestr("kagari/module.json", json.dumps(self.manifest))
            for name, data in self.payload.items():
                out.writestr("kagari/" + name, data)
        return archive

    def test_manifest_inventory_matches_bytes(self):
        self.assertEqual(verify_package(self.package(), self.entry)["id"], "kagari")

    def test_tampered_library_rejected(self):
        self.payload["lib/libkagari.dylib"] = b"changed"
        with self.assertRaisesRegex(ValueError, "checksum"):
            verify_package(self.package(), self.entry)

    def test_different_source_revision_rejected(self):
        self.manifest["source"]["commit"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "source"):
            verify_package(self.package(), self.entry)

    def test_extra_file_rejected(self):
        self.payload["unlisted.txt"] = b"extra"
        with self.assertRaisesRegex(ValueError, "inventory"):
            verify_package(self.package(), self.entry)

    def test_missing_license_rejected_even_with_updated_inventory(self):
        name = "LICENSES/kagari-MIT.txt"
        del self.payload[name]
        del self.manifest["files"][name]
        with self.assertRaisesRegex(ValueError, "Required"):
            verify_package(self.package(), self.entry)

    def test_verification_cannot_name_missing_cpu(self):
        self.manifest["verification"]["nativeABI"] = ["x86_64"]
        with self.assertRaisesRegex(ValueError, "architecture"):
            verify_package(self.package(), self.entry)

    def test_catalog_copies_actual_package_and_hash(self):
        archive = self.package()
        with patch("catalog.check_source"):
            generate(self.root / "snapshot", [archive])
        index = read_json(self.root / "snapshot/index.json")
        item = next(x for x in index["modules"] if x["id"] == "kagari")
        artifact = item["artifacts"][0]
        self.assertEqual(artifact["sha256"], sha256(archive))
        self.assertEqual(artifact["path"], f"artifacts/package-{sha256(archive)[:16]}.zip")
        self.assertEqual(artifact["size"], archive.stat().st_size)
        self.assertEqual((self.root / "snapshot" / artifact["path"]).read_bytes(), archive.read_bytes())

    def test_duplicate_artifacts_rejected_before_writing(self):
        archive = self.package()
        destination = self.root / "snapshot"
        with patch("catalog.check_source"), self.assertRaisesRegex(ValueError, "Duplicate artifact"):
            generate(destination, [archive, archive])
        self.assertFalse(destination.exists())

    def test_abi_report_must_match_the_exact_package(self):
        self.manifest["architectures"] = ["arm64", "x86_64"]
        archive = self.package()
        report = self.root / "abi.json"
        write_json(report, {"schemaVersion": 1, "architecture": "x86_64",
                            "artifacts": [{"id": "kagari", "sha256": sha256(archive)}]})
        with patch("catalog.check_source"):
            generate(self.root / "snapshot", [archive], abi_reports=[report])
        index = read_json(self.root / "snapshot/index.json")
        item = next(x for x in index["modules"] if x["id"] == "kagari")
        self.assertEqual(item["artifacts"][0]["verification"]["nativeABI"], ["arm64", "x86_64"])
        report_data = read_json(report)
        report_data["artifacts"][0]["sha256"] = "0" * 64
        write_json(report, report_data)
        with patch("catalog.check_source"), self.assertRaisesRegex(ValueError, "ABI report differs"):
            generate(self.root / "rejected", [archive], abi_reports=[report])
        self.assertFalse((self.root / "rejected").exists())


if __name__ == "__main__":
    unittest.main()
