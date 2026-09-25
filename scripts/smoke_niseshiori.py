#!/usr/bin/env python3
"""Exercise a relocated niseshiori ZIP through a plain C SHIORI host."""

from pathlib import Path
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/nise-shiori.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-nise-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/nise-shiori"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "ai.txt").write_text(
            "#Charset: UTF-8\n"
            "\\ev,OnBoot & %hour>=0,\\0起動\\set[count=1+2]\\e\n"
            "\\ev,OnMouseDoubleClick & %get[count]=3,\\0クリック\\e\n"
            "\\ev,OnEcho,%ref0\n", encoding="utf-8")
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/nise-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libniseshiori.dylib"), str(master)],
                       check=True, timeout=30)
        if not (master / "nise-shiori-state.json").is_file():
            raise ValueError("Expected persisted niseshiori state")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
