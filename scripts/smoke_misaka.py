#!/usr/bin/env python3
"""Exercise a relocated packaged dylib from a C consumer, without Swift linking."""
from pathlib import Path
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/misaka-native.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-misaka-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/misaka-native"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "misaka.ini").write_bytes("dictionaries\n{\nmisaka.txt\n}\n".encode("cp932"))
        (master / "misaka.txt").write_bytes(('$_Variable\n{$count=0}\n\n'
            '$OnBoot\n{$count++}{$count}\n\n$OnSaori\n{$saori("test.dll","arg")}\n\n'
            '$OnLoad\n{$loadsaori("test.dll")}loaded\n\n$OnUnload\n{$unloadsaori("test.dll")}unloaded\n\n'
            '$OnEcho\n{$reference(0)}\n').encode("cp932"))
        initialization = root / "initializing-master"
        initialization.mkdir()
        (initialization / "misaka.ini").write_bytes((master / "misaka.ini").read_bytes())
        (initialization / "misaka.txt").write_bytes('$_Variable\n{$loadsaori("test.dll")}\n'.encode("cp932"))
        blocked = root / "blocked"
        blocked.write_text("block creation of a directory to test retryable save errors")
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        "-I", str(ROOT / "native/bridge/include"), str(ROOT / "native/bridge/tests/host.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libmisaka.dylib"), str(master),
                        str(root / "state/one.json"), str(root / "state/two.json"),
                        str(blocked / "state.json"), str(initialization)], check=True, timeout=30)
        conventional = root / "conventional 日本語"
        conventional.mkdir()
        for name in ("misaka.ini", "misaka.txt"):
            (conventional / name).write_bytes((master / name).read_bytes())
        standard_host = root / "conventional-host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/conventional.c"), "-o", str(standard_host)], check=True)
        subprocess.run([str(standard_host), str(package / "lib/libmisaka.dylib"),
                        str(conventional)], check=True, timeout=30)
        if sorted(p.name for p in master.iterdir()) != ["misaka.ini", "misaka.txt"]:
            raise ValueError("The module wrote state into the ghost directory")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
