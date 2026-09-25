#!/usr/bin/env python3
"""Exercise a relocated yuhna ZIP through a plain C SHIORI host."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/yuhna.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-yuhna-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/yuhna"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        data = bytearray(b"YDF/1.07 fixture")
        data.extend((0, 0, 0, 4))
        for name, script in (
            ("OnYuhnaRandomTalk", "\\0ランダム\\e"),
            ("OnBoot", "\\0起動\\e"),
            ("OnYuhnaMouseDoubleClick0", "\\0クリック\\e"),
            ("OnEcho", "%ref0"),
        ):
            name_bytes = name.encode("ascii")
            script_bytes = script.encode("shift_jis")
            data.extend(len(name_bytes).to_bytes(2, "big"))
            data.extend(name_bytes)
            data.extend((0, 0, 0, 0, 1))
            data.extend(len(script_bytes).to_bytes(2, "big"))
            data.append(0)
            data.extend(script_bytes)
        (master / "dic.ydf").write_bytes(data)
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/yuhna-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libyuhna.dylib"), str(master)],
                       check=True, timeout=30)
        if not (master / "yuhna-state.json").is_file():
            raise ValueError("Expected persisted yuhna state")
        state = root / "separate state/yuhna.json"
        subprocess.run([str(executable), str(package / "lib/libyuhna.dylib"), str(master)],
                       check=True, timeout=30, env={**os.environ, "YUHNA_STATE_PATH": str(state)})
        if not state.is_file():
            raise ValueError("Expected state at the baseware-selected path")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
