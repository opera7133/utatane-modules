#!/usr/bin/env python3
"""Promote a checked catalog snapshot with an Ed25519 signature."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from jsonschema import Draft202012Validator

from catalog import ROOT, modules, read_json, sha256, verify_package, within, write_json


def validate_snapshot(snapshot, *, channel, signed, require_signature=True):
    index = read_json(snapshot / "index.json")
    Draft202012Validator(read_json(ROOT / "schemas/index.schema.json")).validate(index)
    if index["channel"] != channel or index["signed"] is not signed:
        raise ValueError("Catalog channel or signature flag does not match")
    by_id = {module["id"]: module for module in modules()}
    expected = {"index.json", "index.html", "catalog.css", "catalog.js"}
    if signed and require_signature:
        expected.add("index.sig")
    for module in index["modules"]:
        if module["id"] not in by_id:
            raise ValueError(f"Unknown module: {module['id']}")
        expected.add(module["instructions"])
        if not within(snapshot, module["instructions"]).is_file():
            raise ValueError(f"Missing module instructions: {module['id']}")
        for artifact in module["artifacts"]:
            expected.add(artifact["path"])
            path = within(snapshot, artifact["path"])
            if not path.is_file() or path.stat().st_size != artifact["size"] or sha256(path) != artifact["sha256"]:
                raise ValueError(f"Artifact differs from index: {artifact['path']}")
            manifest = verify_package(path, by_id[module["id"]])
            for name in ("version", "revision", "architectures", "minimumOS", "abi", "signing"):
                if artifact[name] != manifest[name]:
                    raise ValueError(f"Artifact metadata differs from package: {artifact['path']}")
            if not set(manifest["verification"]["utataneUI"]) <= set(artifact["verification"]["utataneUI"]) or \
               not set(manifest["verification"]["nativeABI"]) <= set(artifact["verification"]["nativeABI"]) or \
               not set(artifact["verification"]["nativeABI"]) <= set(artifact["architectures"]):
                raise ValueError(f"Artifact verification differs from package: {artifact['path']}")
    for name in ("index.html", "catalog.css", "catalog.js"):
        if not (snapshot / name).is_file():
            raise ValueError(f"Missing catalog page: {name}")
    actual = {str(path.relative_to(snapshot)) for path in snapshot.rglob("*") if path.is_file()}
    if actual != expected or any(path.is_symlink() for path in snapshot.rglob("*")):
        raise ValueError("Catalog contains missing, unexpected or linked files")
    return index


def public_key(private_key, output):
    subprocess.run(["openssl", "pkey", "-in", str(private_key), "-pubout", "-out", str(output)],
                   check=True, stdout=subprocess.DEVNULL)


def verify(snapshot, public_key_path, *, channel="staging"):
    index = validate_snapshot(snapshot, channel=channel, signed=True)
    if channel == "stable":
        require_stable_verification(index)
    signature = snapshot / "index.sig"
    if not signature.is_file() or signature.stat().st_size != 64:
        raise ValueError("Missing or invalid Ed25519 signature")
    result = subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin",
                             "-inkey", str(public_key_path), "-sigfile", str(signature),
                             "-in", str(snapshot / "index.json")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise ValueError("Catalog signature does not match")


def require_stable_verification(index):
    for module in index["modules"]:
        if module["delivery"] == "binary" and not module["artifacts"]:
            raise ValueError(f"Stable catalog is missing a binary: {module['id']}")
        for artifact in module["artifacts"]:
            if set(artifact["verification"]["nativeABI"]) != set(artifact["architectures"]):
                raise ValueError(f"Stable catalog lacks ABI verification: {module['id']}")


def apply_ui_evidence(index, evidence):
    if evidence.get("schemaVersion") != 1 or not isinstance(evidence.get("artifacts"), list):
        raise ValueError("Invalid UI verification records")
    records = {}
    for record in evidence["artifacts"]:
        digest = record.get("sha256")
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError("Invalid UI verification checksum")
        if digest in records:
            raise ValueError("Duplicate UI verification checksum")
        records[digest] = record
    used = set()
    for module in index["modules"]:
        for artifact in module["artifacts"]:
            record = records.get(artifact["sha256"])
            if record is None:
                continue
            if (record.get("module") != module["id"] or record.get("version") != artifact["version"] or
                    record.get("revision") != artifact["revision"] or
                    not isinstance(record.get("checks"), list) or not record["checks"] or
                    not all(isinstance(check, str) and check.strip() for check in record["checks"])):
                raise ValueError(f"UI verification does not match artifact: {module['id']}")
            artifact["verification"]["utataneUI"] = record["checks"]
            used.add(artifact["sha256"])
    if set(records) != used:
        raise ValueError("UI verification does not match any artifact")


def promote(source, destination, private_key, evidence_path):
    if destination.exists():
        raise ValueError(f"Output already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".stable-catalog-") as temporary:
        temporary = Path(temporary)
        key = temporary / "public.pem"
        public_key(private_key, key)
        verify(source, key, channel="staging")
        staging = temporary / "snapshot"
        shutil.copytree(source, staging)
        index = read_json(staging / "index.json")
        apply_ui_evidence(index, read_json(evidence_path))
        index["channel"] = "stable"
        require_stable_verification(index)
        write_json(staging / "index.json", index)
        validate_snapshot(staging, channel="stable", signed=True)
        subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(private_key),
                        "-in", str(staging / "index.json"), "-out", str(staging / "index.sig")],
                       check=True, stdout=subprocess.DEVNULL)
        verify(staging, key, channel="stable")
        staging.rename(destination)


def sign(source, destination, private_key, *, channel="staging"):
    validate_snapshot(source, channel="development", signed=False)
    if channel not in ("staging", "stable"):
        raise ValueError(f"Invalid signed channel: {channel}")
    if destination.exists():
        raise ValueError(f"Output already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".signed-catalog-") as temporary:
        staging = Path(temporary) / "snapshot"
        shutil.copytree(source, staging)
        index = read_json(staging / "index.json")
        index["channel"] = channel
        index["signed"] = True
        write_json(staging / "index.json", index)
        validate_snapshot(staging, channel=channel, signed=True, require_signature=False)
        if channel == "stable":
            require_stable_verification(index)
        subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(private_key),
                        "-in", str(staging / "index.json"), "-out", str(staging / "index.sig")],
                       check=True, stdout=subprocess.DEVNULL)
        key = Path(temporary) / "public.pem"
        public_key(private_key, key)
        verify(staging, key, channel=channel)
        staging.rename(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    signing = commands.add_parser("sign")
    signing.add_argument("source", type=Path)
    signing.add_argument("destination", type=Path)
    signing.add_argument("--private-key", type=Path, required=True)
    signing.add_argument("--channel", choices=("staging", "stable"), default="staging")
    promoting = commands.add_parser("promote")
    promoting.add_argument("source", type=Path)
    promoting.add_argument("destination", type=Path)
    promoting.add_argument("--private-key", type=Path, required=True)
    promoting.add_argument("--ui-evidence", type=Path, required=True)
    verifying = commands.add_parser("verify")
    verifying.add_argument("snapshot", type=Path)
    verifying.add_argument("--public-key", type=Path, required=True)
    verifying.add_argument("--channel", choices=("staging", "stable"), default="staging")
    args = parser.parse_args()
    if args.command == "sign":
        sign(args.source.resolve(), args.destination.resolve(), args.private_key.resolve(), channel=args.channel)
        print(f"Signed catalog: {args.destination / 'index.json'}")
    elif args.command == "promote":
        promote(args.source.resolve(), args.destination.resolve(), args.private_key.resolve(), args.ui_evidence.resolve())
        print(f"Promoted catalog: {args.destination / 'index.json'}")
    else:
        verify(args.snapshot.resolve(), args.public_key.resolve(), channel=args.channel)
        print(f"Verified catalog: {args.snapshot / 'index.json'}")


if __name__ == "__main__":
    main()
