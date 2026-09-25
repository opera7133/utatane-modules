#!/usr/bin/env python3
"""Exercise a relocated hisui ZIP through a plain C SHIORI host."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/hisui.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-hisui-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/hisui"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "descript.txt").write_text("sakura.name,翡翠\nkero.name,相方\n", encoding="utf-8")
        dictionary = master / "hisui_base"
        dictionary.mkdir()
        (dictionary / "fixture.tlk").write_text(
            "{\ntoken:OnHisuiFreeTalk\nscript:\\0会話\\e\n}\n"
            "{\ntoken:OnBoot\nscript:\\0起動\\e\n}\n"
            "{\ntoken:OnMouseDoubleClick\nscript:\\0クリック\\e\n}\n"
            "{\ntoken:OnEcho\nscript:%ref0\n}\n", encoding="utf-8")
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/hisui-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libhisui.dylib"), str(master)],
                       check=True, timeout=30)
        if not (master / "hisui-state.json").is_file():
            raise ValueError("Expected persisted hisui state")
        state = root / "separate state/hisui.json"
        subprocess.run([str(executable), str(package / "lib/libhisui.dylib"), str(master)],
                       check=True, timeout=30, env={**os.environ, "HISUI_STATE_PATH": str(state)})
        if not state.is_file():
            raise ValueError("Expected state at the baseware-selected path")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
