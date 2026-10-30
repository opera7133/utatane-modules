#!/usr/bin/env python3
"""Compare a local original mae DLL with a native package; never alter the input ghost.

Requires Wine and the framed helper built by Utatane's build-windows-dll-host.sh.
Original assets are copied to a temporary directory, never added to fixtures/packages.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import struct
import subprocess
import tempfile
import time
from conventional_probe import Conventional, relocated

CORPUS = r'''[MAE CORPUS/2.0]
#Declaration:
var count, result, message, array[3], nyear, nmonth, nday, nhour, nminute, nsecond;
:end
#Initialize:
count = count + 1;
:end
#OnBoot
count=${count}
#OnSequence
one
two
#OnMath:
result = sprint(2+3*4, ":", 7/2);
:end
${result}
#OnOperands:
array[0] = 2+3*4;
array[1] = 7/2;
result = sprint(array[0], ":", array[1]);
:end
${result}
#OnWrite:
array[0] = -123;
array[1] = "日本語,末尾";
array[2] = "a,\"quote\"\\tail\nline";
setnews("probe", "最初,one", 0);
setnews("probe", "最新,two", 0);
:end
written
#OnRead:
getnews("probe", 0, message);
:end
${message}
#OnOld:
getnews("probe", 1, message);
:end
${message}
#OnDate:
getnewsdate("probe", 0, nyear, nmonth, nday, nhour, nminute, nsecond);
:end
${nyear}:${nmonth}:${nday}:${nhour}:${nminute}:${nsecond}
#OnDelete:
result = deletenews("probe", 0, 1);
:end
${result}
#OnMissing:
result = "unchanged";
getnews("missing", 0, result);
:end
${result}
#OnMood:
setsenti(-15);
:end
${emotion}
#OnAlias
${renamedhour}
#OnSaved:
result = array[0];
:end
${count}:${result}
#Finalize:
count = count + 10;
:end
'''


DERIVED_CASES = [
    ('OnSecondChange', ['0', '0', '0', '1']),
    ('OnSecondChange', ['0', '1', '0', '1']),
    ('OnSecondChange', ['0', '1', '0', '1']),
    ('OnSecondChange', ['0', '1', '0', '1']),
    ('OnSecondChange', ['0', '0', '0', '1']),
    ('OnSecondChange', ['0', '0', '1', '1']),
    ('OnSecondChange', ['0', '0', '1', '1']),
    ('OnSecondChange', ['0', '0', '0', '1']),
    ('OnMouseMove', ['0', '0', '0', '0', 'head']),
    ('OnMouseMove', ['3', '0', '0', '0', 'head']),
    ('OnMouseMove', ['6', '0', '0', '0', 'head']),
    ('OnCommunicate', ['user', 'hello']),
    ('OnSurfaceRestore', ['0', '0']),
    ('OnBIFFComplete', ['2']),
]
DERIVED_TAGS = ['Mae.MikireBegin', 'Mae.MikireEnd', 'Mae.Mikire',
                'Mae.KasanariBegin', 'Mae.KasanariEnd', 'Mae.Kasanari',
                'Mae.SawariSakura.head', 'Mae.SawariSakura',
                'Mae.ResponseAgainst', 'Mae.ResponseFollow', 'OnCommunicate',
                'Mae.OnSurfaceRestoreSakura.0', 'OnSurfaceRestore',
                'OnBIFFComplete', 'OnBIFFComplete.2']
CORPUS += ''.join('\n#' + tag + '\n' + tag + '\n' for tag in DERIVED_TAGS)


def value(wire):
    return next((line[7:] for line in wire.split('\r\n') if line.startswith('Value: ')), None)


def windows(path):
    return 'Z:' + str(Path(path).resolve()).replace('/', '\\')


class Original:
    def __init__(self, args, master, prefix, log):
        environment = {**os.environ, 'WINEPREFIX': str(prefix), 'WINEDEBUG': '-all',
                       'WINEDLLOVERRIDES': 'mscoree,mshtml='}
        self.process = subprocess.Popen([str(args.wine), windows(args.host), windows(master / 'shiori.dll')],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, env=environment)
        try:
            assert self.receive() == b'', 'Original DLL did not load'
        except BaseException:
            self.abort()
            raise

    def receive(self):
        def exact(length):
            output = b''; end = time.monotonic() + 45
            while len(output) < length:
                if not select.select([self.process.stdout], [], [], max(0, end - time.monotonic()))[0]:
                    raise TimeoutError('Original mae did not respond within 45 seconds')
                part = os.read(self.process.stdout.fileno(), length - len(output))
                if not part:
                    raise RuntimeError('Original mae helper closed unexpectedly')
                output += part
            return output
        length, = struct.unpack('<I', exact(4))
        assert length <= 8 * 1024 * 1024
        return exact(length)

    def request(self, event, references=()):
        headers = "".join(f"Reference{i}: {item}\r\n" for i, item in enumerate(references))
        data = f'GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: {event}\r\n{headers}\r\n'.encode('cp932')
        self.process.stdin.write(struct.pack('<I', len(data)) + data); self.process.stdin.flush()
        return self.receive().decode('cp932')

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0

    def abort(self):
        if self.process.poll() is None:
            self.process.kill(); self.process.wait()


@contextmanager
def original(args, master, prefix, log):
    driver = Original(args, master, prefix, log)
    try:
        yield driver
        driver.close()
    finally:
        driver.abort()


def run(args):
    report = {'packageSHA256': hashlib.sha256(args.native.read_bytes()).hexdigest(), 'comparisons': []}
    with tempfile.TemporaryDirectory(prefix='mae wine regression ') as temporary, relocated('mae', args.native) as library:
        root = Path(temporary); master = root / 'original'; native_root = root / 'native'
        # Follow no symlinks to avoid accidentally modifying user content.
        shutil.copytree(args.original, master, symlinks=True)
        for path in master.rglob('*'):
            if path.is_symlink():
                raise ValueError('Original test directory must not contain symlinks')
        for name in ('mae_variable.txt', 'mae_news.txt', 'mae-native-state.json', 'mae.ini'):
            (master / name).unlink(missing_ok=True)
        (master / 'mae_corpus.txt').write_bytes(CORPUS.encode('cp932'))
        system = ['year', 'month', 'day', 'renamedhour', 'minute', 'second', 'dayofweek', 'username', 'emotion', 'reference[8]']
        (master / 'mae_systemvar.txt').write_bytes(('\n'.join('var ' + name + ';' for name in system) + '\nend\n').encode('cp932'))
        defaults = {'LOG': 0, 'SHIORI': '3.0', 'TALK_INTERVAL': 0, 'TALK_INTERVAL_DETAIL': 0,
                    'TALK_INTERVAL_ADDITION': 30, 'MIKIRE': 2, 'KASANARI': 2, 'SAWARI': 2,
                    'SECUTIRY_LEVEL': 8, 'MAX_SENTI': 100, 'UNDEFINED_WORD': 'アレ'}
        for level in range(1, 6):
            defaults[f'P{level}_SENTI_THRESHOLD'] = [10, 30, 50, 70, 90][level - 1]
            defaults[f'M{level}_SENTI_THRESHOLD'] = [-10, -20, -40, -60, -80][level - 1]
            defaults[f'P{level}_SENTI_ADJUSTMENT'] = 0 if level <= 2 else -3
            defaults[f'M{level}_SENTI_ADJUSTMENT'] = 0 if level <= 2 else 3
        for slot, (begin, end) in enumerate([(-1, -1), (4, 7), (8, 10), (11, 16), (17, 19), (20, 22), (23, 1), (-1, -1), (-1, -1), (-1, -1)]):
            defaults[f'BEGIN_SLOT{slot}'] = begin; defaults[f'END_SLOT{slot}'] = end
        (master / 'mae.ini').write_bytes(''.join(f'{key}={item}\n' for key, item in defaults.items()).encode('cp932'))
        shutil.copytree(master, native_root)
        driver = Conventional(library); assert driver.load(native_root) == 1
        prefix = args.prefix.resolve()
        assert prefix.name != '.wine', 'Use a dedicated test prefix, not the user prefix'
        def compare(event, expected_difference=False, references=()):
            left = value(oracle.request(event, references)); right = value(driver.request(event, charset='Shift_JIS', references=references))
            row = {'event': event, 'original': left, 'native': right, 'equal': left == right, 'references': references}
            report['comparisons'].append(row)
            if expected_difference:
                assert left == "0" and right == "14:3", row
            else:
                assert left == right, row
            print(json.dumps(row, ensure_ascii=False), flush=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.with_suffix('.wine.log').open('wb') as log:
            try:
                with original(args, master, prefix, log) as oracle:
                    for event in ['OnBoot', 'OnSequence', 'OnSequence', 'OnSequence']:
                        compare(event)
                    compare('OnOperands', expected_difference=True)
                    compare('OnMath', expected_difference=True)
                    compare('OnMood')
                    for event in ['OnWrite', 'OnRead', 'OnOld', 'OnAlias', 'OnSaved']:
                        compare(event)
                    for event, references in DERIVED_CASES:
                        compare(event, references=references)
                    # Record the original date exactly. It must survive FILETIME import.
                    report['originalNewsDate'] = value(oracle.request('OnDate'))
                assert driver.unload() == 1
                legacy = {name: (master / name).read_bytes() for name in ('mae_variable.txt', 'mae_news.txt')}
                (native_root / 'mae-native-state.json').unlink()
                for name, data in legacy.items():
                    (native_root / name).write_bytes(data)
                assert driver.load(native_root) == 1
                report['importedNewsDate'] = value(driver.request('OnDate', charset='Shift_JIS'))
                print(json.dumps({'dates': report['originalNewsDate'], 'imported': report['importedNewsDate']}), flush=True)
                assert report['importedNewsDate'] == report['originalNewsDate']
                with original(args, master, prefix, log) as oracle:
                    for event in ['OnBoot', 'OnSaved', 'OnRead', 'OnOld', 'OnDelete', 'OnRead']:
                        compare(event)
                assert driver.unload() == 1
                state = json.loads((native_root / 'mae-native-state.json').read_text())
                imported = state['variables']
                # Original type=1 strings contain escaped commas, quotes, backslashes and newlines.
                assert imported['array']['array']['_0'][2] == {'string': {'_0': 'a,"quote"\\tail\nline'}}
                for name, data in legacy.items():
                    assert (native_root / name).read_bytes() == data
                report['originalSaveImported'] = True
                report['originalFilesPreserved'] = True
            finally:
                driver.unload()
                subprocess.run([str(args.wine.with_name('wineserver')), '-k'],
                               env={**os.environ, 'WINEPREFIX': str(prefix)}, timeout=15, check=False)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS original save/News import, dates, reload, and derived event comparison', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', type=Path, required=True, help='Local original ghost/master, including supporting dictionaries')
    parser.add_argument('--wine', type=Path, required=True)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--prefix', type=Path, required=True, help='Dedicated Wine prefix (not ~/.wine)')
    parser.add_argument('--native', type=Path, required=True, help='Native ZIP or dylib')
    parser.add_argument('--output', type=Path, required=True)
    run(parser.parse_args())
