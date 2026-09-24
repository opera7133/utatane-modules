#!/usr/bin/env python3
"""Build a verified macOS development package; never publish or install it."""

import argparse
import fcntl
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

from catalog import ROOT, git, modules, read_json, relative_path, sha256, verify_package, within, write_json


def verified_archive(dependency, downloads):
    archive = downloads / relative_path(dependency["archive"])
    if not archive.exists():
        with tempfile.TemporaryDirectory(dir=downloads) as temporary:
            incoming = Path(temporary) / "source.tar.gz"
            subprocess.run([
                "curl", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
                "--retry", "3", "--connect-timeout", "20", "--max-time", "180",
                dependency["url"], "--output", str(incoming),
            ], check=True)
            if sha256(incoming) != dependency["sha256"]:
                raise ValueError(f"Source checksum mismatch: {dependency['archive']}")
            incoming.replace(archive)
    if sha256(archive) != dependency["sha256"]:
        raise ValueError(f"Corrupt dependency cache: {archive}")
    return archive


def extract_sources(archive, destination):
    with tarfile.open(archive) as source:
        for member in source.getmembers():
            relative_path(member.name.rstrip("/"))
            if not (member.isfile() or member.isdir()):
                raise ValueError(f"Non-regular source archive entry: {member.name}")
            within(destination, member.name.rstrip("/"))
        source.extractall(destination, filter="data")


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def verify_macho(package, architectures):
    libraries = ("libkagari.dylib", "liblua5.4.dylib")
    for name in libraries:
        library = package / "lib" / name
        actual = set(output("xcrun", "lipo", "-archs", str(library)).split())
        if actual != set(architectures):
            raise ValueError(f"Unexpected architectures: {name}: {actual}")
        subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True)
        for architecture in architectures:
            dependencies = output("otool", "-arch", architecture, "-L", str(library)).splitlines()[1:]
            for line in dependencies:
                dependency = line.strip().split(" ", 1)[0]
                if dependency.startswith(("/usr/lib/", "/System/Library/")):
                    continue
                if dependency not in {f"@rpath/{item}" for item in libraries}:
                    raise ValueError(f"Non-relocatable dependency: {dependency}")
            commands = output("otool", "-arch", architecture, "-l", str(library))
            if "minos 14.0" not in commands:
                raise ValueError(f"Unexpected minimum macOS: {name}/{architecture}")
            if name == "libkagari.dylib" and "path @loader_path " not in commands:
                raise ValueError("kagari is missing loader-relative runtime lookup")
            if name == "libkagari.dylib":
                symbols = {line.split()[-1] for line in output("nm", "-arch", architecture, "-gU", str(library)).splitlines() if line.split()}
                if not {"_kagari_load", "_kagari_request", "_kagari_unload"} <= symbols:
                    raise ValueError("kagari ABI symbols missing")


def archive_package(package, destination):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                archive.write(path, f"{package.name}/{path.relative_to(package)}")


def build(identity, architectures, cache, destination):
    if sys.platform != "darwin":
        raise ValueError("Native package builds require macOS")
    entry = next((item for item in modules() if item["id"] == identity), None)
    if entry is None or entry["delivery"] != "binary":
        raise ValueError(f"No binary recipe for {identity}")
    if entry["source"].get("kind") == "local":
        from build_native import build_native
        return build_native(entry, architectures, cache, destination)
    if identity in ("minato", "pasta", "yaya", "satori"):
        from build_upstream import build_upstream
        return build_upstream(entry, architectures, cache, destination)
    if identity != "kagari":
        raise ValueError(f"No implemented builder for {identity}")
    host = platform.machine()
    if host not in architectures:
        raise ValueError("Include the host architecture so the packaged ABI can be executed")
    name = f"{identity}-{entry['version']}-r{entry['revision']}-macos-{'_'.join(architectures)}.zip"
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / name
    if final.exists():
        raise ValueError(f"Refusing to overwrite a versioned artifact: {final}")
    cache.mkdir(parents=True, exist_ok=True)
    dependencies_path = ROOT / "recipes/kagari/dependencies.json"
    dependencies = read_json(dependencies_path)
    with (cache / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        downloads = cache / "downloads"
        downloads.mkdir(exist_ok=True)
        archives = {name: verified_archive(dep, downloads) for name, dep in dependencies.items()}
        with tempfile.TemporaryDirectory(dir=cache, prefix="build-") as temporary:
            work = Path(temporary)
            for archive in archives.values():
                extract_sources(archive, work)
            package = work / identity
            libraries = package / "lib"
            subprocess.run([
                "sh", str(within(ROOT, entry["recipe"])), str(within(ROOT, entry["source"]["path"])),
                str(work / dependencies["lua"]["directory"]), str(work / dependencies["sol2"]["directory"]),
                str(libraries),
            ], check=True, env={**os.environ, "KAGARI_ARCHS": " ".join(architectures)})
            (libraries / "licenses").rename(package / "LICENSES")
            shutil.copyfile(ROOT / "docs/kagari.md", package / "README.md")
            write_json(package / "dependencies.json", dependencies)
            verify_macho(package, architectures)
            try:
                commit = subprocess.check_output(
                    ["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"],
                    text=True, stderr=subprocess.DEVNULL,
                ).strip()
            except subprocess.CalledProcessError:
                commit = None
            manifest = {
                "schemaVersion": 1,
                **{k: entry[k] for k in ("id", "version", "revision", "abi", "minimumOS", "source")},
                "architectures": architectures,
                "signing": "ad-hoc",
                "verification": {"nativeABI": [host], "utataneUI": []},
                "build": {
                    "repositoryCommit": commit, "dirty": bool(git("status", "--porcelain")),
                    "clang": output("xcrun", "clang", "--version"),
                    "sdk": output("xcrun", "--sdk", "macosx", "--show-sdk-version"),
                    "macOS": platform.mac_ver()[0],
                    "inputHashes": {str(p.relative_to(ROOT)): sha256(p) for p in [
                        ROOT / "pyproject.toml", ROOT / "uv.lock", ROOT / ".python-version",
                        ROOT / entry["recipe"], dependencies_path, ROOT / "scripts/build.py",
                        ROOT / "scripts/catalog.py", ROOT / "scripts/smoke_kagari.py",
                        ROOT / "tests/fixtures/kagari/index.lua", ROOT / "catalog/modules/kagari.json",
                        ROOT / "docs/kagari.md", ROOT / "schemas/package.schema.json",
                    ]},
                },
                "files": {str(p.relative_to(package)): sha256(p) for p in sorted(package.rglob("*")) if p.is_file()},
            }
            write_json(package / "module.json", manifest)
            candidate = work / name
            archive_package(package, candidate)
            verify_package(candidate, entry)
            # Run a subprocess against a relocated ZIP. A native crash fails the build;
            # no report or artifact is retained unless every contract check passes.
            subprocess.run([sys.executable, str(ROOT / "scripts/smoke_kagari.py"), str(candidate)], check=True, timeout=60)
            # Publish locally only after the final, packaged bytes passed validation.
            with tempfile.TemporaryDirectory(dir=destination, prefix=".package-") as incoming:
                staged = Path(incoming) / name
                shutil.copyfile(candidate, staged)
                # Exclusive creation avoids replacing another concurrent builder's output.
                os.link(staged, final)
            write_json(final.with_suffix(".sha256.json"), {"file": name, "sha256": sha256(final)})
            print(f"Verified development package: {final}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module")
    parser.add_argument("--archs", nargs="+", choices=("arm64", "x86_64"), default=[platform.machine()])
    parser.add_argument("--cache", type=Path, default=ROOT / "build/cache")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build(args.module, sorted(set(args.archs)), args.cache.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
