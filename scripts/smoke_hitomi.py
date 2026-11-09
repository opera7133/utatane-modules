#!/usr/bin/env python3
"""Run the legacy and 0.4.6 subsets via the relocated conventional SHIORI ABI."""
import base64
from pathlib import Path
import sys
import tempfile
from conventional_probe import Conventional, relocated


def smoke(library):
    driver = Conventional(library)
    assert driver.request('OnBoot') is None
    assert driver.library.loadu(None, 1) == 0
    with tempfile.TemporaryDirectory(prefix='hitomi 日本語 ') as temporary:
        root = Path(temporary)
        (root / 'kawari.ini').write_bytes(b'dict: ai.txt\r\n')
        source = r'''word: 日本語
@local: local
?OnBoot: \0${word}:${0}:${@local}\e
?OnEcho: ${!Reference0}\e
sentence: 通常\e
'''.encode('cp932')
        lines = [b'!KAWA0000' + base64.b64encode(bytes(b ^ 0xcc for b in line)) for line in source.splitlines()]
        (root / 'ai.txt').write_bytes(b'\r\n'.join(lines) + b'\r\n')
        assert driver.load(root) == 1
        assert driver.load(root) == 0
        assert 'Value: \\0日本語:日本語:local\\e\r\n' in driver.request('OnBoot')
        assert 'Value: 日本語😀\\e\r\n' in driver.request('OnEcho', references=['日本語😀'])
        assert 'Value: 日本語\\e\r\n' in driver.request('OnEcho', charset='Shift_JIS', references=['日本語'])
        assert 'Value: 通常\\e\r\n' in driver.request('OnAITalk')
        assert driver.request('Unknown').startswith('SHIORI/3.0 204')
        assert driver.request('OnBoot', method='NOTIFY').startswith('SHIORI/3.0 204')
        assert driver.unload() == 1
        assert driver.load(root) == 1
        assert driver.unload() == 1
        assert driver.unload() == 1
        (root / 'ai.txt').write_bytes(b'?OnBoot & ${x} equal y: unsupported\r\n')
        assert driver.load(root) == 0
        (root / 'hitomi.ini').write_bytes(b'dict: ai.txt\r\n')
        (root / 'psy.ini').write_bytes(b'Hearts.dict: memory.txt\r\n')
        original_memory = b'Word: cat,0\r\n'
        (root / 'memory.txt').write_bytes(original_memory)
        (root / 'ai.txt').write_bytes(r'''?#OnNumeric & ${!Reference0} >= 3 : NUMBER
?#OnNumeric . : SMALL
?#OnCount : $Inc{"count"}$Get{"count"}
?#HitomiStudyNewWord : NEW:${!keyword}
?#HitomiStudyCommit : SAVED:${!keyword}
?#OnCheck : $Hearts.Exist{"apple"}:$Hearts.GetRelation{"apple"}
'''.replace('\n', '\r\n').encode('cp932'))
        assert driver.load(root) == 1
        assert 'Value: NUMBER\r\n' in driver.request('OnNumeric', references=['3'])
        assert 'Value: SMALL\r\n' in driver.request('OnNumeric', references=['2'])
        assert 'Value: 1\r\n' in driver.request('OnCount')
        assert driver.request('OnTeach', references=['apple']).startswith('SHIORI/3.0 311')
        assert 'Value: SAVED:apple\r\n' in driver.request('OnTeach', references=['apple', 'cat', ''])
        assert driver.unload() == 1
        assert driver.load(root) == 1
        assert 'Value: apple:cat\r\n' in driver.request('OnCheck')
        assert 'Value: 2\r\n' in driver.request('OnCount')
        assert driver.unload() == 1
        assert (root / 'memory.txt').read_bytes() == original_memory
    print('PASS hitomi ABI: encrypted CP932 dictionary, UTF-8/CP932 wire, events, local words, NOTIFY, unsupported syntax rejection')


if __name__ == '__main__':
    with relocated('hitomi', sys.argv[1]) as library:
        smoke(library)
