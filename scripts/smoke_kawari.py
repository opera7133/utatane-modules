#!/usr/bin/env python3
"""Exercise a relocated kawari ZIP through a plain C SHIORI host."""

from pathlib import Path
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/kawari.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-kawari-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/kawari"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "kawari.ini").write_bytes("dict : events.txt\r\n".encode("shift_jis"))
        (master / "events.txt").write_bytes(
            "event.OnBoot : \\0起動\\e\r\nevent.OnMouseDoubleClick : \\0クリック\\e\r\n".encode("shift_jis"))
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/kawari-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libkawari.dylib"), str(master)],
                       check=True, timeout=30)


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
