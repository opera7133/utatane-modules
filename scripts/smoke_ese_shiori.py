#!/usr/bin/env python3
"""Exercise a relocated ese-shiori ZIP through a plain C SHIORI host."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/ese-shiori.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-ese-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/ese-shiori"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "eseai.ini").write_text("[ESEAI]\nDIC_CHAR_SET=UTF-8\n", encoding="utf-8")
        (master / "eseai_test.txt").write_text(
            '##EVNT=("OnBoot")\n\\1\\s1起動\\e\n'
            '##EVNT=("OnProbe")\n$PUSH("hello",1,0)$WRITEFILE("USER.DAT",1,1)done\n',
            encoding="utf-8",
        )
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/ese-conventional.c"), "-o", str(executable)], check=True)
        state = root / "state 日本語/ese-shiori-state.json"
        subprocess.run([str(executable), str(package / "lib/libese-shiori.dylib"), str(master)],
                       check=True, timeout=30, env={**os.environ, "ESE_SHIORI_STATE_PATH": str(state)})
        if not state.is_file():
            raise ValueError("Expected ese-shiori state at the baseware-selected path")
        if (state.parent / "ese-shiori-files/USER.DAT").read_text(encoding="utf-8") != "hello\n":
            raise ValueError("Expected $WRITEFILE output beside the selected state path")
        if (master / "USER.DAT").exists():
            raise ValueError("$WRITEFILE unexpectedly modified the ghost directory")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
