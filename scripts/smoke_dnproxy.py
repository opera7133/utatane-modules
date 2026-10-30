#!/usr/bin/env python3
"""Probe the portable C# D.N.Proxy through the relocated dylib and managed host."""
from pathlib import Path
import sys
import tempfile
from conventional_probe import Conventional, relocated

ROOT = Path(__file__).resolve().parents[1]


def smoke(library):
    driver = Conventional(library)
    assert driver.request('OnBoot') is None
    with tempfile.TemporaryDirectory(prefix='DNProxy ghost 日本語 ') as temporary:
        root = Path(temporary)
        (root / 'Portable.cs').write_bytes((ROOT / 'tests/fixtures/dnproxy/Portable.cs').read_bytes())
        (root / 'dnproxy.dll.config').write_text('''<configuration><applicationSettings><D.N.Properties.Settings>
<setting name="AssemblyName"><value>user.dll</value></setting>
<setting name="MainClass"><value>Portable.Ghost</value></setting>
<setting name="Protocol"><value>SHIORI/3.0</value></setting>
</D.N.Properties.Settings></applicationSettings></configuration>''')
        (root / 'dnproxy.ini').write_text('Language: C#\nSourceFiles: Portable.cs\nMainClass: Portable.Ghost\n')
        assert driver.load(root) == 1
        assert driver.load(root) == 0
        assert '日本語😀 count=1' in driver.request('OnBoot')
        assert driver.unload() == 1
        assert driver.unload() == 1
        assert driver.load(root) == 1
        assert '日本語😀 count=2' in driver.request('OnBoot')
        assert driver.unload() == 1
        assert not (root / 'user.dll').exists()
        assert driver.request('OnBoot') is None
        (root / 'dnproxy.ini').write_text('Language: JScript\nSourceFiles: Portable.cs\n')
        assert driver.load(root) == 0
        assert driver.unload() == 1
    print('PASS DNProxy ABI: portable C# compilation, UTF-8, managed host relocation, save/reload, duplicate load, unsupported language')


if __name__ == '__main__':
    with relocated('dnproxy', sys.argv[1]) as library:
        smoke(library)
