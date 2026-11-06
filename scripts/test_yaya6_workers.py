#!/usr/bin/env python3
"""Test YAYA 6 worker/capture behavior through the real Utatane helper."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

from catalog import ROOT
from test_cpp_host import Host


class Yaya6WorkerTests(unittest.TestCase):
    helper = None
    library = None

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="YAYA 並行 日本語 ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.host = None
        self.addCleanup(self.cleanup_host)
        text = (ROOT / "sources/yaya-6/tests/thread/thread.dic").read_text(encoding="utf-8-sig")
        text += r'''
TH.Block
{
    _r = EXECUTE_CAPTURE('./block.sh')
    _r['status']
}
TH.Capture
{
    _r = EXECUTE_CAPTURE('/bin/sh', '-c "printf out; printf err >&2; exit 7"')
    _r['status'] + '|' + _r['stdout'] + '|' + _r['stderr'] + '|' + TOSTR(_r['exitcode'])
}
TH.Timeout
{
    _opts = IHASH()
    _opts['timeout'] = 20
    _r = EXECUTE_CAPTURE('./block.sh', '', '', _opts)
    _r['status']
}
TH.InputLimit
{
    _opts = IHASH()
    _opts['stdin'] = 'hello'
    _opts['maxsize'] = 3
    _r = EXECUTE_CAPTURE('/bin/cat', '', '', _opts)
    _r['status'] + '|' + _r['stdout']
}
TH.Internal
{
    _loaded = LOADLIB('internal_system')
    _wire = "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))Argument0: ListModules%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))"
    _r = REQUESTLIB('internal_system', _wire)
    'returned'
}
TH.Native
{
    _path = _argv[0]
    _loaded = LOADLIB(_path)
    _count = 0
    for _i = 0; _i < 100; _i++ {
        _r = REQUESTLIB(_path, "EXECUTE SAORI/1.0%(CHR(13))%(CHR(10))Charset: UTF-8%(CHR(13))%(CHR(10))%(CHR(13))%(CHR(10))")
        if STRSTR(_r, 'alive', 0) >= 0 { _count++ }
    }
    _count
}
'''
        # Avoid a duplicate definition of the upstream Windows-only TH.Capture helper.
        text = text.replace('TH.Capture\n{\n\t_r = EXECUTE_CAPTURE(GETENV', 'TH.WindowsCapture\n{\n\t_r = EXECUTE_CAPTURE(GETENV')
        (self.root / "thread.dic").write_text(text, encoding="utf-8")
        (self.root / "yaya.txt").write_text("charset, UTF-8\ndic, thread.dic\nlooplimit, 0\n")
        blocker = self.root / "block.sh"
        blocker.write_text("#!/bin/sh\necho $$ > ready.pid\n/usr/bin/tail -f /dev/null &\necho $! > descendant.pid\nwait\n")
        blocker.chmod(0o755)
        self.host = Host(self.helper, self.library, self.root, self.root / "shared")

    def cleanup_host(self):
        if self.host is not None:
            self.host.abort()
            self.host = None
        marker = self.root / "ready.pid"
        if marker.exists():
            pid = int(marker.read_text())
            try:
                if os.getpgid(pid) == pid:
                    os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                descendant = self.root / "descendant.pid"
                if descendant.exists():
                    try:
                        if os.getpgid(int(descendant.read_text())) == pid:
                            os.killpg(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def evaluate(self, expression):
        reply = self.host.exchange(1, ("!! " + expression).encode()).decode()
        self.assertTrue(reply.startswith("!! "), reply)
        return reply[3:]

    def wait_for(self, condition):
        deadline = time.monotonic() + 5
        while not condition():
            if time.monotonic() >= deadline:
                self.fail("condition did not complete before deadline")
            time.sleep(0.01)

    def start_blocker(self):
        identity = int(self.evaluate("THREADSTART('TH.Block')"))
        self.assertGreater(identity, 0)
        self.wait_for(lambda: (self.root / "descendant.pid").exists())
        return identity, int((self.root / "ready.pid").read_text())

    @staticmethod
    def exited(pid):
        try:
            os.kill(pid, 0)
            return False
        except ProcessLookupError:
            return True

    def test_nested_workers(self):
        self.assertEqual(self.evaluate("TH.Nest()"), "30")

    def test_capture_output_and_exit_status(self):
        self.assertEqual(self.evaluate("TH.Capture()"), "ok|out|err|7")

    def test_capture_stdin_and_output_limit(self):
        self.assertEqual(self.evaluate("TH.InputLimit()"), "truncated|hel")

    def test_capture_timeout(self):
        self.assertEqual(self.evaluate("TH.Timeout()"), "timeout")
        marker = self.root / "ready.pid"
        if marker.exists():
            self.wait_for(lambda: self.exited(int(marker.read_text())))

    def test_cancel_capture_keeps_requests_responsive_and_reaps_child(self):
        identity, pid = self.start_blocker()
        self.assertEqual(self.evaluate("1+2"), "3")
        self.assertEqual(self.evaluate(f"THREADSTOP({identity})"), "1")
        self.evaluate(f"THREADJOIN({identity})")
        self.assertEqual(self.evaluate(f"THREADSTATE({identity})"), "2")
        self.wait_for(lambda: self.exited(pid))
        descendant = self.root / "descendant.pid"
        if descendant.exists():
            self.wait_for(lambda: self.exited(int(descendant.read_text())))

    def test_unload_cancels_capture_and_reaps_child(self):
        _, pid = self.start_blocker()
        self.host.close()
        self.host = None
        self.wait_for(lambda: self.exited(pid))
        descendant = self.root / "descendant.pid"
        if descendant.exists():
            self.wait_for(lambda: self.exited(int(descendant.read_text())))

    def test_worker_internal_callback_returns_without_corrupting_pipe(self):
        identity = int(self.evaluate("THREADSTART('TH.Internal')"))
        self.evaluate(f"THREADJOIN({identity})")
        self.assertEqual(self.evaluate(f"THREADRESULT({identity})"), "returned")
        self.assertEqual(self.evaluate("10+20"), "30")

    def test_different_native_saori_workers_share_lookup_safely(self):
        source = self.root / "echo.c"
        source.write_text(r'''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) { free(p); return n > 0; }
int32_t unload(void) { return 1; }
void *request(void *p, int32_t *n) {
    free(p);
    const char *answer = "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: alive\r\n\r\n";
    *n = (int32_t)strlen(answer);
    void *r = malloc(*n); memcpy(r, answer, *n); return r;
}
''')
        for name in ("one", "two"):
            subprocess.run(["xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-arch", "x86_64", str(source), "-o", str(self.root / (name + ".dylib"))], check=True)
        first = int(self.evaluate("THREADSTART('TH.Native','one.dll')"))
        second = int(self.evaluate("THREADSTART('TH.Native','two.dll')"))
        self.assertEqual(self.evaluate("1+2"), "3")
        for identity in (first, second):
            self.evaluate(f"THREADJOIN({identity})")
            self.assertEqual(self.evaluate(f"THREADRESULT({identity})"), "100")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    parser.add_argument("--library", required=True, type=Path)
    args = parser.parse_args()
    Yaya6WorkerTests.helper = args.host.resolve()
    Yaya6WorkerTests.library = args.library.resolve()
    unittest.main(argv=[__file__], verbosity=2)
