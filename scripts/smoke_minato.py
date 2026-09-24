#!/usr/bin/env python3
"""Exercise the macOS minato SHIORI ABI and a native SAORI in an isolated fixture."""
import argparse
import ctypes as C
from pathlib import Path
import subprocess
import platform
import tempfile
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    args = parser.parse_args()
    if args.library.suffix == ".zip":
        from catalog import ROOT, read_json, safe_extract, verify_package
        verify_package(args.library, read_json(ROOT / "catalog/modules/minato.json"))
        with tempfile.TemporaryDirectory(prefix="minato ZIP 日本語 ") as temporary:
            root = Path(temporary)
            safe_extract(args.library, root)
            subprocess.run([sys.executable, __file__, str(root / "minato/lib/libminato.dylib")], check=True, timeout=45)
        return
    library = C.CDLL(str(args.library.resolve()))
    libc = C.CDLL(None)
    libc.malloc.argtypes = [C.c_size_t]
    libc.malloc.restype = C.c_void_p
    libc.free.argtypes = [C.c_void_p]
    library.loadu.argtypes = [C.c_void_p, C.c_int32]
    library.loadu.restype = C.c_int32
    library.request.argtypes = [C.c_void_p, C.POINTER(C.c_int32)]
    library.request.restype = C.c_void_p
    library.unload.restype = C.c_int32

    def owned(data):
        pointer = libc.malloc(max(len(data), 1))
        if not pointer:
            raise MemoryError()
        C.memmove(pointer, data, len(data))
        return pointer

    def send(event):
        data = f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: {event}\r\n\r\n".encode()
        length = C.c_int32(len(data))
        response = library.request(owned(data), C.byref(length))
        assert response and 0 < length.value <= 8 * 1024 * 1024
        try:
            return C.string_at(response, length.value).decode("utf-8")
        finally:
            libc.free(response)

    with tempfile.TemporaryDirectory(prefix="minato 日本語 ") as temporary:
        root = Path(temporary)
        (root / "talks").mkdir()
        (root / "config.toml").write_text('[characters]\n"湊" = "\\\\0"\n')
        (root / "talks/main.mnt").write_text(
            "OnBoot => {\n    湊: こんにちは\n}\n"
            "OnSaori => {\n    湊: ${saori('echo.dll', '日本語')[0]}\n}\n"
        )
        # This fixture verifies UTF-8 paths and arguments as well as transferred buffers.
        source = root / "echo.c"
        source.write_text(r'''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) {
    int ok = n > 0 && ((char *)p)[n-1] == '/'; free(p); return ok;
}
int32_t unload(void) { return 1; }
void *request(void *p, int32_t *n) {
    char *input = malloc((size_t)*n + 1);
    memcpy(input, p, *n); input[*n] = 0; free(p);
    const char *ok = strstr(input, "Argument0: 日本語\r\n");
    const char *text = ok ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: 応答成功\r\n\r\n" : "SAORI/1.0 400 Bad Request\r\n\r\n";
    free(input); *n = (int32_t)strlen(text);
    void *out = malloc(*n); memcpy(out, text, *n); return out;
}
''')
        subprocess.run(["cc", "-arch", platform.machine(), "-dynamiclib", str(source), "-o", str(root / "echo.dylib")], check=True)
        path = str(root).encode()
        assert library.loadu(owned(path), len(path)) == 1
        assert library.loadu(owned(path), len(path)) == 0, "A second load must not overwrite an active ghost"
        response = send("OnBoot")
        assert "Charset: UTF-8\r\n" in response and "こんにちは" in response, response
        response = send("OnSaori")
        assert "応答成功" in response, response
        assert library.unload() == 1
        assert (root / "save.json").is_file()
        assert library.loadu(owned(path), len(path)) == 1
        assert "こんにちは" in send("OnBoot")
        assert library.unload() == 1
        for length in (-1, 8 * 1024 * 1024 + 1):
            size = C.c_int32(length)
            assert not library.request(owned(b"x"), C.byref(size))
            assert size.value == 0
        assert not library.request(owned(b"x"), None)
        assert library.loadu(owned(b"\xff"), 1) == 0
    print("PASS: minato UTF-8 ABI, native SAORI, unload/reload, duplicate-load guard and invalid inputs")


if __name__ == "__main__":
    main()
