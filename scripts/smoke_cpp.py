#!/usr/bin/env python3
"""Probe YAYA/SATORI dictionary, persistence and conventional SAORI loading."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile


def prepare_dictionary(identity, root):
    (root / "keyword.txt").write_bytes("飲み物＝日本酒、酒\r\n場所＝酒場\r\n".encode("cp932"))
    if identity == "yaya":
        (root / "yaya.txt").write_text("charset, UTF-8\ndic, probe.dic\n")
        (root / "probe.dic").write_text(r'''
request
{
_value = ""
if STRSTR(_argv[0], "ID: OnKeyword", 0) >= 0 {
    _loaded = LOADLIB("kenonoke.dll")
    _answer = REQUESTLIB("kenonoke.dll", "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: GETKEYWORD%(CHR(13))%(CHR(10))Argument1: 酒場で日本酒を飲む%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))")
    _value = "failed"
    if STRSTR(_answer, "場所", 0) >= 0 { _value = "場所" }
    _unloaded = UNLOADLIB("kenonoke.dll")
} elseif STRSTR(_argv[0], "ID: OnSaori", 0) >= 0 {
    _loaded = LOADLIB("saori_cpuid.dll")
    _answer = REQUESTLIB("saori_cpuid.dll", "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: Shift_JIS%(CHR(13))%(CHR(10))Argument0: os.name%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))")
    _value = "failed"
    if STRSTR(_answer, "macOS", 0) >= 0 { _value = "macOS" }
    _unloaded = UNLOADLIB("saori_cpuid.dll")
} else {
    probe_count++
    _value = "こんにちは count=%(probe_count)"
}
"SHIORI/3.0 200 OK%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Value: %(_value)%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
}
''')
    else:
        (root / "dic00.txt").write_bytes("＊OnBoot\r\n：こんにちは。\r\n＊OnSet\r\n＄確認\t保存できた\r\n：設定。\r\n＊OnRead\r\n：値は（確認）。\r\n＊OnSaori\r\n：OSは（os_name）。\r\n＊OnKeyword\r\n：分類は（分類、酒場で日本酒を飲む）。\r\n".encode("cp932"))
        (root / "satori_conf.txt").write_bytes("＠SAORI\r\nos_name,saori_cpuid.dll,os.name\r\n分類,kenonoke.dll,GETKEYWORD\r\n".encode("cp932"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("--saori-library", type=Path)
    parser.add_argument("--saori-package", type=Path)
    args = parser.parse_args()
    if args.library.suffix == ".zip":
        from catalog import ROOT, read_json, safe_extract, verify_package
        with zipfile.ZipFile(args.library) as archive:
            names = [n for n in archive.namelist() if n.count("/") == 1 and n.endswith("/module.json")]
            if len(names) != 1: raise ValueError("Expected one manifest")
            identity = json.loads(archive.read(names[0]))["id"]
        verify_package(args.library, read_json(ROOT / f"catalog/modules/{identity}.json"))
        with tempfile.TemporaryDirectory(prefix="SHIORI ZIP 日本語 ") as temporary:
            root = Path(temporary); safe_extract(args.library, root)
            command = [sys.executable, __file__, str(root / identity / f"lib/lib{identity}.dylib")]
            if args.saori_package:
                verify_package(args.saori_package, read_json(ROOT / "catalog/modules/saori-cpuid.json"))
                safe_extract(args.saori_package, root / "saori")
                command += ["--saori-library", str(root / "saori/saori-cpuid/lib/libsaori_cpuid.dylib")]
            elif args.saori_library: command += ["--saori-library", str(args.saori_library.resolve())]
            subprocess.run(command, check=True, timeout=40)
        return
    identity = args.library.stem.removeprefix("lib")
    library = C.CDLL(str(args.library.resolve()))
    libc = C.CDLL(None)
    libc.malloc.argtypes = [C.c_size_t]; libc.malloc.restype = C.c_void_p
    libc.free.argtypes = [C.c_void_p]
    library.loadu.argtypes = [C.c_void_p, C.c_int32]; library.loadu.restype = C.c_int32
    library.request.argtypes = [C.c_void_p, C.POINTER(C.c_int32)]; library.request.restype = C.c_void_p
    library.unload.restype = C.c_int32
    class Length(C.Structure):
        _fields_ = [("value", C.c_int32), ("guard", C.c_uint32)]
    def owned(data):
        pointer = libc.malloc(max(len(data), 1))
        if not pointer: raise MemoryError()
        C.memmove(pointer, data, len(data)); return pointer
    def send(event):
        data = f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Utatane\r\nSecurityLevel: local\r\nID: {event}\r\n\r\n".encode()
        length = Length(len(data), 0x12345678)
        output = library.request(owned(data), C.cast(C.byref(length), C.POINTER(C.c_int32)))
        assert output and 0 < length.value <= 8 * 1024 * 1024 and length.guard == 0x12345678
        try: return C.string_at(output, length.value).decode("utf-8")
        finally: libc.free(output)
    with tempfile.TemporaryDirectory(prefix=f"{identity} 日本語 ") as temporary:
        root = Path(temporary)
        os.environ["UTATANE_SAORI_ROOT"] = str(root / "shared")
        saori = root / "libsaori_cpuid.dylib"
        if args.saori_library: shutil.copyfile(args.saori_library, saori)
        else:
            fixture = root / "saori.c"
            fixture.write_text(r'''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) { int valid = n > 0 && ((char *)p)[n-1] == '/'; free(p); return valid; }
int32_t unload(void) { return 1; }
void *request(void *p, int32_t *n) {
    const char *text = "SAORI/1.0 200 OK\r\nCharset: Shift_JIS\r\nResult: macOS\r\n\r\n";
    free(p); *n = strlen(text); void *out = malloc(*n); memcpy(out, text, *n); return out;
}
''')
            subprocess.run(["cc", "-arch", platform.machine(), "-dynamiclib", str(fixture), "-o", str(saori)], check=True)
        prepare_dictionary(identity, root)
        previous = Path.cwd(); os.chdir(root)
        try:
            path = str(root).encode()
            assert library.loadu(owned(path), len(path)) == 1
            assert library.loadu(owned(path), len(path)) == 0
            response = send("OnBoot")
            assert "こんにちは" in response and "Charset: UTF-8" in response, response
            response = send("OnSaori")
            assert "macOS" in response, response
            if identity == "satori": assert "設定" in send("OnSet")
            assert library.unload() == 1
            assert (root / ("yaya_variable.cfg" if identity == "yaya" else "satori_savedata.txt")).is_file()
            assert library.loadu(owned(path), len(path)) == 1
            response = send("OnBoot" if identity == "yaya" else "OnRead")
            assert ("count=2" if identity == "yaya" else "保存できた") in response, response
            assert library.unload() == 1
            for invalid in (-1, 8 * 1024 * 1024 + 1):
                length = Length(invalid, 0x12345678)
                assert not library.request(owned(b"x"), C.cast(C.byref(length), C.POINTER(C.c_int32)))
                assert length.value == 0 and length.guard == 0x12345678
            assert not library.request(owned(b"x"), None)
            assert library.loadu(owned(b"\xff"), 1) == 0
        finally: os.chdir(previous)
    print(f"PASS: {identity} UTF-8 dictionary, save/reload, conventional SAORI, guarded 32-bit ABI")


if __name__ == "__main__": main()
