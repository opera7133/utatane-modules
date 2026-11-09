#!/usr/bin/env python3
"""Compare documented 0.4.6 behavior using synthetic dictionaries and a local DLL.

--host must support both normal and underscore-prefixed PSY exports. The
original DLLs are copied into a temporary directory and remain unmodified.
"""
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

CORPUS = r'''#define ENABLED
#ifdef ENABLED
?#OnBoot : BOOT
#else
?#OnBoot : WRONG
#endif
word,copy : kept
?#OnAlias : ${copy}
?#OnNumeric & ${!Reference0} >= 3 : LARGE
?#OnNumeric . : SMALL
?#OnFound & ${!Reference0} found "cat" : FOUND
?#OnFound . : OTHER
?#OnExist & ${!Reference0} exist : EXISTS
?#OnOption "head" : HEAD
?#OnOption . : DEFAULT
?#OnHas & ${!Reference0} has ${!Reference1} : HAS
?#OnCount : $Length{"a","b","c"}
?#OnJoin : $Join{"-","a","b"}
?#OnGet : $Get{"count"}
?#OnInc : $Inc{"count"}
?#OnReset : $Reset{"count"}
?#OnSet : $SetWord{"slot","saved"}${~Word.slot}
?#OnSaved : ${~Word.slot}
?#OnExists : $Hearts.Exist{"cat"}
?#OnAppend : $Hearts.Words.Append{"orange"}$Hearts.Exist.Words{"orange"}
?#OnRelation : $Hearts.Set.Relation{"cat","dog"}$Hearts.GetRelation{"cat"}
?#OnLove : $Hearts.Love{"zebra"}$Hearts.Like{"zebra"}
?#OnHate : $Hearts.Hate{"zebra"}$Hearts.Dislike{"zebra"}
?#OnCheck : $Hearts.Exist{"apple"}:$Hearts.GetRelation{"apple"}
?#OnDate : $MakeDateString{"2024","2","3","4","5","6"}
?#OnTmp : $Tmp{"a","b"}OK
?#OnUserName : $UserName{"Named"}
?#OnReadUser : ${username}:${~String.username}
?#OnHolder : $Hearts.RelationHolder{"cat"}
?#OnStudy : $Hearts.Study{"new","cat"}
?#HitomiStudyNewWord : NEW:${!keyword}:${!teachword}
?#HitomiStudyRequire : REQUIRE:${!keyword}:${!teachword}
?#HitomiStudyReject : REJECT:${!keyword}:${!teachword}
?#HitomiStudySameKey : SAME:${!keyword}:${!teachword}
?#HitomiStudyCommit : COMMIT:${!keyword}:${!teachword}
'''
CASES = [('OnBoot', []), ('OnAlias', []), ('OnNumeric', ['3']), ('OnNumeric', ['2']),
         ('OnFound', ['cat']), ('OnFound', ['dog']), ('OnExist', ['x']), ('OnExist', []),
         ('OnOption', ['head']), ('OnOption', ['body']), ('OnHas', ['3', '3']),
         ('OnCount', []), ('OnJoin', []), ('OnGet', []), ('OnInc', []), ('OnInc', []),
         ('OnGet', []), ('OnReset', []), ('OnGet', []), ('OnSet', []), ('OnSaved', []),
         ('OnExists', []), ('OnAppend', []), ('OnRelation', []), ('OnLove', []), ('OnHate', []),
         ('OnDate', []), ('OnTmp', []), ('OnUserName', []), ('OnReadUser', []),
         ('OnHolder', []), ('OnStudy', []), ('OnTeach', ['apple']), ('OnTeach', ['apple', 'unknown']), ('OnTeach', ['apple', 'apple']),
         ('OnTeach', ['apple', 'cat']), ('OnTeach', ['apple', 'cat', 'cat']),
         ('OnTeach', ['apple', 'cat', '']), ('OnCheck', [])]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('dll', 'psy', 'native', 'wine', 'host', 'prefix', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    driver = Conventional(args.native.resolve())
    rows = []
    with tempfile.TemporaryDirectory(prefix='hitomi046 ') as temporary:
        root = Path(temporary)
        original, native = root / 'original', root / 'native'
        for directory in (original, native):
            directory.mkdir()
            (directory / 'hitomi.ini').write_bytes(b'Locale: Japanese\r\nCharset: Shift_JIS\r\nLanguage: Japanese\r\ndict: ai.txt\r\nAutosave.data: on\r\n')
            (directory / 'psy.ini').write_bytes(b'Hearts.dict: memory.txt\r\n')
            (directory / 'memory.txt').write_bytes(b'Myself: Native,0\r\nMaster: User,0\r\nWord: cat,0\r\nWord: dog,0\r\n')
            (directory / 'ai.txt').write_bytes(CORPUS.replace('\n', '\r\n').encode('cp932'))
        shutil.copyfile(args.dll, original / 'hitomi.dll')
        shutil.copyfile(args.psy, original / 'psy.dll')
        environment = {**os.environ, 'WINEPREFIX': str(args.prefix.resolve()), 'WINEDEBUG': '-all', 'WINEDLLOVERRIDES': 'mscoree,mshtml='}
        for run, cases in [('initial', CASES), ('restart', [('OnSaved', []), ('OnGet', []), ('OnCheck', [])])]:
            with (root / (run + '.log')).open('wb') as log:
                process = subprocess.Popen([str(args.wine.resolve()), windows(args.host.resolve()), windows(original / 'hitomi.dll')],
                                           env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                try:
                    assert frame(process) == b''
                    assert driver.load(native) == 1
                    for event, refs in cases:
                        if event == 'OnTeach':
                            wire = ('TEACH SHIORI/2.4\r\nSender: Probe\r\nWord: ' + refs[0] + '\r\n'
                                    + ''.join(f'Reference{i}: {v}\r\n' for i, v in enumerate(refs[1:])) + '\r\n')
                        else:
                            wire = (f'GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nSender: Probe\r\nID: {event}\r\n'
                                    + ''.join(f'Reference{i}: {v}\r\n' for i, v in enumerate(refs)) + '\r\n')
                        data = wire.encode('cp932')
                        process.stdin.write(struct.pack('<I', len(data)) + data)
                        process.stdin.flush()
                        old = frame(process).decode('cp932')
                        new = driver.request(event, charset='Shift_JIS', references=refs)
                        old_value = value(old, 'Sentence' if event == 'OnTeach' else 'Value')
                        new_value = value(new, 'Value')
                        old_status = int(old.split()[1])
                        new_status = int(new.split()[1])
                        equal = old_value == new_value and old_status == new_status
                        row = {'run': run, 'event': event, 'references': refs,
                               'originalStatus': old_status, 'nativeStatus': new_status,
                               'originalValue': old_value, 'nativeValue': new_value, 'equal': equal,
                               'knownDifference': run == 'restart' and event == 'OnCheck' and old_value == 'apple:' and new_value == 'apple:cat'}
                        rows.append(row)
                        args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
                        print(('PASS ' if equal else 'DIFF ') + run + '/' + event, flush=True)
                    assert driver.unload() == 1
                    process.stdin.close()
                    process.wait(timeout=10)
                    args.output.with_name(args.output.stem + '-' + run + '-memory.txt').write_bytes((original / 'memory.txt').read_bytes())
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
        print(f"{sum(row['equal'] for row in rows)}/{len(rows)} match; {args.output}")
        print(f"{sum(row['knownDifference'] for row in rows)} documented retention difference(s)")
        if not all(row['equal'] or row['knownDifference'] for row in rows):
            raise SystemExit(1)


if __name__ == '__main__':
    main()
