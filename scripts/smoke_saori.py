#!/usr/bin/env python3
"""Exercise a relocated native SAORI ZIP, including signed 32-bit buffer lengths."""
import argparse
import ctypes as C
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile


def smoke_httpc(send, root):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import threading
    body = "<a>日本語</a>\r\n<a>次</a>".encode()
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(404 if self.path == "/missing" else 200)
            self.send_header("Content-Type", "text/plain; charset=UTF-8")
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args): pass
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/data"
            print("httpc: local text response", flush=True)
            assert "Result: <a>日本語</a><a>次</a>\r\n" in send([url])
            print("httpc: local binary save", flush=True)
            assert "Result: 1\r\n" in send([url, "保存.bin"])
            assert (root / "保存.bin").read_bytes() == body
            print("httpc: HTTP failure preserves file", flush=True)
            assert "Result: 0\r\n" in send([url.replace("/data", "/missing"), "保存.bin"])
            assert (root / "保存.bin").read_bytes() == body
            print("httpc: sequential extraction", flush=True)
            assert "Result: 日本語\r\n" in send([url, "<a>", "</a>"])
            assert "Result: 次\r\n" in send([url, "<a>", "</a>"])
        finally:
            server.shutdown()
            thread.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    args = parser.parse_args()
    if args.library.suffix == ".zip":
        from catalog import ROOT, read_json, safe_extract, verify_package
        with zipfile.ZipFile(args.library) as archive:
            manifests = [n for n in archive.namelist() if n.count("/") == 1 and n.endswith("/module.json")]
            if len(manifests) != 1:
                raise ValueError("Expected exactly one package manifest")
            identity = json.loads(archive.read(manifests[0]))["id"]
        entry = read_json(ROOT / f"catalog/modules/{identity}.json")
        verify_package(args.library, entry)
        with tempfile.TemporaryDirectory(prefix="SAORI ZIP 日本語 ") as temporary:
            root = Path(temporary)
            safe_extract(args.library, root)
            library = root / identity / "lib" / f"lib{identity.replace('-', '_')}.dylib"
            if identity == "proxy-ex":
                helper = root / identity / "bin/mp3tag"
                import wave
                audio = root / "無音.wav"
                with wave.open(str(audio), "wb") as sound:
                    sound.setnchannels(1); sound.setsampwidth(2); sound.setframerate(8000)
                    sound.writeframes(bytes(1600))
                result = subprocess.check_output([str(helper), str(audio)], text=True)
                assert "Milliseconds:100|" in result, result
                # Exercise the complete package layout so the dylib locates bin/.
                subprocess.run([sys.executable, __file__, str(library)], check=True, timeout=30)
            # The same bytes must work beside a Windows DLL, outside the ZIP's layout.
            master = root / "ghost/master/saori"
            master.mkdir(parents=True)
            relocated = master / library.name
            shutil.copyfile(library, relocated)
            subprocess.run([sys.executable, __file__, str(relocated)], check=True, timeout=45 if identity == "httpc" else 30)
        return
    library = C.CDLL(str(args.library.resolve()))
    name = args.library.stem.removeprefix("lib")
    libc = C.CDLL(None)
    libc.malloc.argtypes = [C.c_size_t]
    libc.malloc.restype = C.c_void_p
    libc.free.argtypes = [C.c_void_p]
    library.loadu.argtypes = [C.c_void_p, C.c_int32]
    library.loadu.restype = C.c_int32
    library.load.argtypes = library.loadu.argtypes
    library.load.restype = C.c_int32
    library.request.argtypes = [C.c_void_p, C.POINTER(C.c_int32)]
    library.request.restype = C.c_void_p
    library.unload.argtypes = []
    library.unload.restype = C.c_int32

    class GuardedLength(C.Structure):
        _fields_ = [("value", C.c_int32), ("canary", C.c_uint32)]

    def owned(data):
        pointer = libc.malloc(max(len(data), 1))
        if not pointer:
            raise MemoryError()
        C.memmove(pointer, data, len(data))
        return pointer

    def send(arguments=None, charset="UTF-8", command="EXECUTE SAORI/1.0"):
        encoding = "utf-8" if charset == "UTF-8" else "cp932"
        lines = [command, f"Charset: {charset}"]
        lines += [f"Argument{i}: {arg}" for i, arg in enumerate(arguments or [])]
        data = ("\r\n".join(lines) + "\r\n\r\n").encode(encoding)
        count = GuardedLength(len(data), 0x76543210)
        response = library.request(owned(data), C.cast(C.byref(count), C.POINTER(C.c_int32)))
        assert count.canary == 0x76543210, "request overwrote the 32-bit length"
        assert response and 0 < count.value <= 8 * 1024 * 1024
        try:
            return C.string_at(response, count.value).decode(encoding)
        finally:
            libc.free(response)

    with tempfile.TemporaryDirectory(prefix="SAORI 日本語 ") as temporary:
        root = Path(temporary)
        (root / "keyword.txt").write_bytes("飲み物＝日本酒、酒\r\n場所＝酒場\r\n".encode("cp932"))
        path = str(root).encode()
        assert library.loadu(owned(path), len(path)) == 1
        assert library.loadu(owned(path), len(path)) == 0
        assert send(command="GET Version SAORI/1.0").startswith("SAORI/1.0 200")
        assert send(command="BROKEN SAORI/1.0").startswith("SAORI/1.0 400")
        for charset in ("UTF-8", "Shift_JIS"):
            if name == "saori_cpuid":
                assert "Result: macOS\r\n" in send(["os.name"], charset)
                assert "Result: 0\r\n" not in send(["cpu.num"], charset)
            elif name == "kenonoke":
                response = send(["GETKEYWORD", "酒場で日本酒を飲む"], charset)
                assert "Result: 場所\r\nValue0: 飲み物\r\n" in response, response
            elif name == "wmove":
                assert send(["GET_POSITION", "sakura"], charset).startswith("SAORI/1.0 501")
            elif name == "httpc":
                smoke_httpc(lambda arguments: send(arguments, charset), root)
            elif name == "textcopy2":
                # Do not overwrite the developer's clipboard during a package build.
                assert send([], charset).startswith("SAORI/1.0 204")
            elif name == "proxy_ex":
                helper = root / "echoarg"
                helper.write_text("#!/bin/sh\nprintf '%s\\r\\n' \"$@\"\n")
                helper.chmod(0o755)
                assert send(["/delim", "|"], charset).startswith("SAORI/1.0 204")
                response = send([str(helper), "日本語 [2017]", "$(literal)"], charset)
                assert "Result: 日本語 [2017]|$(literal)|\r\n" in response, response
                packaged = args.library.resolve().parent.parent / "bin/mp3tag"
                if charset == "UTF-8" and packaged.is_file():
                    import wave
                    audio = root / "無音.wav"
                    with wave.open(str(audio), "wb") as sound:
                        sound.setnchannels(1); sound.setsampwidth(2); sound.setframerate(8000)
                        sound.writeframes(bytes(1600))
                    response = send(["mp3tag.exe", str(audio)], charset)
                    assert "Milliseconds:100|" in response, response
            elif name == "mciaudior":
                assert send(["load", "missing.wav"], charset).startswith("SAORI/1.0 204")
                assert send(["stop"], charset).startswith("SAORI/1.0 204")
            else:
                raise ValueError(f"Unknown native SAORI {name}")
        assert library.unload() == 1
        if name == "wmove":
            callback_type = C.CFUNCTYPE(C.c_int32, C.c_int32, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_int32))
            moves = []
            @callback_type
            def windows(operation, scope, x, speed, output):
                if operation == 1:
                    output[0], output[1], output[2], output[3] = 100, 200, 50, 80
                elif operation == 2:
                    output[0], output[1] = 1440, 900
                elif operation == 3:
                    moves.append((scope, x, speed))
                else:
                    return 0
                return 1
            setter = library.utatane_wmove_set_window_callback
            setter.argtypes = [callback_type]
            setter.restype = C.c_int32
            assert setter(windows) == 1
            assert library.load(owned(path), len(path)) == 1
            assert "Result: 100\r\nValue0: 125\r\nValue1: 150\r\n" in send(["GET_POSITION", "kero"])
            assert "Result: 1440\r\nValue0: 900\r\n" in send(["GET_DESKTOP_SIZE"])
            send(["MOVETO", "kero", "30", "-4"])
            assert moves == [(1, 30, 0)], moves
            assert library.unload() == 1
        assert library.load(owned(path), len(path)) == 1
        assert library.unload() == 1
        for invalid in (-1, 0, 8 * 1024 * 1024 + 1):
            count = GuardedLength(invalid, 0x76543210)
            assert not library.request(owned(b"x"), C.cast(C.byref(count), C.POINTER(C.c_int32)))
            assert count.value == 0 and count.canary == 0x76543210
        assert not library.request(owned(b"x"), None)
        assert library.loadu(owned(b"\xff"), 1) == 0
    print(f"PASS: {name} relocated ABI, UTF-8/Shift_JIS, lifecycle, guarded 32-bit lengths")


if __name__ == "__main__":
    main()
