#!/usr/bin/env python3
"""Exercise a relocated akari ZIP through a plain C SHIORI host."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/akari.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-akari-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/akari"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "descript.txt").write_text("shiori,akari.dll\n", encoding="utf-8")
        (master / "akari.txt").write_text(
            "＊OnBoot\n・（０）起動。\n＊OnMouseDoubleClick\n・（０）クリック。\n", encoding="utf-8")
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/akari-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libakari.dylib"), str(master)],
                       check=True, timeout=30)
        if not (master / "akari-vars.json").is_file():
            raise ValueError("Expected persisted akari state")
        state = root / "separate state/akari.json"
        subprocess.run([str(executable), str(package / "lib/libakari.dylib"), str(master)],
                       check=True, timeout=30, env={**os.environ, "AKARI_VARIABLE_STORE_PATH": str(state)})
        if not state.is_file():
            raise ValueError("Expected state at the baseware-selected path")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
