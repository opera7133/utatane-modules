#!/usr/bin/env python3
"""Compare ACP/Unicode SATORI with disposable dictionaries and optional local ghosts."""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_cpp_host import Host

DICTIONARY = """＊OnBoot
：こんにちは ABC。
＊OnArithmetic
：（calc、2+3*4）／（calc、10/2）。
＊OnString
：（length、あいう）／（substr、あいう、1、1）。
＊OnChoice
：選んで。
＿選択\tOnChosen
＊OnChosen
：選んだ。
＊OnSet
＄確認\t保存できた
：設定。
＊OnRead
：値は（確認）。
＊OnPower
：（calc、2^3）。
＊OnSaori
：（echo、日本語）。
＊OnValues
：（echo、values）（Ｓ０）|（Ｓ１）|（Ｓ２）。
＊OnNoValues
：（echo、日本語）（Ｓ２）。
＊OnUnicodeInput
：（Ｒ０）。
"""


def send(host, event, references=(), allow_errors=False):
    wire = f"GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Utatane\r\nSecurityLevel: local\r\nID: {event}\r\n"
    wire += "".join(f"Reference{i}: {value}\r\n" for i, value in enumerate(references)) + "\r\n"
    response = host.exchange(1, wire.encode()).decode("utf-8")
    assert response.startswith(("SHIORI/3.0 200", "SHIORI/3.0 204")), response
    if not allow_errors: assert "ErrorLevel: critical" not in response, response
    return response


@contextmanager
def session(helper, library, directory):
    host = Host(helper, library, directory, directory / "shared")
    try:
        yield host
    finally:
        if host.process.poll() is None:
            host.close()
        host.abort()


def fixture(directory, encrypted=False, encoding="cp932"):
    directory.mkdir(parents=True)
    (directory / "dic00.txt").write_bytes(DICTIONARY.replace("\n", "\r\n").encode(encoding))
    config = "＊初期化\r\n＄自動挿入ウェイトの倍率\t100\r\n"
    if encrypted: config += "＄セーブデータ暗号化\t有効\r\n"
    (directory / "satori_conf.txt").write_bytes(config.encode(encoding))


def c_string(data):
    return '"' + "".join(f"\\x{byte:02x}" for byte in data) + '"'


def saori_fixture(directory, unicode_wire):
    encoding = "utf-8" if unicode_wire else "cp932"
    charset = b"Charset: UTF-8\r\n" if unicode_wire else b""
    version = b"SAORI/1.0 200 OK\r\n" + charset + b"\r\n"
    answer = b"SAORI/1.0 200 OK\r\n" + charset + "Result: 日本語\r\n\r\n".encode(encoding)
    values = b"SAORI/1.0 200 OK\r\n" + charset + b"Result: \r\nValue2: third\r\n\r\n"
    needle = "Argument0: 日本語".encode(encoding)
    if unicode_wire: needle = "Argument0: 😀𠮷".encode(encoding)
    unicode_answer = b"SAORI/1.0 200 OK\r\nCharset: UTF-8\r\n" + "Result: 😀𠮷\r\n\r\n".encode()
    source = directory / "echo.c"
    source.write_text(f'''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int32_t loadu(void *p, int32_t n) {{ free(p); return n > 0; }}
int32_t unload(void) {{ return 1; }}
void *request(void *p, int32_t *n) {{
    char *in = calloc(*n + 1, 1); memcpy(in, p, *n); free(p);
    const char *out = "SAORI/1.0 200 OK\\r\\nResult: wrong-encoding\\r\\n\\r\\n";
    if (strstr(in, "GET Version")) out = {c_string(version)};
    else if (strstr(in, "Argument0: values")) out = {c_string(values)};
    else if (strstr(in, {c_string('Argument0: 日本語'.encode(encoding))})) out = {c_string(answer)};
    else if (strstr(in, {c_string(needle)})) out = {c_string(unicode_answer if unicode_wire else answer)};
    else if (strstr(in, "Argument0: \\r\\n")) out = {c_string(version)};
    free(in); *n = strlen(out); void *result = malloc(*n); memcpy(result, out, *n); return result;
}}
''')
    subprocess.run(["cc", "-dynamiclib", str(source), "-o", str(directory / "libecho.dylib")], check=True)
    with (directory / "satori_conf.txt").open("ab") as stream:
        stream.write("＠SAORI\r\necho,echo.dll\r\n".encode("cp932"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--unicode", type=Path, required=True)
    parser.add_argument("--legacy", type=Path)
    parser.add_argument("--ghost", type=Path, action="append", default=[])
    args = parser.parse_args()
    helper, current = args.host.resolve(), args.unicode.resolve()
    legacy = args.legacy.resolve() if args.legacy else None
    report = {"synthetic": [], "ghosts": []}
    with tempfile.TemporaryDirectory(prefix="SATORI 互換性 ") as temporary:
        root = Path(temporary)
        for encrypted in (False, True):
            directory = root / f"legacy-save-{encrypted}"
            fixture(directory, encrypted)
            baseline = {}
            if legacy:
                with session(helper, legacy, directory) as host:
                    for event in ("OnBoot", "OnArithmetic", "OnString", "OnChoice", "OnChosen", "OnPower"):
                        baseline[event] = send(host, event)
                    assert "設定" in send(host, "OnSet")
                save = directory / ("satori_savedata.sat" if encrypted else "satori_savedata.txt")
                assert save.is_file()
                if not encrypted: assert "保存できた" in save.read_bytes().decode("cp932")
            with session(helper, current, directory) as host:
                for event in ("OnBoot", "OnArithmetic", "OnString", "OnChoice", "OnChosen"):
                    response = send(host, event)
                    # Header ordering is not part of the SHIORI contract.
                    if legacy: assert sorted(response.split("\r\n")) == sorted(baseline[event].split("\r\n")), (event, baseline[event], response)
                if legacy: assert "保存できた" in send(host, "OnRead")
                else: assert "設定" in send(host, "OnSet")
                assert "8。" in send(host, "OnPower")
            with session(helper, current, directory) as host:
                assert "保存できた" in send(host, "OnRead")
            if not encrypted:
                assert "保存できた" in (directory / "satori_savedata.txt").read_text(encoding="utf-8")
            report["synthetic"].append({"encrypted": encrypted, "legacyPower": baseline.get("OnPower"), "status": "passed"})
        for unicode_wire in (False, True):
            directory = root / f"saori-{unicode_wire}"
            fixture(directory)
            saori_fixture(directory, unicode_wire)
            if unicode_wire:
                (directory / "dic01.txt").write_text("＊OnUnicodeSaori\n：（echo、😀𠮷）。\n", encoding="utf-8")
            with session(helper, current, directory) as host:
                assert "日本語" in send(host, "OnSaori")
                assert "||third" in send(host, "OnValues")
                assert "third" in send(host, "OnNoValues")
                assert "输入😀𠮷" in send(host, "OnUnicodeInput", ("输入😀𠮷",))
                if unicode_wire: assert "😀𠮷" in send(host, "OnUnicodeSaori")
            report["synthetic"].append({"saoriUTF8": unicode_wire, "status": "passed"})
        directory = root / "UTF-8辞書"
        fixture(directory, encoding="utf-8")
        with (directory / "dic00.txt").open("ab") as stream:
            stream.write("＊OnUnicode\r\n：😀𠮷（length、😀𠮷）。\r\n＊OnUnicodeSave\r\n＄確認\t😀𠮷\r\n：保存。\r\n".encode())
        with session(helper, current, directory) as host:
            assert "😀𠮷2" in send(host, "OnUnicode")
            send(host, "OnUnicodeSave")
        with session(helper, current, directory) as host:
            assert "😀𠮷" in send(host, "OnRead")
        report["synthetic"].append({"unicodeDictionaryAndSave": "passed"})
        for index, ghost in enumerate(args.ghost):
            # Copy only to a disposable workspace; never load original user saves.
            source = ghost.resolve()
            records = []
            for label, library in (("legacy", legacy), ("unicode", current)):
                if library is None: continue
                directory = root / f"ghost-{index}-{label}"
                shutil.copytree(source, directory, symlinks=False)
                with session(helper, library, directory) as host:
                    responses = {event: send(host, event, ("0", "0", "0", "0", "0", "0", "0"), allow_errors=True)
                                 for event in ("OnBoot", "OnFirstBoot", "OnSecondChange", "OnMouseDoubleClick", "OnClose")}
                with session(helper, library, directory) as host:
                    responses["reload"] = send(host, "OnBoot", allow_errors=True)
                records.append({"engine": label, "events": {key: len(value) for key, value in responses.items()},
                                "criticalEvents": [key for key, value in responses.items() if "ErrorLevel: critical" in value]})
            if legacy:
                assert set(records[1]["criticalEvents"]) <= set(records[0]["criticalEvents"]), records
            report["ghosts"].append({"name": source.parent.parent.name, "runs": records})
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()
