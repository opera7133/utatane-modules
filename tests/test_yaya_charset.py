"""Exercise the real empty-string conversion with AddressSanitizer."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "macOS charset regression")
class YayaCharsetTests(unittest.TestCase):
    def test_empty_legacy_charset_allocates_a_full_wide_character(self):
        for identity in ("yaya", "yaya-6"):
            with self.subTest(module=identity), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                vendor = ROOT / "sources" / identity
                source = (vendor / "ccct.cpp").read_bytes()
                if identity == "yaya-6":
                    source = subprocess.check_output(["iconv", "-f", "CP932", "-t", "UTF-8", "-c"], input=source)
                (root / "ccct.cpp").write_bytes(source)
                (root / "probe.cpp").write_text('''
#include "ccct.h"
#include "manifest.h"
#include <cstdlib>
int main() {
    static_assert(sizeof(wchar_t) == 4, "exercise the POSIX wide character size");
    wchar_t *value = Ccct::MbcsToUcs2("", CHARSET_SJIS);
    if (!value) return 1;
    bool empty = value[0] == 0;
    free(value);
    return empty ? 0 : 2;
}
''')
                runner = root / "probe"
                compiled = subprocess.run(["xcrun", "clang++", "-std=c++14", "-DPOSIX", "-fsanitize=address",
                                "-I", str(vendor), str(root / "probe.cpp"), str(root / "ccct.cpp"),
                                "-o", str(runner)], capture_output=True)
                self.assertEqual(compiled.returncode, 0, compiled.stderr.decode(errors="replace"))
                checked = subprocess.run([str(runner)], capture_output=True,
                               env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0"})
                self.assertEqual(checked.returncode, 0, checked.stderr.decode(errors="replace"))
