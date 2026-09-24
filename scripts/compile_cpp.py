#!/usr/bin/env python3
"""Compile pinned YAYA/SATORI sources with the distribution's POSIX entry adapter."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    identity, source, output, work, archs = sys.argv[1:]
    source, output, work = map(lambda p: Path(p).resolve(), (source, output, work))
    output.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    tree = work / "source"
    shutil.copytree(source, tree / "Vendor", ignore=shutil.ignore_patterns(".git"))
    recipe = ROOT / f"recipes/{identity}"
    for file in recipe.glob("*.h"):
        shutil.copyfile(file, tree / file.name)
    # Rename only the legacy long-width entry points in a disposable build copy.
    # The pinned source and its history stay unchanged.
    if identity == "yaya":
        for filename in ("aya5.cpp", "aya5.h"):
            path = tree / "Vendor" / filename
            raw = path.read_bytes()
            raw = re.sub(rb'(?<!->)\b(loadu|load|unload|request)(?=\s*\()', rb'legacy_\1', raw)
            path.write_bytes(raw)
    if identity == "yaya":
        path = tree / "Vendor/lib1.cpp"
        raw = path.read_bytes()
        needle = b"        nativeSaori = true;\n        hDLL = reinterpret_cast<void *>(1);\n        return 1;\n    }"
        if raw.count(needle) != 1: raise ValueError("YAYA SAORI adapter anchor changed")
        path.write_bytes(raw.replace(needle, needle + b"\n    return 0; // Conventional macOS SAORI only.\n"))
    else:
        path = tree / "Vendor/satori/shiori_plugin.cpp"
        raw = path.read_bytes()
        start = raw.index(b"#ifdef POSIX\r\n\t\telse if")
        end = raw.index(b"#endif\r\n\t\telse {", start)
        replacement = b"#ifdef POSIX\n\t\telse if (true) {\n\t\t\tmDllData[fullpath].mRefCount=1;\n\t\t\tmDllData[fullpath].m_pSaoriClient=new NativeSwiftSaori(fullpath);\n\t\t}\n"
        raw = raw[:start] + replacement + raw[end:]
        raw = raw.replace(b'#include "../../NativeSwiftSaori.h"', b'#include "../../NativeSwiftSaori.h"\n#include "../_/charset.h"')
        raw = raw.replace(b'mBaseFolder + filename', b'mBaseFolder + SJIStoUTF8(filename)')
        path.write_bytes(raw)
    sources = [tree / "Vendor" / name for name in json.loads((recipe / "sources.json").read_text())]
    sources += [ROOT / "recipes/cpp/SHIORI.cpp", ROOT / "recipes/cpp/SaoriLibrary.cpp"]
    if identity == "satori":
        sources += [recipe / "CharsetPOSIX.cpp", recipe / "NativeSwiftSaori.cpp"]
    common = ["-O2", "-DNDEBUG", "-DPOSIX", "-fvisibility=hidden", "-mmacosx-version-min=14.0",
              "-I", str(tree), "-I", str(tree / "Vendor"), "-I", str(ROOT / "recipes/cpp")]
    if identity == "yaya": common += ["-DYAYA_MODULE"]
    else: common += ["-DSATORI_DLL", "-I", str(tree / "Vendor/satori"), "-I", str(tree / "Vendor/_")]
    libraries = []
    for arch in archs.split():
        if arch not in ("arm64", "x86_64"): raise ValueError(arch)
        directory = work / arch; directory.mkdir()
        def compile_one(item):
            index, path = item
            obj = directory / f"{index}.o"
            compiler = ["xcrun", "clang"] if path.suffix == ".c" else ["xcrun", "clang++", "-std=c++17"]
            subprocess.run(compiler + common + ["-arch", arch, "-c", str(path), "-o", str(obj)], check=True)
            return obj
        with ThreadPoolExecutor(max_workers=min(os.cpu_count() or 2, 6)) as pool:
            objects = list(pool.map(compile_one, enumerate(sources)))
        library = directory / f"lib{identity}.dylib"
        subprocess.run(["xcrun", "clang++", "-arch", arch, "-dynamiclib", "-mmacosx-version-min=14.0",
                        *map(str, objects), "-liconv", "-install_name", f"@rpath/{library.name}", "-o", str(library)], check=True)
        libraries.append(library)
    final = output / f"lib{identity}.dylib"
    subprocess.run(["xcrun", "lipo", "-create", *map(str, libraries), "-output", str(final)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(final)], check=True)
    licenses = output / "licenses"; licenses.mkdir()
    license_id = "BSD-3-Clause" if identity == "yaya" else "BSD-2-Clause"
    shutil.copyfile(source / ("LICENSE" if identity == "yaya" else "LICENSE.txt"), licenses / f"{identity}-{license_id}.txt")
    shutil.copyfile(ROOT / "LICENSE", licenses / "utatane-MIT.txt")
    extra_licenses = recipe / "licenses"
    if extra_licenses.is_dir():
        for path in extra_licenses.iterdir():
            if path.is_file(): shutil.copyfile(path, licenses / path.name)
    # Keep bundled notices for vendored hash/random algorithms alongside the upstream license.
    for path in source.rglob("*"):
        if path.is_file() and path.name.lower() in ("md5c.c", "md5.h", "sha1.c", "sha1.h", "mt19937ar.cpp", "crc32.c", "zlib.h", "zconf.h"):
            name = str(path.relative_to(source)).replace("/", "-")
            shutil.copyfile(path, licenses / name)


if __name__ == "__main__":
    main()
