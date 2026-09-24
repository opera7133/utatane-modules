"""Build a pinned upstream SHIORI port and verify the relocated ZIP's conventional ABI."""
import fcntl
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

from catalog import ROOT, git, sha256, verify_package, within, write_json


def verify_library(library, architectures):
    from build import output
    if set(output("xcrun", "lipo", "-archs", str(library)).split()) != set(architectures):
        raise ValueError("SHIORI architectures differ from the requested target")
    subprocess.run(["codesign", "--verify", "--strict", str(library)], check=True)
    for arch in architectures:
        for line in output("otool", "-arch", arch, "-L", str(library)).splitlines()[1:]:
            dependency = line.strip().split(" ", 1)[0]
            if dependency != f"@rpath/{library.name}" and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                raise ValueError(f"Non-relocatable dependency: {dependency}")
        if "minos 14.0" not in output("otool", "-arch", arch, "-l", str(library)):
            raise ValueError("Expected macOS 14 deployment target")
        symbols = {line.split()[-1] for line in output("nm", "-arch", arch, "-gU", str(library)).splitlines() if line.split()}
        if not {"_load", "_loadu", "_request", "_unload"} <= symbols:
            raise ValueError("Conventional SHIORI entry points missing")


def build_upstream(entry, architectures, cache, destination):
    from build import archive_package, output
    identity = entry["id"]
    cpp = identity in ("yaya", "satori")
    host = platform.machine()
    if host not in architectures:
        raise ValueError("Include the host architecture to execute the packaged ABI")
    name = f"{identity}-{entry['version']}-r{entry['revision']}-macos-{'_'.join(architectures)}.zip"
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / name
    if final.exists():
        raise ValueError(f"Refusing to overwrite a versioned artifact: {final}")
    cache.mkdir(parents=True, exist_ok=True)
    cargo = os.environ.get("CARGO", "cargo")
    with (cache / f"build-{identity}.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(dir=cache, prefix=f"{identity}-") as temporary:
            work = Path(temporary)
            package = work / identity
            subprocess.run(["sh", str(within(ROOT, entry["recipe"])), str(within(ROOT, entry["source"]["path"])),
                            str(package / "lib"), str(work / "cpp") if cpp else str(cache / f"{identity}-rust"), " ".join(architectures)],
                           check=True, env={**os.environ, f"{identity.upper()}_TOOLCHAIN": "1.93.0", "PYTHON": sys.executable})
            verify_library(package / f"lib/lib{identity}.dylib", architectures)
            if identity == "pasta":
                from rust_licenses import collect
                collect(within(ROOT, entry["source"]["path"]), package / "LICENSES", cargo)
            else:
                (package / "lib/licenses").rename(package / "LICENSES")
            shutil.copyfile(ROOT / entry["instructions"], package / "README.md")
            try:
                commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"],
                                                 text=True, stderr=subprocess.DEVNULL).strip()
            except subprocess.CalledProcessError:
                commit = None
            inputs = ["pyproject.toml", "uv.lock", ".python-version", entry["recipe"], entry["instructions"],
                      f"catalog/modules/{identity}.json", "schemas/package.schema.json", "scripts/catalog.py",
                      "scripts/build.py", "scripts/build_upstream.py", "scripts/smoke_cpp.py" if cpp else f"scripts/smoke_{identity}.py"]
            if cpp:
                inputs += ["scripts/compile_cpp.py"]
                inputs += [str(p.relative_to(ROOT)) for folder in ("recipes/cpp", f"recipes/{identity}") for p in (ROOT / folder).rglob("*") if p.is_file()]
            if identity == "pasta":
                inputs += ["scripts/rust_licenses.py"]
                inputs += [str(p.relative_to(ROOT)) for p in (ROOT / "recipes/pasta/licenses").rglob("*") if p.is_file()]
            manifest = {
                "schemaVersion": 1,
                **{key: entry[key] for key in ("id", "version", "revision", "abi", "minimumOS", "source")},
                "architectures": architectures, "signing": "ad-hoc",
                "verification": {"nativeABI": [host], "utataneUI": []},
                "build": {"repositoryCommit": commit, "dirty": bool(git("status", "--porcelain")),
                          "clang": output("xcrun", "clang", "--version"), "compiler": output("xcrun", "clang++", "--version") if cpp else output(cargo, "+1.93.0", "--version"),
                          "sdk": output("xcrun", "--sdk", "macosx", "--show-sdk-version"),
                          "macOS": platform.mac_ver()[0],
                          "inputHashes": {name: sha256(ROOT / name) for name in inputs}},
                "files": {str(p.relative_to(package)): sha256(p) for p in sorted(package.rglob("*")) if p.is_file()},
            }
            write_json(package / "module.json", manifest)
            candidate = work / name
            archive_package(package, candidate)
            verify_package(candidate, entry)
            subprocess.run([sys.executable, str(ROOT / ("scripts/smoke_cpp.py" if cpp else f"scripts/smoke_{identity}.py")), str(candidate)], check=True, timeout=60)
            with tempfile.TemporaryDirectory(dir=destination, prefix=".package-") as incoming:
                staged = Path(incoming) / name
                shutil.copyfile(candidate, staged)
                os.link(staged, final)
            write_json(final.with_suffix(".sha256.json"), {"file": name, "sha256": sha256(final)})
            print(f"Verified development package: {final}", flush=True)
