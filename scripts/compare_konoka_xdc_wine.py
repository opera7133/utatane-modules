#!/usr/bin/env python3
"""Verify standard XDC in both directions using synthetic dictionaries.

Supply the locally recovered standard Konoka DLL, Native dictionary tool,
Wine, the existing Windows DLL host and a dedicated Wine prefix.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from compare_konoka_wine import frame, windows, value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('dll', 'tool', 'wine', 'host', 'prefix', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    environment = {**os.environ, 'WINEPREFIX': str(args.prefix.resolve()), 'WINEDEBUG': '-all', 'WINEDLLOVERRIDES': 'mscoree,mshtml='}
    rows = []
    with tempfile.TemporaryDirectory(prefix='konoka xdc ') as temporary:
        root = Path(temporary)
        def original(directory):
            with (directory / 'wine.log').open('ab') as log:
                process = subprocess.Popen([str(args.wine.resolve()), windows(args.host.resolve()), windows(directory / 'konoka.dll')],
                                           env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                try:
                    assert frame(process) == b''
                    wire = b'GET Sentence SHIORI/2.5\r\nSender: Research\r\nEvent: OnBoot\r\n\r\n'
                    process.stdin.write(struct.pack('<I', len(wire)) + wire)
                    process.stdin.flush()
                    assert value(frame(process).decode('cp932'), 'Sentence') == '合成テスト14\\e'
                    process.stdin.close()
                    process.wait(timeout=10)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
        for length in (0, 1, 12, 13, 18, 19, 246, 247, 1024, 4096):
            directory = root / str(length)
            directory.mkdir()
            shutil.copyfile(args.dll, directory / 'konoka.dll')
            (directory / 'konoka.ini').write_bytes(b'ai.txt,e\r\n')
            plain = '@OnBoot,合成テスト%(2+3*4)\r\n'.encode('cp932') + b'#' + b'x' * length + b'\r\n'
            (directory / 'ai.txt').write_bytes(plain)
            original(directory)
            generated = (directory / 'ai.xdc').read_bytes()
            subprocess.run([str(args.tool.resolve()), 'decode', str(directory / 'ai.xdc'), str(directory / 'decoded.txt')], check=True)
            assert (directory / 'decoded.txt').read_bytes() == plain
            subprocess.run([str(args.tool.resolve()), 'encode', str(directory / 'ai.txt'), str(directory / 'native.xdc')], check=True)
            assert (directory / 'native.xdc').read_bytes() == generated
            (directory / 'ai.txt').unlink()
            (directory / 'ai.xdc').write_bytes((directory / 'native.xdc').read_bytes())
            original(directory)
            rows.append({'plainBytes': len(plain), 'cipherBytes': len(generated), 'byteIdentical': True,
                         'nativeDecode': True, 'originalReadsNative': True})
            args.output.write_text(json.dumps(rows, indent=2) + '\n')
            print('PASS XDC ' + str(len(plain)) + ' bytes', flush=True)
    print(f'PASS {len(rows)} XDC vectors, both directions')


if __name__ == '__main__':
    main()
