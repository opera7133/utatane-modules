#!/usr/bin/env python3
"""Exercise Konoka through the relocated malloc/free SHIORI ABI."""
from pathlib import Path
import sys
import subprocess
import tempfile
from conventional_probe import Conventional, relocated


def smoke(library):
    driver = Conventional(library)
    assert driver.request('OnBoot') is None
    assert driver.library.loadu(None, 1) == 0
    with tempfile.TemporaryDirectory(prefix='konoka 日本語 ') as temporary:
        root = Path(temporary)
        (root / 'konoka.ini').write_bytes(b'ai.txt,e\r\n')
        (root / 'ai.txt').write_bytes(r'''\word,辞書
@OnBoot,起動%(2+3*4):%word
@OnEcho,%ref0
@OnSave,%(\_save:=counter.7)
@OnRestore,%(\_load:=counter)
@OnTeach,%word:%lasthint\[shortage]
*homeurl,https://example.test/
'''.replace('\n', '\r\n').encode('cp932'))
        assert driver.load(root) == 1
        assert driver.load(root) == 0
        assert (root / 'ai.xdc').is_file()
        assert 'Value: 起動14:辞書\\e\r\n' in driver.request('OnBoot')
        assert 'Value: 日本語😀\\e\r\n' in driver.request('OnEcho', references=['日本語😀'])
        assert 'Value: 日本語\\e\r\n' in driver.request('OnEcho', charset='Shift_JIS', references=['日本語'])
        assert 'Value: https://example.test/\r\n' in driver.request('homeurl')
        assert driver.request('OnTeach', references=['apple', 'cat']).startswith('SHIORI/3.0 311')
        assert driver.request('Unknown').startswith('SHIORI/3.0 204')
        assert driver.request('OnSave', method='NOTIFY').startswith('SHIORI/3.0 204')
        assert driver.unload() == 1
        assert driver.load(root) == 1
        assert 'Value: 7\\e\r\n' in driver.request('OnRestore')
        assert driver.unload() == 1
        assert driver.unload() == 1
        assert driver.request('OnBoot') is None
        tool = library.parent.parent / 'bin/konoka-dictionary'
        if tool.is_file():
            subprocess.run([str(tool), 'encode', str(root / 'ai.txt'), str(root / 'ai.xdi')], check=True)
            subprocess.run([str(tool), 'decode', str(root / 'ai.xdi'), str(root / 'decoded.txt')], check=True)
            assert (root / 'decoded.txt').read_bytes() == (root / 'ai.txt').read_bytes()
            refused = subprocess.run([str(tool), 'decode', str(root / 'ai.xdi'), str(root / 'ai.txt')], capture_output=True)
            assert refused.returncode != 0
            (root / 'ai.txt').unlink()
            (root / 'ai.xdc').unlink()
            assert driver.load(root) == 1
            assert 'Value: 起動14:辞書\\e\r\n' in driver.request('OnBoot')
            assert driver.unload() == 1
            subprocess.run([str(tool), 'encode', str(root / 'decoded.txt'), str(root / 'ai.xdc')], check=True)
            subprocess.run([str(tool), 'decode', str(root / 'ai.xdc'), str(root / 'xdc-decoded.txt')], check=True)
            assert (root / 'xdc-decoded.txt').read_bytes() == (root / 'decoded.txt').read_bytes()
            (root / 'ai.xdi').unlink()
            assert driver.load(root) == 1
            assert 'Value: 起動14:辞書\\e\r\n' in driver.request('OnBoot')
            assert driver.unload() == 1
    print('PASS konoka ABI: CP932 dictionary/request, UTF-8 emoji, resources, expressions, NOTIFY, persistence, reload')


if __name__ == '__main__':
    with relocated('konoka', sys.argv[1]) as library:
        smoke(library)
