#!/usr/bin/env python3
"""Compare a local Konoka DLL with Native using a synthetic, temporary dictionary.

The DLL and DLL host are supplied by the developer; neither is distributed here.
Uses an explicitly supplied Wine prefix and leaves the original ghost untouched.
"""
import argparse
import json
import os
from pathlib import Path
import select
import shutil
import struct
import subprocess
import tempfile
import time
from conventional_probe import Conventional

CORPUS = r'''\word,hello
@OnPlain,PLAIN
@OnJapanese,日本語
@OnMath,%(2+3*4)
@OnDivide,%(1/0)
@OnEcho,%word:%word
@OnRef,%ref0:%ref1
@OnRedirect,@OnPlain
@OnInline,%(@OnPlain)
@OnSave,%(\_save:=counter.7)
@OnRestore,%(\_load:=counter)
@OnTernary,%(0?(\a:=1):(\b:=2));%a:%b
@OnLength,%(\_length:=abc)
@OnUpper,%(\_upcase:=abc)
@OnLower,%(\_locase:=ABC)
@OnInstr,%(\_instr:=abc.b)
@OnSubstr,%(\_substr:=abc.2.1)
@OnReplace,%(\_replace:=abc.b.X)
@OnEmpty,%(\_load:=absent)
'''
EVENTS = ['OnPlain', 'OnJapanese', 'OnMath', 'OnDivide', 'OnEcho', 'OnRef',
          'OnRedirect', 'OnInline', 'OnSave', 'OnRestore', 'OnTernary', 'OnLength',
          'OnUpper', 'OnLower', 'OnInstr', 'OnSubstr', 'OnReplace', 'OnEmpty', 'Unknown']


def read_exact(process, length):
    result = b''
    deadline = time.monotonic() + 35
    while len(result) < length:
        if not select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))[0]:
            raise TimeoutError('Wine response timeout')
        chunk = os.read(process.stdout.fileno(), length - len(result))
        if not chunk:
            raise RuntimeError('DLL host exited')
        result += chunk
    return result


def frame(process):
    length, = struct.unpack('<I', read_exact(process, 4))
    if length > 2 * 1024 * 1024:
        raise ValueError('Oversized frame')
    return read_exact(process, length)


def value(response, key):
    return next((line[len(key) + 2:] for line in response.split('\r\n') if line.startswith(key + ': ')), None)


def windows(path):
    return 'Z:' + str(path).replace('/', '\\')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('dll', 'native', 'wine', 'host', 'prefix', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    driver = Conventional(args.native.resolve())
    with tempfile.TemporaryDirectory(prefix='konoka comparison ') as temporary:
        root = Path(temporary)
        original, native = root / 'original', root / 'native'
        for directory in (original, native):
            directory.mkdir()
            (directory / 'konoka.ini').write_text('ai.txt,e\r\n')
            (directory / (args.dll.stem + '.ini')).write_text('ai.txt,e\r\n')
            (directory / 'ai.txt').write_bytes(CORPUS.replace('\n', '\r\n').encode('cp932'))
        shutil.copyfile(args.dll, original / args.dll.name)
        environment = {**os.environ, 'WINEPREFIX': str(args.prefix.resolve()), 'WINEDEBUG': '-all',
                       'WINEDLLOVERRIDES': 'mscoree,mshtml='}
        with (root / 'wine.log').open('wb') as log:
            process = subprocess.Popen([str(args.wine.resolve()), windows(args.host.resolve()), windows(original / args.dll.name)],
                                       env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
            try:
                assert frame(process) == b''
                assert driver.load(native) == 1
                rows = []
                for event in EVENTS:
                    print('Comparing ' + event, flush=True)
                    wire = (f'GET Sentence SHIORI/2.5\r\nSender: Research\r\nEvent: {event}\r\n'
                            'Reference0: 5\r\nReference1: 9\r\n\r\n').encode('cp932')
                    process.stdin.write(struct.pack('<I', len(wire)) + wire)
                    process.stdin.flush()
                    old = value(frame(process).decode('cp932'), 'Sentence')
                    new = value(driver.request(event, charset='Shift_JIS', references=['5', '9']), 'Value')
                    rows.append({'event': event, 'original': old, 'native': new, 'equal': old == new})
                    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
                assert rows[0]['original'] == 'PLAIN\\e', 'Original DLL did not read the synthetic dictionary'
                driver.unload()
                process.stdin.close()
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
            print(f"{sum(row['equal'] for row in rows)}/{len(rows)} equal; {args.output}")
            for row in rows:
                if not row['equal']:
                    print(row)


if __name__ == '__main__':
    main()
