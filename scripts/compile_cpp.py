#!/usr/bin/env python3
"""Compile pinned YAYA/SATORI sources with the distribution's POSIX entry adapter."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import runpy
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
    if identity == "yaya-6":
        # The upstream POSIX makefile converts these CP932 translation units too.
        for path in (tree / "Vendor").rglob("*.cpp"):
            if path.parts[-2] in ("tinyxml2",):
                continue
            converted = subprocess.run(["iconv", "-f", "CP932", "-t", "UTF-8", "-c"],
                                       input=path.read_bytes(), stdout=subprocess.PIPE, check=True)
            path.write_bytes(converted.stdout)
    recipe = ROOT / f"recipes/{identity}"
    for file in recipe.glob("*.h"):
        shutil.copyfile(file, tree / file.name)
    # Rename only the legacy long-width entry points in a disposable build copy.
    # The pinned source and its history stay unchanged.
    if identity in ("yaya", "yaya-6"):
        for filename in ("aya5.cpp", "aya5.h"):
            path = tree / "Vendor" / filename
            raw = path.read_bytes()
            raw = re.sub(rb'(?<!->)\b(loadu|load|unload|request)(?=\s*\()', rb'legacy_\1', raw)
            path.write_bytes(raw)
    if identity == "yaya-6":
        # Upstream's ptrdiff_t overload is ambiguous with the macOS arm64 ABI.
        path = tree / "Vendor/function.cpp"
        raw = path.read_bytes()
        needle = b"CValue(st.linecount)"
        if raw.count(needle) != 2: raise ValueError("YAYA 6 linecount patch anchor changed")
        path.write_bytes(raw.replace(needle, b"CValue(static_cast<yaya::int_t>(st.linecount))"))
        path = tree / "Vendor/sha1.h"
        raw = path.read_bytes()
        needle = b"#if (_MSC_VER >= 1400)"
        if raw.count(needle) != 1: raise ValueError("YAYA 6 stdint patch anchor changed")
        path.write_bytes(raw.replace(needle, b"#if defined(__APPLE__) || (_MSC_VER >= 1400)"))
        path = tree / "Vendor/sysfunc.cpp"
        raw = path.read_bytes()
        needle = b'#include "sysfunc.h"'
        if raw.count(needle) != 1: raise ValueError("YAYA 6 fcntl patch anchor changed")
        path.write_bytes(raw.replace(needle, b"#undef FREAD\n#undef FWRITE\n" + needle))
        path = tree / "Vendor/parser0.cpp"
        raw = path.read_bytes()
        needle = b"inline CDefine::CDefine("
        if raw.count(needle) != 1: raise ValueError("YAYA 6 CDefine patch anchor changed")
        path.write_bytes(raw.replace(needle, b"CDefine::CDefine("))
        path = tree / "Vendor/basis.cpp"
        raw = path.read_bytes()
        needle = b"Ccct::MbcsToUcs2Buf(base_path, mbpath, CHARSET_UTF8);"
        if raw.count(needle) != 2: raise ValueError("YAYA 6 path patch anchor changed")
        start = raw.rfind(needle)
        raw = raw[:start] + b"base_path = widen(mbpath);" + raw[start + len(needle):]
        path.write_bytes(raw)
        runpy.run_path(str(recipe / "patch_native_saori.py"))["patch"](tree)
        path = tree / "Vendor/lib1.cpp"
        raw = path.read_bytes()
        needle = b'#include "lib.h"'
        if raw.count(needle) != 1: raise ValueError("YAYA 6 libgen patch anchor changed")
        path.write_bytes(raw.replace(needle, b'#include <libgen.h>\n' + needle))
    if identity == "yaya":
        path = tree / "Vendor/lib1.cpp"
        raw = path.read_bytes()
        needle = b"        nativeSaori = true;\n        hDLL = reinterpret_cast<void *>(1);\n        return 1;\n    }"
        if raw.count(needle) != 1: raise ValueError("YAYA SAORI adapter anchor changed")
        path.write_bytes(raw.replace(needle, needle + b"\n    return 0; // Conventional macOS SAORI only.\n"))
    elif identity == "satori":
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
    if identity in ("yaya", "yaya-6"): common += ["-DYAYA_MODULE"]
    else: common += ["-DSATORI_DLL", "-I", str(tree / "Vendor/satori"), "-I", str(tree / "Vendor/_")]
    libraries = []
    for arch in archs.split():
        if arch not in ("arm64", "x86_64"): raise ValueError(arch)
        directory = work / arch; directory.mkdir()
        def compile_one(item):
            index, path = item
            obj = directory / f"{index}.o"
            cpp_standard = "c++14" if identity == "yaya-6" and tree / "Vendor" in path.parents else "c++17"
            compiler = ["xcrun", "clang"] if path.suffix == ".c" else ["xcrun", "clang++", f"-std={cpp_standard}"]
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
    license_id = "BSD-3-Clause" if identity in ("yaya", "yaya-6") else "BSD-2-Clause"
    shutil.copyfile(source / ("LICENSE" if identity in ("yaya", "yaya-6") else "LICENSE.txt"), licenses / f"{identity}-{license_id}.txt")
    shutil.copyfile(ROOT / "LICENSE", licenses / "utatane-MIT.txt")
    if identity == "yaya-6":
        for source_name, notice_name in (("parson/LICENSE", "parson-MIT.txt"),
                                         ("tinyxml2/LICENSE.txt", "tinyxml2-zlib.txt"),
                                         ("sqlite/LICENSE", "sqlite-amalgamation-BSD-3-Clause.txt")):
            shutil.copyfile(source / source_name, licenses / notice_name)
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
