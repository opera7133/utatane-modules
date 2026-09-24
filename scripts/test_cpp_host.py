#!/usr/bin/env python3
"""Run distributed YAYA/SATORI and SAORI ZIPs through Utatane's actual helper."""
import argparse
from contextlib import ExitStack
import os
from pathlib import Path
import select
import shutil
import struct
import subprocess
import tempfile
import time

from catalog import ROOT, read_json, safe_extract, verify_package
from smoke_cpp import prepare_dictionary


class Host:
    def __init__(self, helper, library, directory, shared, window_callback=None):
        self.window_callback = window_callback
        self.process = subprocess.Popen([str(helper), str(library), str(directory)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env={**os.environ, "UTATANE_SAORI_ROOT": str(shared)})
        try:
            assert self.receive() == b""
        except BaseException:
            self.abort()
            raise

    def exact(self, count, deadline):
        data = bytearray()
        while len(data) < count:
            ready, _, _ = select.select([self.process.stdout], [], [], max(0, deadline - time.monotonic()))
            if not ready: raise TimeoutError("SHIORI helper did not respond")
            chunk = os.read(self.process.stdout.fileno(), count - len(data))
            if not chunk: raise ValueError(f"SHIORI helper closed its pipe ({self.process.poll()})")
            data.extend(chunk)
        return bytes(data)

    def receive(self):
        deadline = time.monotonic() + 15
        for _ in range(1025):
            size, = struct.unpack("<I", self.exact(4, deadline))
            if not 1 <= size <= 8 * 1024 * 1024 + 1: raise ValueError("Invalid frame size")
            response = self.exact(size, deadline)
            if response[0] == 6:
                if len(response) != 17 or self.window_callback is None: raise ValueError("Unexpected window callback")
                arguments = struct.unpack("<4i", response[1:])
                values = self.window_callback(*arguments)
                if len(values) != 5: raise ValueError("Invalid window reply")
                payload = struct.pack("<5i", *values)
                self.process.stdin.write(struct.pack("<IB", len(payload) + 1, 3) + payload)
                self.process.stdin.flush()
                continue
            if response[0]: raise ValueError(f"Helper failure {response[0]}: {response[1:]!r}")
            return response[1:]
        raise ValueError("Too many window callbacks")

    def exchange(self, command, data=b""):
        self.process.stdin.write(struct.pack("<IB", len(data) + 1, command) + data)
        self.process.stdin.flush()
        return self.receive()

    def send(self, event):
        return self.exchange(1, f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: {event}\r\n\r\n".encode()).decode()

    def close(self):
        if self.process.poll() is None:
            assert self.exchange(2) == b""
        assert self.process.wait(timeout=5) == 0
        self.process.stdin.close(); self.process.stdout.close()

    def abort(self):
        if self.process.poll() is None: self.process.kill()
        self.process.wait(timeout=5)
        self.process.stdin.close(); self.process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--yaya", type=Path, required=True)
    parser.add_argument("--satori", type=Path, required=True)
    parser.add_argument("--saori", type=Path, required=True)
    parser.add_argument("--keyword", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="Utatane C++ 配布 ") as temporary:
        root = Path(temporary)
        for identity, archive in [("yaya", args.yaya), ("satori", args.satori), ("saori-cpuid", args.saori), ("kenonoke", args.keyword)]:
            verify_package(archive, read_json(ROOT / f"catalog/modules/{identity}.json"))
            safe_extract(archive, root / "packages")
        cpuid = root / "packages/saori-cpuid/lib/libsaori_cpuid.dylib"
        keyword = root / "packages/kenonoke/lib/libkenonoke.dylib"
        keyword_shared = root / "shared/kenonoke/lib"
        keyword_shared.mkdir(parents=True)
        shutil.copyfile(keyword, keyword_shared / keyword.name)
        shared = root / "shared/saori-cpuid/lib"
        shared.mkdir(parents=True)
        shutil.copyfile(cpuid, shared / cpuid.name)
        for identity in ("yaya", "satori"):
            library = root / f"packages/{identity}/lib/lib{identity}.dylib"
            directories = []
            with ExitStack() as stack:
                hosts = []
                for index in range(2):
                    directory = root / f"{identity} 日本語 {index}"; directory.mkdir()
                    prepare_dictionary(identity, directory); directories.append(directory)
                    image = library
                    if index == 1:
                        # One ghost bundles both libraries; the other uses the shared copies.
                        image = directory / library.name
                        shutil.copyfile(library, image)
                        shutil.copyfile(cpuid, directory / cpuid.name)
                        shutil.copyfile(keyword, directory / keyword.name)
                    host = Host(args.host.resolve(), image, directory, root / "shared")
                    stack.callback(host.abort); hosts.append(host)
                for host in hosts:
                    assert "こんにちは" in host.send("OnBoot")
                    assert "macOS" in host.send("OnSaori")
                    response = host.send("OnKeyword")
                    assert "場所" in response, response
                if identity == "yaya":
                    assert "count=2" in hosts[0].send("OnBoot")
                    assert "count=2" in hosts[1].send("OnBoot")
                else:
                    assert "設定" in hosts[0].send("OnSet")
                    assert "保存できた" not in hosts[1].send("OnRead")
                for host in hosts: host.close()
            with ExitStack() as stack:
                host = Host(args.host.resolve(), library, directories[0], root / "shared")
                stack.callback(host.abort)
                response = host.send("OnBoot" if identity == "yaya" else "OnRead")
                assert ("count=3" if identity == "yaya" else "保存できた") in response, response
                host.close()
            print(f"PASS: Utatane helper + {identity}: shared/bundled libraries, two ghosts, native SAORI, save/reload")


if __name__ == "__main__": main()
