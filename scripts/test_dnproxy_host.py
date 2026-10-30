#!/usr/bin/env python3
"""Run a portable C# ghost through the managed D.N.Proxy compatibility host."""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]


def write_packet(stream, data):
    stream.write(struct.pack('<i', len(data)) + data)
    stream.flush()


def read_packet(stream):
    header = stream.read(4)
    assert len(header) == 4, 'Host exited before a response'
    size, = struct.unpack('<i', header)
    assert 0 <= size <= 8 * 1024 * 1024
    data = stream.read(size)
    assert len(data) == size
    return data


def session(dotnet, host, root, expected):
    # Subprocess timeout is enforced by a separate controller below.
    with (root / 'host.log').open('ab') as log:
        process = subprocess.Popen([dotnet, str(host), str(root)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=log,
                                   env={**os.environ, 'UTATANE_DOTNET': dotnet})
        watchdog = threading.Timer(150, process.kill)
        watchdog.start()
        try:
            assert read_packet(process.stdout) == b'\x01'
            write_packet(process.stdin, b'GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n')
            result = read_packet(process.stdout).decode('utf-8')
            assert f'日本語😀 count={expected}' in result, result
            write_packet(process.stdin, b'')
            assert read_packet(process.stdout) == b'\x01'
            assert process.wait(timeout=10) == 0
        finally:
            watchdog.cancel()
            if process.poll() is None:
                process.kill()
                process.wait()


def run(dotnet):
    host = ROOT / 'managed/DnProxyHost/bin/Release/net10.0/DnProxyHost.dll'
    subprocess.run([dotnet, 'build', str(ROOT / 'managed/DnProxyHost'), '-c', 'Release',
                    '--nologo', '--ignore-failed-sources'], check=True, timeout=120)
    with tempfile.TemporaryDirectory(prefix='dnproxy 日本語 ') as temporary:
        root = Path(temporary)
        shutil.copyfile(ROOT / 'tests/fixtures/dnproxy/Portable.cs', root / 'Portable.cs')
        (root / 'dnproxy.dll.config').write_text('''<configuration><applicationSettings><D.N.Properties.Settings>
<setting name="AssemblyName"><value>user.dll</value></setting>
<setting name="MainClass"><value>Portable.Ghost</value></setting>
<setting name="Protocol"><value>SHIORI/3.0</value></setting>
</D.N.Properties.Settings></applicationSettings></configuration>''')
        (root / 'dnproxy.ini').write_text('Language: C#\nSourceFiles: Portable.cs\nMainClass: Portable.Ghost\n')
        session(dotnet, host, root, 1)
        session(dotnet, host, root, 2)
        assert not (root / 'user.dll').exists(), 'Original Windows assembly must not be overwritten'
        assert b'ghost log' in (root / 'host.log').read_bytes()
        # Precompiled portable assembly, without runtime compilation.
        (root / 'dnproxy.ini').unlink()
        shutil.copyfile(root / 'profile/dnproxy-macos/user.dll', root / 'user.dll')
        session(dotnet, host, root, 3)
        # Unsupported Windows options fail before source execution.
        (root / 'dnproxy.ini').write_text('Language: JScript\nSourceFiles: Portable.cs\n')
        failed = subprocess.run([dotnet, str(host), str(root)], capture_output=True, timeout=20)
        assert failed.returncode != 0 and b'Only portable C#' in failed.stderr
    print('PASS DNProxy: C# compile, managed interfaces, UTF-8, save/reload, precompiled DLL, isolated logging, rejected unsupported language')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dotnet', default='dotnet')
    args = parser.parse_args()
    run(args.dotnet)
