#!/usr/bin/env python3
"""Exercise a pasta dylib or verified ZIP through its conventional macOS ABI."""
import ctypes
from pathlib import Path
import subprocess
import sys
import tempfile

COUNTER_LUA = r'''
local save = require "pasta.save"
SHIORI = {}
function SHIORI.load(_, directory) return true end
function SHIORI.request(req)
    if req.id == "OnNotify" then
        save.count = (save.count or 0) + 1
        return "SHIORI/3.0 204 No Content\r\n\r\n"
    end
    local value
    if req.id == "OnEcho" then value = req.reference[0]
    else
        save.count = (save.count or 0) + 1
        value = "count=" .. save.count
    end
    return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: " .. value .. "\r\n\r\n"
end
function SHIORI.unload() end
return SHIORI
'''


def fixture(root, counter=True):
    root.mkdir(parents=True, exist_ok=True)
    (root / "pasta.toml").write_text('[actor."テスト"]\nspot = 0\n[persistence]\nobfuscate = false\n', encoding="utf-8")
    (root / "dic").mkdir()
    (root / "dic/main.pasta").write_text('＊OnBoot\n　テスト：こんにちは😀\n', encoding="utf-8")
    if counter:
        entry = root / "scripts/pasta/shiori/entry.lua"
        entry.parent.mkdir(parents=True)
        entry.write_text(COUNTER_LUA, encoding="utf-8")


def smoke(library):
    import _ctypes
    lib = ctypes.CDLL(str(library))
    libc = ctypes.CDLL(None)
    libc.malloc.argtypes = [ctypes.c_size_t]
    libc.malloc.restype = ctypes.c_void_p
    libc.free.argtypes = [ctypes.c_void_p]
    for name in ("load", "loadu"):
        getattr(lib, name).argtypes = [ctypes.c_void_p, ctypes.c_int32]
        getattr(lib, name).restype = ctypes.c_int32
    lib.unload.restype = ctypes.c_int32
    lib.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int32)]
    lib.request.restype = ctypes.c_void_p

    def owned(data):
        p = libc.malloc(max(len(data), 1))
        assert p
        ctypes.memmove(p, data, len(data))
        return p

    def request(data):
        n = ctypes.c_int32(len(data))
        p = lib.request(owned(data), ctypes.byref(n))
        if not p:
            assert n.value == 0
            return None
        try:
            assert 0 < n.value <= 8 * 1024 * 1024
            return ctypes.string_at(p, n.value).decode("utf-8")
        finally:
            libc.free(p)

    boot = b"GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
    assert request(boot) is None
    assert lib.loadu(None, 1) == 0
    for data, length in [(b"a", -1), (b"a", 0), (b"a", 8 * 1024 * 1024 + 1), (b"\xff", 1), (b"relative", 8)]:
        assert lib.loadu(owned(data), length) == 0
    with tempfile.TemporaryDirectory(prefix="pasta 日本語 ") as temporary:
        root = Path(temporary)
        master = root / "ghost/master"
        fixture(master)
        directory = str(master).encode("utf-8")
        assert lib.loadu(owned(directory), len(directory)) == 1
        assert lib.load(owned(directory), len(directory)) == 0
        assert "Value: count=1\r\n" in request(boot)
        notify = b"NOTIFY SHIORI/3.0\r\nID: OnNotify\r\n\r\n"
        assert request(notify).startswith("SHIORI/3.0 204")
        assert "Value: count=3\r\n" in request(boot)
        echo = "GET SHIORI/3.0\r\nID: OnEcho\r\nReference0: 日本語😀\r\n\r\n".encode()
        assert "Value: 日本語😀\r\n" in request(echo)
        assert request(b"\xff") is None
        n = ctypes.c_int32(-1)
        assert not lib.request(owned(b"a"), ctypes.byref(n)) and n.value == 0
        assert not lib.request(owned(b"a"), None)
        assert lib.unload() == 1
        assert (master / "profile/pasta/save/save.json").is_file()
        assert lib.load(owned(directory), len(directory)) == 1
        assert "Value: count=4\r\n" in request(boot)
        assert lib.unload() == 1
        assert lib.unload() == 1
        assert request(boot) is None
        dsl = root / "DSL 日本語"
        fixture(dsl, counter=False)
        directory = str(dsl).encode()
        assert lib.loadu(owned(directory), len(directory)) == 1
        response = request(boot)
        assert "こんにちは😀" in response, response
        assert lib.unload() == 1
    _ctypes.dlclose(lib._handle)
    print("PASS pasta ABI: UTF-8, DSL, NOTIFY ordering, duplicate load, save/reload, invalid inputs, dlclose")


if __name__ == "__main__":
    path = Path(sys.argv[1]).resolve()
    if path.suffix == ".zip":
        from catalog import ROOT, read_json, safe_extract, verify_package
        verify_package(path, read_json(ROOT / "catalog/modules/pasta.json"))
        with tempfile.TemporaryDirectory(prefix="pasta-package-") as temporary:
            root = Path(temporary)
            safe_extract(path, root)
            subprocess.run([sys.executable, __file__, str(root / "pasta/lib/libpasta.dylib")], check=True, timeout=60)
    else:
        smoke(path)
