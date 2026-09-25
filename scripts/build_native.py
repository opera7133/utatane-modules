"""Build the in-repository Swift module using the shared package contract."""
import fcntl
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

from catalog import ROOT, git, sha256, verify_package, write_json


def verify_library(library, architectures, *, misaka=False):
    from build import output
    if set(output("xcrun", "lipo", "-archs", str(library)).split()) != set(architectures):
        raise ValueError("Swift module architectures differ from the requested target")
    subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True)
    for arch in architectures:
        dependencies = output("otool", "-arch", arch, "-L", str(library)).splitlines()[1:]
        for line in dependencies:
            dependency = line.strip().split(" ", 1)[0]
            if dependency == f"@rpath/{library.name}" or dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            # Swift runtime compatibility libraries are shipped by the OS.
            if dependency.startswith("@rpath/libswift") and dependency.endswith(".dylib"):
                continue
            raise ValueError(f"Non-relocatable Swift dependency: {dependency}")
        commands = output("otool", "-arch", arch, "-l", str(library))
        if "minos 14.0" not in commands or "path /usr/lib/swift " not in commands:
            raise ValueError("Expected macOS 14 deployment and system Swift runtime lookup")
        symbols = {line.split()[-1] for line in output("nm", "-arch", arch, "-gU", str(library)).splitlines() if line.split()}
        required = {"_load", "_loadu", "_request", "_unload"}
        if misaka:
            required.add("_utatane_misaka_bridge")
        if not required <= symbols:
            raise ValueError("SHIORI entry points missing")


def build_native(entry, architectures, cache, destination):
    from build import archive_package, output
    identity = entry["id"]
    misaka = identity == "misaka-native"
    nise = identity == "nise-shiori"
    ese = identity == "ese-shiori"
    saori = entry["kinds"] == ["saori"]
    product = "misaka" if misaka else "niseshiori" if nise else "ese-shiori" if ese else identity.replace("-", "_")
    smoke_script = "smoke_misaka.py" if misaka else "smoke_niseshiori.py" if nise else "smoke_ese_shiori.py" if ese else "smoke_saori.py"
    host = platform.machine()
    if host not in architectures:
        raise ValueError("Include the host architecture to execute the packaged ABI")
    name = f"{entry['id']}-{entry['version']}-r{entry['revision']}-macos-{'_'.join(architectures)}.zip"
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / name
    if final.exists():
        raise ValueError(f"Refusing to overwrite a versioned artifact: {final}")
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "build-native.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(dir=cache, prefix="native-") as temporary:
            work = Path(temporary)
            package = work / entry["id"]
            # Every local module belongs to the same Swift package. Keep one
            # scratch directory so later products reuse compiled dependencies.
            scratch = cache / "native-swift" / "_".join(architectures)
            subprocess.run(["sh", str(ROOT / entry["recipe"]), str(ROOT / "native"),
                            str(package / "lib"), str(scratch), " ".join(architectures)], check=True)
            verify_library(package / f"lib/lib{product}.dylib", architectures, misaka=misaka)
            (package / "LICENSES").mkdir()
            shutil.copyfile(ROOT / "LICENSE", package / "LICENSES/utatane-MIT.txt")
            shutil.copyfile(ROOT / entry["instructions"], package / "README.md")
            try:
                commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"],
                                                  text=True, stderr=subprocess.DEVNULL).strip()
            except subprocess.CalledProcessError:
                commit = None
            inputs = [ROOT / "pyproject.toml", ROOT / "uv.lock", ROOT / ".python-version", ROOT / entry["recipe"], ROOT / f"catalog/modules/{identity}.json", ROOT / "LICENSE"]
            inputs += [p for directory in ("native",) for p in (ROOT / directory).rglob("*")
                       if p.is_file() and not any(part.startswith(".") for part in p.relative_to(ROOT).parts)]
            inputs += [ROOT / "scripts" / name for name in ("build.py", "build_native.py", "catalog.py", smoke_script)]
            inputs += [ROOT / entry["instructions"], ROOT / "schemas/package.schema.json"]
            if saori:
                inputs.append(ROOT / "recipes/saori/build.sh")
            manifest = {
                "schemaVersion": 1,
                **{key: entry[key] for key in ("id", "version", "revision", "abi", "minimumOS", "source")},
                "architectures": architectures, "signing": "ad-hoc",
                "verification": {"nativeABI": [host], "utataneUI": []},
                "build": {"repositoryCommit": commit, "dirty": bool(git("status", "--porcelain")),
                          "clang": output("xcrun", "clang", "--version"), "swift": output("swift", "--version"),
                          "sdk": output("xcrun", "--sdk", "macosx", "--show-sdk-version"),
                          "macOS": platform.mac_ver()[0],
                          "inputHashes": {str(p.relative_to(ROOT)): sha256(p) for p in sorted(set(inputs))}},
                "files": {str(p.relative_to(package)): sha256(p) for p in sorted(package.rglob("*")) if p.is_file()},
            }
            write_json(package / "module.json", manifest)
            candidate = work / name
            archive_package(package, candidate)
            verify_package(candidate, entry)
            subprocess.run([sys.executable, str(ROOT / "scripts" / smoke_script), str(candidate)], check=True, timeout=60)
            with tempfile.TemporaryDirectory(dir=destination, prefix=".package-") as incoming:
                staged = Path(incoming) / name
                shutil.copyfile(candidate, staged)
                os.link(staged, final)
            write_json(final.with_suffix(".sha256.json"), {"file": name, "sha256": sha256(final)})
            print(f"Verified development package: {final}", flush=True)
