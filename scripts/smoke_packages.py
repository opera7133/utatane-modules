#!/usr/bin/env python3
"""Run native ABI checks against every ZIP from one build."""

import argparse
import json
from pathlib import Path
import platform
import subprocess
import sys
import zipfile

from catalog import modules, sha256, verify_package, write_json


def smoke_commands(archives):
    expected = {item["id"]: item for item in modules() if item["delivery"] == "binary"}
    found = {}
    for archive in archives:
        with zipfile.ZipFile(archive) as source:
            manifests = [name for name in source.namelist()
                         if name.count("/") == 1 and name.endswith("/module.json")]
            if len(manifests) != 1:
                raise ValueError(f"Expected one manifest: {archive}")
            identity = json.loads(source.read(manifests[0]))["id"]
        if identity not in expected or identity in found:
            raise ValueError(f"Unknown or duplicate package: {identity}")
        manifest = verify_package(archive, expected[identity])
        if platform.machine() not in manifest["architectures"]:
            raise ValueError(f"Host architecture missing: {identity}")
        found[identity] = archive
    missing = expected.keys() - found.keys()
    if missing:
        raise ValueError(f"Missing packages: {', '.join(sorted(missing))}")

    commands = []
    for identity, archive in sorted(found.items()):
        if identity in ("yaya", "satori"):
            commands.append([sys.executable, "scripts/smoke_cpp.py", str(archive),
                             "--saori-package", str(found["saori-cpuid"])])
        elif expected[identity]["kinds"] == ["saori"]:
            commands.append([sys.executable, "scripts/smoke_saori.py", str(archive)])
        else:
            script = {"misaka-native": "smoke_misaka.py", "nise-shiori": "smoke_niseshiori.py"}.get(
                identity, f"smoke_{identity}.py")
            commands.append([sys.executable, f"scripts/{script}", str(archive)])
    return commands, found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", type=Path, nargs="+")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    commands, found = smoke_commands([path.resolve() for path in args.archives])
    for command in commands:
        subprocess.run(command, check=True, timeout=90)
    if args.report:
        write_json(args.report.resolve(), {
            "schemaVersion": 1,
            "architecture": platform.machine(),
            "artifacts": [{"id": identity, "sha256": sha256(archive)}
                          for identity, archive in sorted(found.items())],
        })
    print(f"PASS: {len(args.archives)} packages on this host")


if __name__ == "__main__":
    main()
