#!/usr/bin/env python3
"""Load distributed SAORI packages in Utatane's native helper process."""

import argparse
import json
from pathlib import Path
import tempfile
import zipfile

from catalog import ROOT, read_json, safe_extract, verify_package
from test_cpp_host import Host


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--package", type=Path, nargs="+", action="append", required=True)
    args = parser.parse_args()
    expected = {"saori-cpuid", "kenonoke", "textcopy2", "mciaudior", "wmove"}
    packages = {}
    for archive in (item for group in args.package for item in group):
        with zipfile.ZipFile(archive) as package:
            manifests = [name for name in package.namelist() if name.count("/") == 1 and name.endswith("/module.json")]
            if len(manifests) != 1: raise ValueError(f"Invalid SAORI package: {archive}")
            identity = json.loads(package.read(manifests[0]))["id"]
        if identity not in expected or identity in packages:
            raise ValueError(f"Unknown or repeated SAORI package: {archive}")
        verify_package(archive, read_json(ROOT / f"catalog/modules/{identity}.json"))
        packages[identity] = archive
    if set(packages) != expected:
        raise ValueError(f"Expected all five SAORI packages; missing {sorted(expected - set(packages))}")

    with tempfile.TemporaryDirectory(prefix="Utatane SAORI host 日本語 ") as temporary:
        root = Path(temporary)
        master = root / "ghost/master/saori"
        master.mkdir(parents=True)
        (master / "keyword.txt").write_bytes("飲み物＝日本酒、酒\r\n場所＝酒場\r\n".encode("cp932"))
        for identity, archive in packages.items():
            safe_extract(archive, root / "packages")
            library = root / "packages" / identity / "lib" / f"lib{identity.replace('-', '_')}.dylib"
            moves = []

            def windows(operation, scope, x, speed):
                if operation == 1 and scope == 1: return (1, 100, 200, 50, 80)
                if operation == 2: return (1, 1440, 900, 0, 0)
                if operation == 3:
                    moves.append((scope, x, speed))
                    return (1, 0, 0, 0, 0)
                return (0, 0, 0, 0, 0)

            host = Host(args.host.resolve(), library, master, root / "shared", window_callback=windows)
            try:
                def execute(*arguments):
                    lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8"]
                    lines += [f"Argument{index}: {value}" for index, value in enumerate(arguments)]
                    return host.exchange(1, ("\r\n".join(lines) + "\r\n\r\n").encode()).decode()

                if identity == "saori-cpuid":
                    assert "Result: macOS\r\n" in execute("os.name")
                elif identity == "kenonoke":
                    assert "Result: 場所\r\nValue0: 飲み物\r\n" in execute("GETKEYWORD", "酒場で日本酒を飲む")
                elif identity == "textcopy2":
                    assert execute().startswith("SAORI/1.0 204")
                elif identity == "mciaudior":
                    assert execute("stop").startswith("SAORI/1.0 204")
                else:
                    assert "Result: 100\r\nValue0: 125\r\nValue1: 150\r\n" in execute("GET_POSITION", "kero")
                    assert "Result: 1440\r\nValue0: 900\r\n" in execute("GET_DESKTOP_SIZE")
                    execute("MOVETO", "kero", "30", "5")
                    assert moves == [(1, 30, 5)], moves
                host.close()
            finally:
                host.abort()
            print(f"PASS: Utatane helper + {identity}")


if __name__ == "__main__":
    main()
