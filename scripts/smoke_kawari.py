#!/usr/bin/env python3
"""Exercise a relocated kawari ZIP through a plain C SHIORI host."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def smoke(archive):
    entry = read_json(ROOT / "catalog/modules/kawari.json")
    verify_package(archive, entry)
    with tempfile.TemporaryDirectory(prefix="utatane-kawari-ABI-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root / "relocated 日本語")
        package = root / "relocated 日本語/kawari"
        master = root / "ghost 日本語/master"
        master.mkdir(parents=True)
        (master / "kawari.ini").write_bytes("dict : events.txt\r\n".encode("shift_jis"))
        (master / "events.txt").write_bytes(
            "event.OnBoot : \\0起動\\e\r\nevent.OnMouseDoubleClick : \\0クリック\\e\r\n".encode("shift_jis"))
        executable = root / "host"
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "native/bridge/tests/kawari-conventional.c"), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(package / "lib/libkawari.dylib"), str(master)],
                       check=True, timeout=30)
        modern = root / "ghost UTF-8 😀/master"
        modern.mkdir(parents=True)
        (modern / "kawarirc.kis").write_text(
            "System.Callback.OnGET: ${event.${System.Request.ID}}\n"
            "event.OnBoot: \\0起動\\e$(saoriregist echo.dll echo)$(callsaori echo 日本語😀)\n"
            "event.OnMouseDoubleClick: \\0クリック\\e\n", encoding="utf-8-sig")
        fixture = root / "echo.c"
        fixture.write_text(r'''#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) { free(p); return n > 0; }
int32_t unload(void) { return 1; }
void *request(void *p, int32_t *n) {
    char *in = malloc((size_t)*n + 1); memcpy(in, p, *n); in[*n] = 0; free(p);
    int execute = strstr(in, "EXECUTE ") != NULL;
    int valid = strstr(in, "Argument0: 日本語😀\r\n") != NULL;
    const char *text = !execute ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\n\r\n" :
        valid ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: native-ok\r\n\r\n" :
        "SAORI/1.0 400 Bad Request\r\nCharset: UTF-8\r\n\r\n";
    free(in); *n = (int32_t)strlen(text); void *out = malloc(*n); memcpy(out, text, *n); return out;
}
''')
        subprocess.run(["xcrun", "clang", "-dynamiclib", str(fixture), "-o", str(modern / "echo.dylib")], check=True)
        subprocess.run([str(executable), str(package / "lib/libkawari.dylib"), str(modern)],
                       check=True, timeout=30, env={**os.environ, "KAWARI_EXPECT_NATIVE_SAORI": "1"})



if __name__ == "__main__":
    smoke(Path(sys.argv[1]).resolve())
