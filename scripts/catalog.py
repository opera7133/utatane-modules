#!/usr/bin/env python3
"""Validate module sources and create an unsigned, local catalog snapshot."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tempfile
import zipfile

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def relative_path(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value or ":" in value:
        raise ValueError(f"Not a safe relative path: {value}")
    if path.as_posix() != value or value == ".":
        raise ValueError(f"Not a canonical relative path: {value}")
    return path


def within(root, value):
    path = (root / relative_path(value)).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes root: {value}")
    return path


def git(*args, root=ROOT):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def check_source(module, root=ROOT):
    source = module["source"]
    location = within(root, source["path"])
    if source.get("kind") == "local":
        if not (location / "Package.swift").is_file():
            raise ValueError(f"{module['id']}: local native source is missing")
        return
    actual = git("rev-parse", "HEAD", root=location)
    if actual != source["commit"]:
        raise ValueError(f"{module['id']}: source commit differs from catalog")
    if git("status", "--porcelain", "--untracked-files=all", root=location):
        raise ValueError(f"{module['id']}: source tree is dirty")
    entry = git("ls-files", "--stage", "--", source["path"], root=root).split()
    if len(entry) != 4 or entry[0] != "160000" or entry[1] != actual:
        raise ValueError(f"{module['id']}: source must be a pinned submodule in the index")
    expected_url = git("config", "--file", ".gitmodules", "--get",
                       f"submodule.{source['path']}.url", root=root)
    if expected_url != source["url"]:
        raise ValueError(f"{module['id']}: submodule URL differs from catalog")


def modules(root=ROOT, check_sources=True):
    schema = read_json(root / "schemas/module.schema.json")
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    found = []
    ids = set()
    for path in sorted((root / "catalog/modules").glob("*.json")):
        item = read_json(path)
        validator.validate(item)
        if item["id"] in ids:
            raise ValueError(f"Duplicate module ID: {item['id']}")
        ids.add(item["id"])
        if not within(root, item["instructions"]).is_file():
            raise ValueError(f"Missing instructions: {item['instructions']}")
        if item["delivery"] == "binary":
            if not within(root, item["recipe"]).is_file():
                raise ValueError(f"Missing recipe: {item['recipe']}")
            if check_sources:
                check_source(item, root)
        found.append(item)
    if not found:
        raise ValueError("The catalog has no module entries")
    return found


def safe_extract(archive, destination):
    """Only regular files/directories, within a new disposable destination."""
    seen = set()
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            name = item.filename.rstrip("/")
            relative_path(name)
            mode = item.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError(f"Non-regular ZIP entry: {name}")
            if name in seen:
                raise ValueError(f"Duplicate ZIP entry: {name}")
            seen.add(name)
            within(destination, name)
        source.extractall(destination)


def verify_package(archive, module, root=ROOT):
    """Validate the actual ZIP contents, not a detachable sidecar report."""
    with tempfile.TemporaryDirectory(prefix="utatane-package-check-") as temporary:
        extracted = Path(temporary)
        safe_extract(archive, extracted)
        package = extracted / module["id"]
        manifest = read_json(package / "module.json")
        Draft202012Validator(read_json(root / "schemas/package.schema.json")).validate(manifest)
        for key in ("id", "version", "revision", "abi", "minimumOS", "source"):
            if manifest[key] != module[key]:
                raise ValueError(f"Package/catalog mismatch: {key}")
        if not set(manifest["verification"]["nativeABI"]) <= set(manifest["architectures"]):
            raise ValueError("Verification names an architecture absent from the package")
        actual_files = {str(p.relative_to(package)) for p in package.rglob("*") if p.is_file()}
        if actual_files != set(manifest["files"]) | {"module.json"}:
            raise ValueError("Package file inventory differs from manifest")
        if set(p.name for p in extracted.iterdir()) != {module["id"]}:
            raise ValueError("Unexpected package root")
        for name, checksum in manifest["files"].items():
            if sha256(within(package, name)) != checksum:
                raise ValueError(f"Package checksum mismatch: {name}")
        for name in module["requiredFiles"]:
            if name not in manifest["files"]:
                raise ValueError(f"Required package file missing: {name}")
        return manifest


def generate(output, packages, root=ROOT, abi_reports=()):
    entries = modules(root)
    by_id = {item["id"]: item for item in entries}
    artifacts = {}
    for archive in packages:
        with zipfile.ZipFile(archive) as source:
            manifests = [name for name in source.namelist() if name.count("/") == 1 and name.endswith("/module.json")]
            if len(manifests) != 1:
                raise ValueError("Expected one package manifest")
            identity = json.loads(source.read(manifests[0]))["id"]
        if identity not in by_id or by_id[identity]["delivery"] != "binary":
            raise ValueError(f"Package is not a binary catalog entry: {identity}")
        manifest = verify_package(archive, by_id[identity], root)
        key = (identity, tuple(manifest["architectures"]))
        if key in artifacts:
            raise ValueError(f"Duplicate artifact target: {key}")
        artifacts[key] = (archive, manifest)
    checked_architectures = {}
    artifact_hashes = {(identity, sha256(archive)): manifest
                       for (identity, _), (archive, manifest) in artifacts.items()}
    for report_path in abi_reports:
        report = read_json(report_path)
        architecture = report.get("architecture")
        if report.get("schemaVersion") != 1 or architecture not in ("arm64", "x86_64"):
            raise ValueError(f"Invalid ABI report: {report_path}")
        records = report.get("artifacts")
        if not isinstance(records, list) or len(records) != len(artifacts):
            raise ValueError(f"ABI report does not cover every package: {report_path}")
        seen = set()
        for record in records:
            if not isinstance(record, dict) or set(record) != {"id", "sha256"}:
                raise ValueError(f"Invalid ABI report record: {report_path}")
            key = (record["id"], record["sha256"])
            if key in seen or key not in artifact_hashes or architecture not in artifact_hashes[key]["architectures"]:
                raise ValueError(f"ABI report differs from packages: {report_path}")
            seen.add(key)
            checked_architectures.setdefault(key, set()).add(architecture)
    if output.exists():
        raise ValueError(f"Output already exists; choose a new snapshot directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".catalog-") as temporary:
        staging = Path(temporary) / "snapshot"
        staging.mkdir()
        public = []
        filenames = set()
        for entry in entries:
            item = {k: entry[k] for k in ("id", "displayName", "kinds", "origin", "upstream", "delivery", "license", "licenseURL", "instructions", "limitations")}
            if "windowsFilenames" in entry:
                item["windowsFilenames"] = entry["windowsFilenames"]
            if "originalURL" in entry:
                item["originalURL"] = entry["originalURL"]
            instructions = staging / entry["instructions"]
            instructions.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(within(root, entry["instructions"]), instructions)
            item["artifacts"] = []
            for (identity, _), (archive, manifest) in artifacts.items():
                if identity != entry["id"]:
                    continue
                archive_hash = sha256(archive)
                filename = f"{archive.stem}-{archive_hash[:16]}.zip"
                if filename in filenames:
                    raise ValueError(f"Duplicate artifact filename: {filename}")
                filenames.add(filename)
                destination = staging / "artifacts" / filename
                destination.parent.mkdir(exist_ok=True)
                shutil.copyfile(archive, destination)
                verification = {
                    "nativeABI": sorted(set(manifest["verification"]["nativeABI"]) |
                                        checked_architectures.get((identity, archive_hash), set())),
                    "utataneUI": manifest["verification"]["utataneUI"],
                }
                item["artifacts"].append({
                    "path": f"artifacts/{filename}", "sha256": archive_hash,
                    "size": destination.stat().st_size,
                    **{k: manifest[k] for k in ("version", "revision", "architectures", "minimumOS", "abi", "signing")},
                    "verification": verification,
                })
            item["availability"] = "candidate" if item["artifacts"] else ("instructions-only" if entry["delivery"] == "instructions-only" else "not-built")
            public.append(item)
        index = {"schemaVersion": 1, "channel": "development", "signed": False, "modules": public}
        Draft202012Validator(read_json(root / "schemas/index.schema.json")).validate(index)
        write_json(staging / "index.json", index)
        for name in ("index.html", "catalog.css", "catalog.js"):
            shutil.copyfile(within(root, f"site/{name}"), staging / name)
        staging.rename(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    build = sub.add_parser("generate")
    build.add_argument("--output", type=Path, required=True)
    build.add_argument("--package", type=Path, action="extend", nargs="+", default=[])
    build.add_argument("--abi-report", type=Path, action="append", default=[])
    args = parser.parse_args()
    if args.command == "validate":
        print(f"Validated {len(modules())} catalog entries and build sources")
    else:
        generate(args.output.resolve(), [p.resolve() for p in args.package],
                 abi_reports=[p.resolve() for p in args.abi_report])
        print(f"Unsigned development catalog: {args.output / 'index.json'}")


if __name__ == "__main__":
    main()
