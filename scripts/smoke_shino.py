#!/usr/bin/env python3
"""Exercise a relocated shino ZIP through a plain C SHIORI host."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/shino.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-shino-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/shino"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "descript.txt").write_text("sakura.name,忍\n", encoding="utf-8")
        (master / "ai.txt").write_text(
            "\\ev[OnBoot],\\0起動\\e\n"
            "\\ev[OnMouseDoubleClick],\\0クリック\\e\n"
            "\\ev[OnEcho],%ref0\n"
            "\\ev[OnSaori],%saori[fixture.dll,sample]|%saoriresult[1]\n", encoding="utf-8")
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-dynamiclib",
                        str(ROOT / "native/bridge/tests/shino-saori.c"),
                        "-o", str(master / "libfixture.dylib")], check=True)
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/shino-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libshino.dylib"), str(master)],
                       check=True, timeout=30)
        if not (master / "shino-state.json").is_file():
            raise ValueError("Expected persisted shino state")
        state = root / "separate state/shino.json"
        subprocess.run([str(executable), str(package / "lib/libshino.dylib"), str(master)],
                       check=True, timeout=30, env={**os.environ, "SHINO_STATE_PATH": str(state)})
        if not state.is_file():
            raise ValueError("Expected state at the baseware-selected path")
        managed = root / "managed SAORI"
        catalog_module = managed / "fixture/lib"
        catalog_module.mkdir(parents=True)
        (master / "libfixture.dylib").replace(catalog_module / "libfixture.dylib")
        subprocess.run([str(executable), str(package / "lib/libshino.dylib"), str(master)],
                       check=True, timeout=30,
                       env={**os.environ, "SHINO_SAORI_ROOT": str(managed), "SHINO_STATE_PATH": str(state)})


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
