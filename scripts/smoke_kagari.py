#!/usr/bin/env python3
"""Exercise the relocated kagari ZIP via its real, instance-based C ABI."""

import ctypes
from pathlib import Path
import platform
import sys
import tempfile

from catalog import ROOT, modules, safe_extract, verify_package


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def smoke(archive):
    entry = next(item for item in modules() if item["id"] == "kagari")
    manifest = verify_package(archive, entry)
    check(platform.machine() in manifest["architectures"], "Host architecture missing")
    with tempfile.TemporaryDirectory(prefix="utatane relocated 日本語 ") as temporary:
        root = Path(temporary)
        safe_extract(archive, root)
        library = ctypes.CDLL(str(root / "kagari/lib/libkagari.dylib"))
        libc = ctypes.CDLL(None)
        libc.malloc.argtypes = [ctypes.c_size_t]
        libc.malloc.restype = ctypes.c_void_p
        libc.free.argtypes = [ctypes.c_void_p]
        libc.free.restype = None
        library.kagari_load.argtypes = [ctypes.c_void_p, ctypes.c_long]
        library.kagari_load.restype = ctypes.c_int
        library.kagari_request.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
        library.kagari_request.restype = ctypes.c_void_p
        library.kagari_unload.argtypes = [ctypes.c_int]
        library.kagari_unload.restype = ctypes.c_int

        def owned(data):
            pointer = libc.malloc(max(len(data), 1))
            check(bool(pointer), "Allocation failed")
            ctypes.memmove(pointer, data, len(data))
            return pointer

        def load(path):
            data = (str(path) + "/").encode("utf-8")
            return library.kagari_load(owned(data), len(data))

        def request(identity, event="OnBoot"):
            data = f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: {event}\r\n\r\n".encode()
            length = ctypes.c_long(len(data))
            pointer = library.kagari_request(identity, owned(data), ctypes.byref(length))
            if not pointer:
                check(length.value == 0, "Null response must have zero length")
                return None
            try:
                check(0 <= length.value <= 8 * 1024 * 1024, "Bad response length")
                return ctypes.string_at(pointer, length.value).decode("utf-8")
            finally:
                libc.free(pointer)

        fixture = (ROOT / "tests/fixtures/kagari/index.lua").read_text()
        first, second, invalid = [root / name for name in ("first 日本語", "second", "invalid")]
        for directory in (first, second, invalid):
            directory.mkdir()
            (directory / "index.lua").write_text(fixture if directory != invalid else "return {}")
        a, b = load(first), load(second)
        check(a >= 0 and b >= 0 and a != b, "Distinct instances failed (zero is valid)")
        check("Value: こんにちは1\r\n" in request(a), "First response")
        check("Value: こんにちは2\r\n" in request(a), "First state")
        check("Value: こんにちは1\r\n" in request(b), "Isolated second state")
        check(library.kagari_unload(a) == 1, "Unload first")
        check(request(a) is None, "Closed instance accepted a request")
        check("Value: こんにちは2\r\n" in request(b), "Second survives first closing")
        check(library.kagari_unload(b) == 1, "Unload second")
        check((first / "count.txt").read_text() == "2", "First save")
        check((second / "count.txt").read_text() == "2", "Second save")
        a = load(first)
        check("Value: こんにちは3\r\n" in request(a), "Reload saved state")
        check(request(a, "Break").startswith("SHIORI/3.0 500"), "Lua error contract")
        check(library.kagari_unload(a) == 1, "Final unload")
        check(load(invalid) == -1, "Invalid module accepted")
        check(library.kagari_unload(9999) == -1, "Invalid instance accepted")
    print(f"PASS kagari ABI ({platform.machine()}): relocation, UTF-8, isolation, save/reload, failures")


if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
