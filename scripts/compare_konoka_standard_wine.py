#!/usr/bin/env python3
"""Compare standard Konoka TEACH, values.dat and builtins using synthetic data."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from conventional_probe import Conventional
from compare_konoka_wine import frame, windows, value

CORPUS = r'''\one,alpha
\two,alpha,beta
@OnImport,%(\_load:=key)
@OnBuiltins,%(\v:=5;\_isval:=v):%(\_get:=v):%(\_wordtype:=alpha):%(\_isval:=one)
@OnReg1,%(\_registword:=one.gamma)
@OnReg2,%(\_registword:=one.gamma)
@OnCount,%(\_countword:=one)
@OnMiddle0,%(\_middle:=a\tb\tc.0)
@OnMiddle2,%(\_middle:=a\tb\tc.2)
@OnTeach & %lastnum=,%word:%hint0\[shortage]
@OnTeach & %lastnum<>,%word:%lasthint:%lastnum\[advice]
'''.replace(r'\t', '\t')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('dll', 'native', 'wine', 'host', 'prefix', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    driver = Conventional(args.native.resolve())
    rows = []
    with tempfile.TemporaryDirectory(prefix='konoka-standard ') as temporary:
        root = Path(temporary)
        original, native = root / 'original', root / 'native'
        for directory in (original, native):
            directory.mkdir()
            (directory / 'konoka.ini').write_bytes(b'ai.txt,e\r\n')
            (directory / 'ai.txt').write_bytes(CORPUS.replace('\n', '\r\n').encode('cp932'))
            (directory / 'values.dat').write_bytes(b'key,7\r\n')
        shutil.copyfile(args.dll, original / 'konoka.dll')
        environment = {**os.environ, 'WINEPREFIX': str(args.prefix.resolve()), 'WINEDEBUG': '-all', 'WINEDLLOVERRIDES': 'mscoree,mshtml='}
        with (root / 'wine.log').open('wb') as log:
            process = subprocess.Popen([str(args.wine.resolve()), windows(args.host.resolve()), windows(original / 'konoka.dll')],
                                       env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
            try:
                assert frame(process) == b''
                assert driver.load(native) == 1
                assert (original / 'ai.xdc').read_bytes() == (native / 'ai.xdc').read_bytes()
                cases = [(event, []) for event in ['OnImport', 'OnBuiltins', 'OnReg1', 'OnReg2', 'OnCount', 'OnMiddle0', 'OnMiddle2']]
                cases += [('OnTeach', refs) for refs in [['apple'], ['apple', 'cat'], ['apple', 'cat', 'dog']]]
                for event, refs in cases:
                    if event == 'OnTeach':
                        wire = ('TEACH SHIORI/2.4\r\nWord: ' + refs[0] + '\r\n'
                                + ''.join(f'Reference{i}: {v}\r\n' for i, v in enumerate(refs[1:])) + '\r\n')
                    else:
                        wire = f'GET Sentence SHIORI/2.5\r\nEvent: {event}\r\n\r\n'
                    data = wire.encode('cp932')
                    process.stdin.write(struct.pack('<I', len(data)) + data)
                    process.stdin.flush()
                    old = frame(process).decode('cp932')
                    new = driver.request(event, charset='Shift_JIS', references=refs)
                    row = {'event': event, 'references': refs, 'original': value(old, 'Sentence'), 'native': value(new, 'Value'),
                           'originalStatus': int(old.split()[1]), 'nativeStatus': int(new.split()[1])}
                    row['equal'] = row['original'] == row['native'] and row['originalStatus'] == row['nativeStatus']
                    rows.append(row)
                assert driver.unload() == 1
                process.stdin.close()
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    print(f"{sum(row['equal'] for row in rows)}/{len(rows)} equal; XDC bytes equal")
    for row in rows:
        if not row['equal']:
            print(row)
    if any(not row['equal'] for row in rows):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
