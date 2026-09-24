"""Check the DLL-to-dylib lookup used by distributed YAYA and SATORI."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin", "macOS dylib test")
class SaoriLibraryResolutionTests(unittest.TestCase):
    def test_bundled_names_precede_managed_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ghost = root / "ghost/master/saori"
            ghost.mkdir(parents=True)
            managed = root / "managed/kenonoke/lib"
            managed.mkdir(parents=True)
            runner = root / "runner"
            source = root / "runner.cpp"
            source.write_text('''
#include "SaoriLibrary.h"
#include <cstdlib>
#include <cstdio>
int main(int argc, char **argv) {
    if (argc != 2 || !saori::load(argv[1])) return 1;
    long length = 1;
    char *answer = saori::request(argv[1], "x", &length);
    if (!answer) return 2;
    fwrite(answer, 1, length, stdout);
    free(answer);
    return saori::unload(argv[1]) ? 0 : 3;
}
''')
            subprocess.run(["xcrun", "clang++", "-std=c++17", "-I", str(ROOT / "recipes/cpp"),
                            str(source), str(ROOT / "recipes/cpp/SaoriLibrary.cpp"), "-o", str(runner)], check=True)
            module_source = root / "module.c"
            module_source.write_text('''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifndef ANSWER
#define ANSWER "unknown"
#endif
int32_t loadu(void *path, int32_t length) { free(path); return length > 0; }
int32_t unload(void) { return 1; }
void *request(void *input, int32_t *length) {
    free(input); const char *answer = ANSWER;
    *length = (int32_t)strlen(answer);
    char *result = malloc(*length); memcpy(result, answer, *length); return result;
}
''')
            plain = ghost / "kenonoke.dylib"
            prefixed = ghost / "libkenonoke.dylib"
            shared = managed / "libkenonoke.dylib"
            for destination, answer in [(plain, "plain"), (prefixed, "prefixed"), (shared, "managed")]:
                subprocess.run(["xcrun", "clang", "-dynamiclib", f'-DANSWER="{answer}"',
                                str(module_source), "-o", str(destination)], check=True)
            declared = ghost / "kenonoke.dll"
            environment = {**os.environ, "UTATANE_SAORI_ROOT": str(root / "managed")}

            def selected():
                return subprocess.check_output([runner, declared], env=environment, text=True)

            self.assertEqual(selected(), "plain")
            plain.unlink()
            self.assertEqual(selected(), "prefixed")
            prefixed.unlink()
            self.assertEqual(selected(), "managed")


if __name__ == "__main__":
    unittest.main()
