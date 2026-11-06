#!/usr/bin/env python3
"""Probe the portable C# D.N.Proxy through the relocated dylib and managed host."""
from pathlib import Path
import sys
import ctypes
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
        last_error = driver.library.utatane_shiori_last_error
        last_error.argtypes = [ctypes.POINTER(ctypes.c_int32)]
        last_error.restype = ctypes.c_void_p
        def error_text():
            size = ctypes.c_int32()
            pointer = last_error(ctypes.byref(size))
            assert pointer and 0 < size.value <= 4096
            try: return ctypes.string_at(pointer, size.value).decode('utf-8')
            finally: driver.libc.free(pointer)
        assert 'DNProxy [unsupported]' in error_text()
        (root / 'Portable.cs').write_text('not valid C#;')
        (root / 'dnproxy.ini').write_text('Language: C#\nSourceFiles: Portable.cs\nMainClass: Portable.Ghost\n')
        assert driver.load(root) == 0
        assert 'DNProxy [compile]' in error_text()
        (root / 'dnproxy.ini').unlink()
        assert driver.load(root) == 0
        assert 'DNProxy [assembly]' in error_text()
        (root / 'Reject.cs').write_text('''using System;
using System.Runtime.InteropServices;
using Ukagaka.NET.Interfaces;
public class Reject : ILoad, IRequest, IUnload {
    public bool load(IntPtr p, int n) { Marshal.FreeHGlobal(p); return false; }
    public IntPtr request(IntPtr p, ref int n) { Marshal.FreeHGlobal(p); n = 0; return IntPtr.Zero; }
    public bool unload() { return true; }
}''')
        (root / 'dnproxy.ini').write_text('Language: C#\nSourceFiles: Reject.cs\nMainClass: Reject\n')
        assert driver.load(root) == 0
        assert 'DNProxy [load]' in error_text()
        assert driver.unload() == 1
    print('PASS DNProxy ABI: portable C# compilation, UTF-8, managed host relocation, save/reload, duplicate load, unsupported language')


if __name__ == '__main__':
    with relocated('dnproxy', sys.argv[1]) as library:
        smoke(library)
