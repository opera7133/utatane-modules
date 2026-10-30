#!/usr/bin/env python3
"""Probe mae's independent interpreter through its packaged conventional ABI."""
import os
import platform
import subprocess
from pathlib import Path
import sys
import tempfile
from conventional_probe import Conventional, relocated


def smoke(library):
    driver = Conventional(library)
    assert driver.request('OnBoot') is None
    assert driver.library.loadu(None, 1) == 0
    with tempfile.TemporaryDirectory(prefix='mae ghost 日本語 ') as temporary:
        root = Path(temporary)
        (root / 'mae_corpus.txt').write_bytes('''#Declaration:
var count, message, code, result, output[2], arguments[2];
:end
#Initialize:
count = count + 1;
code = saoriload("echo", result, "echo.dll");
:end
#OnBoot:
message = sprint("起動", count);
:end
${message}
#OnEcho:
message = reference[0];
:end
${message}
#OnJapanese
日本語
#OnSaori:
arguments[0] = reference[0];
code = saori("echo", result, output, arguments, 1);
message = output[0];
:end
${code}:${result}:${message}
#OnSaoriVariable
${%saori:0:echo:arguments:1}
#Finalize:
count = count + 10;
:end
'''.encode('cp932'))
        echo = root / 'echo.c'
        echo.write_text(r'''#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) { free(p); return n > 0; }
int32_t unload(void) { return 1; }
void *request(void *p, int32_t *n) {
    char *in = malloc((size_t)*n + 1); memcpy(in, p, *n); in[*n] = 0; free(p);
    int execute = strstr(in, "EXECUTE ") != NULL;
    int valid = strstr(in, "Argument0: 日本語😀\r\n") != NULL;
    const char *text = !execute ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\n\r\n" :
        valid ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: native-ok\r\nValue0: second\r\n\r\n" :
        "SAORI/1.0 400 Bad Request\r\nCharset: UTF-8\r\n\r\n";
    free(in); *n = (int32_t)strlen(text); void *out = malloc(*n); memcpy(out, text, *n); return out;
}
''')
        subprocess.run(['xcrun', 'clang', '-arch', platform.machine(), '-dynamiclib', str(echo),
                        '-o', str(root / 'libecho.dylib')], check=True)
        assert driver.load(root) == 1
        assert driver.load(root) == 0
        assert 'Value: 起動1\r\n' in driver.request('OnBoot')
        assert 'Value: 日本語😀\r\n' in driver.request('OnEcho', references=['日本語😀'])
        assert 'Value: 日本語\r\n' in driver.request('OnJapanese', charset='Shift_JIS')
        response = driver.request('OnSaori', references=['日本語😀'])
        assert 'Value: 200:native-ok:second\r\n' in response, response
        assert 'Value: native-ok\r\n' in driver.request('OnSaoriVariable')
        assert driver.request('OnJapanese', method='NOTIFY').startswith('SHIORI/3.0 204')
        assert driver.unload() == 1
        assert driver.unload() == 1
        assert (root / 'mae-native-state.json').is_file() or os.environ.get('UTATANE_GHOST_STATE_DIR') or os.environ.get('MAE_STATE_PATH')
        assert driver.load(root) == 1
        assert 'Value: 起動12\r\n' in driver.request('OnBoot')
        assert driver.unload() == 1
        assert driver.request('OnBoot') is None
    print('PASS mae ABI: CP932 dictionary/request, UTF-8 emoji, Declaration/Initialize/Finalize, save/reload, duplicate load, NOTIFY, native SAORI Result/Value')


if __name__ == '__main__':
    with relocated('mae', sys.argv[1]) as library:
        smoke(library)
