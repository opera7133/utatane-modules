#!/usr/bin/env python3
"""Exercise the independent mae/DNProxy packages using Utatane's real helper."""
import argparse
from pathlib import Path
import shutil
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package
from test_cpp_host import Host


def fixture(identity, root):
    root.mkdir(parents=True)
    if identity == 'mae':
        (root / 'mae_corpus.txt').write_text('''#Declaration:
var count;
:end
#Initialize:
count = count + 1;
:end
#OnBoot
count=${count} 日本語😀
''')
    else:
        shutil.copyfile(ROOT / 'tests/fixtures/dnproxy/Portable.cs', root / 'Portable.cs')
        (root / 'dnproxy.ini').write_text('Language: C#\nSourceFiles: Portable.cs\nMainClass: Portable.Ghost\n')
        (root / 'dnproxy.dll.config').write_text('''<configuration><applicationSettings><D.N.Properties.Settings>
<setting name="AssemblyName"><value>user.dll</value></setting>
<setting name="MainClass"><value>Portable.Ghost</value></setting>
<setting name="Protocol"><value>SHIORI/3.0</value></setting>
</D.N.Properties.Settings></applicationSettings></configuration>''')


def run(helper, identity, archive):
    verify_package(archive, read_json(ROOT / f'catalog/modules/{identity}.json'))
    with tempfile.TemporaryDirectory(prefix=f'{identity} Utatane 日本語 ') as temporary:
        root = Path(temporary)
        safe_extract(archive, root / 'relocated')
        library = root / f'relocated/{identity}/lib/lib{identity}.dylib'
        a, b = root / 'ghost A', root / 'ghost B'
        fixture(identity, a)
        fixture(identity, b)
        hosts = []
        try:
            for directory in (a, b):
                host = Host(helper, library, directory, root / 'shared')
                hosts.append(host)
                response = host.send('OnBoot')
                assert 'count=1' in response and '日本語😀' in response, response
            for host in hosts:
                host.close()
            hosts = []
            reloaded = Host(helper, library, a, root / 'shared')
            hosts.append(reloaded)
            assert 'count=2' in reloaded.send('OnBoot')
            reloaded.close()
            hosts = []
        finally:
            for host in hosts:
                host.abort()
    print(f'PASS {identity}: real Utatane helper, two isolated ghosts, relocated package, persistence/reload')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--mae', type=Path)
    parser.add_argument('--dnproxy', type=Path)
    args = parser.parse_args()
    assert args.mae or args.dnproxy
    for identity in ('mae', 'dnproxy'):
        archive = getattr(args, identity)
        if archive:
            run(args.host.resolve(), identity, archive.resolve())
