#!/usr/bin/env python3
"""Compare the Phase 0.2 dictionary/event subset with a locally supplied DLL.

Phase 0.2 exports destruct instead of unload. Supply a probe host which falls
back to destruct when unload is absent. The DLL itself remains unmodified.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from conventional_probe import Conventional
from compare_konoka_wine import frame, windows, value

CORPUS = r'''word: WORD
chain: ${word}
@local: LOCAL
?OnBoot: \0BOOT:${word}:${0}\e
?OnJapanese: 日本語\e
?OnNested: ${chain}:${0}\e
?OnMissing: ${absent}\e
?OnRef: ${!Reference0}:${!Reference6}\e
?OnLocal: ${@local}\e
sentence: RANDOM\e
'''
EVENTS = ['OnBoot', 'OnJapanese', 'OnNested', 'OnMissing', 'OnRef', 'OnLocal', 'Unknown', 'OnAITalk']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('dll', 'native', 'wine', 'host', 'prefix', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    driver = Conventional(args.native.resolve())
    rows = []
    with tempfile.TemporaryDirectory(prefix='hitomi comparison ') as temporary:
        root = Path(temporary)
        for encrypted in (False, True):
            mode = 'encrypted' if encrypted else 'plain'
            original, native = root / (mode + '-original'), root / (mode + '-native')
            for directory in (original, native):
                directory.mkdir()
                (directory / 'kawari.ini').write_bytes(b'dict: ai.txt\r\n')
                lines = CORPUS.encode('cp932').splitlines()
                if encrypted:
                    lines = [b'!KAWA0000' + base64.b64encode(bytes(b ^ 0xcc for b in line)) for line in lines]
                (directory / 'ai.txt').write_bytes(b'\r\n'.join(lines) + b'\r\n')
            shutil.copyfile(args.dll, original / 'hitomi.dll')
            environment = {**os.environ, 'WINEPREFIX': str(args.prefix.resolve()), 'WINEDEBUG': '-all', 'WINEDLLOVERRIDES': 'mscoree,mshtml='}
            with (root / (mode + '.log')).open('wb') as log:
                process = subprocess.Popen([str(args.wine.resolve()), windows(args.host.resolve()), windows(original / 'hitomi.dll')],
                                           env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                try:
                    assert frame(process) == b''
                    assert driver.load(native) == 1
                    for event in EVENTS:
                        print('Comparing ' + mode + '/' + event, flush=True)
                        version = '2.0' if event == 'OnAITalk' else '2.2'
                        wire = (f'GET Sentence SHIORI/{version}\r\nSender: Research\r\nEvent: {event}\r\n'
                                + ''.join(f'Reference{i}: {i}\r\n' for i in range(7)) + '\r\n').encode('cp932')
                        process.stdin.write(struct.pack('<I', len(wire)) + wire)
                        process.stdin.flush()
                        old = value(frame(process).decode('cp932'), 'Sentence')
                        new = value(driver.request(event, charset='Shift_JIS', references=[str(i) for i in range(7)]), 'Value')
                        rows.append({'mode': mode, 'event': event, 'original': old, 'native': new, 'equal': old == new})
                        args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
                    assert driver.unload() == 1
                    process.stdin.close()
                    process.wait(timeout=10)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
    print(f"{sum(row['equal'] for row in rows)}/{len(rows)} equal; {args.output}")
    if not all(row['equal'] for row in rows):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
