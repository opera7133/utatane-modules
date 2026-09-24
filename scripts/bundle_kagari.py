#!/usr/bin/env python3
"""Build and embed pinned kagari/Lua libraries without host package-manager paths."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIRECTORY = Path(__file__).resolve().parent
DEPENDENCIES_FILE = ROOT / "recipes/kagari/dependencies.json"
KAGARI = ROOT / "sources/kagari"
RECIPE = ROOT / "recipes/kagari/build.sh"
from build import verified_archive, extract_sources, verify_macho
from catalog import modules
LIBRARIES = ("libkagari.dylib", "liblua5.4.dylib")


def build_key(architectures):
    inputs = [Path(__file__), DEPENDENCIES_FILE, RECIPE, SCRIPT_DIRECTORY / "build.py",
              ROOT / "catalog/modules/kagari.json"]
    inputs += [KAGARI / name for name in ("kagari.cpp", "kagari.h", "kagari_unix.cpp", "kagari_unix.h", "LICENSE")]
    hasher = hashlib.sha256(" ".join(architectures).encode())
    for path in inputs:
        hasher.update(path.read_bytes())
    for command in (["xcrun", "clang", "--version"], ["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                    ["xcrun", "--sdk", "macosx", "--show-sdk-version"]):
        hasher.update(subprocess.check_output(command))
    return hasher.hexdigest()


def bundle(output, cache, architectures):
    modules()  # Verify the pinned submodule and dependency metadata before using the cache.
    dependencies = json.loads(DEPENDENCIES_FILE.read_text())
    cache.mkdir(parents=True, exist_ok=True)
    # Debug, Release and command-line builds may share downloaded sources/cache.
    with (cache / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        artifact = cache / "artifacts" / build_key(architectures)
        if not artifact.exists():
            downloads = cache / "downloads"
            downloads.mkdir(exist_ok=True)
            archives = {name: verified_archive(item, downloads) for name, item in dependencies.items()}
            with tempfile.TemporaryDirectory(dir=cache, prefix="build-") as temporary:
                work = Path(temporary)
                for archive in archives.values():
                    extract_sources(archive, work)
                built = work / "stage/lib"
                subprocess.run([
                    "sh", str(RECIPE), str(KAGARI),
                    str(work / dependencies["lua"]["directory"]),
                    str(work / dependencies["sol2"]["directory"]), str(built),
                ], check=True, env={**os.environ, "KAGARI_ARCHS": " ".join(architectures)})
                verify_macho(work / "stage", architectures)
                shutil.copy2(DEPENDENCIES_FILE, built / "dependencies.json")
                for library in LIBRARIES:
                    subprocess.run(["xcrun", "lipo", str(built / library), "-verify_arch", *architectures], check=True)
                artifact.parent.mkdir(exist_ok=True)
                built.rename(artifact)
        output.mkdir(parents=True, exist_ok=True)
        for source in artifact.rglob("*"):
            if source.is_file():
                destination = output / source.relative_to(artifact)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if not destination.exists() or source.read_bytes() != destination.read_bytes():
                    shutil.copy2(source, destination)
        # Match the app's signing identity when Xcode signing is enabled. Local
        # unsigned/CI builds retain the ad-hoc signatures from the build script.
        identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY", "")
        if identity and os.environ.get("CODE_SIGNING_ALLOWED") != "NO":
            for library in LIBRARIES:
                subprocess.run(["codesign", "--force", "--sign", identity, str(output / library)], check=True)
        print(f"Bundled kagari ({' '.join(architectures)}): {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=ROOT / "build/app-bundle")
    parser.add_argument("--archs", nargs="+", choices=("arm64", "x86_64"), default=("arm64", "x86_64"))
    args = parser.parse_args()
    bundle(args.output.resolve(), args.cache.resolve(), sorted(set(args.archs)))


if __name__ == "__main__":
    main()
