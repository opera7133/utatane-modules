#!/usr/bin/env python3
"""Build a macOS BalloonSelector NAR from the audited upstream checkout."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import zipfile

UPSTREAM_COMMIT = "04ac6c086a03f1394c572d0748e4bdd190046c77"
UTIL_SHA256 = "93c41c45107820c4970d2f4cfc1cf650b19acffe0f1d8549fa2b411caf2a74c4"
MAIN_SHA256 = "313a64fffd6aed7929dd7bc07cfd445cccdb6ac2b5154ab15b7de63072180529"
NATIVE_VIEW = r'''ShowBalloonView
{
    _page = _argv[0]
    _width = _argv[1]; if _width < 100 { _width = 100 }
    _max = ARRAYSIZE(PLUGINUTIL.installedballoon_path)
    _start = _page * 9
    _end = _start + 9; if _end > _max { _end = _max }
    _pages = (_max - 1) / 9 + 1
    _ret = '\![set,balloontimeout,0]\![set,autoscroll,disable]\0\s[0]\b[2]\_q\f[height,12]'
    _ret += "BalloonSelector %(_page + 1)/%(_pages)  "
    if _page > 0 {
        _ret += "\q[前へ,OnBalloonSelectMenuOpen,%(_page - 1)] "
    }
    if _end < _max {
        _ret += "\q[次へ,OnBalloonSelectMenuOpen,%(_page + 1)] "
    }
    _ret += '\q[閉じる,PLUGINUTIL.Menu_CANCEL]\n'
    _wi = _width / 4; if _wi > 80 { _wi = 80 }
    _ti = (_width - _wi - 16) / 12; if _ti < 1 { _ti = 1 }
    for _i = _start; _i < _end; _i++ {
        _tmp_path = PLUGINUTIL.installedballoon_path[_i] + "\\balloons0.png"
        _tmp_name = PLUGINUTIL.installedballoon_name[_i]
        _quoted_path = '"' + REPLACE(_tmp_path,'"','""') + '"'
        _quoted_name = '"' + REPLACE(_tmp_name,'"','""') + '"'
        _nameshow = PLUGINUTIL.MakeShortText(_tmp_name,_ti)
        _nameshow = REPLACE(_nameshow,'\','\\')
        _ret += "\__q[OnPLUGINUTIL.BalloonChange,%(_quoted_name)]\_b[%(_quoted_path),inline,--clipping=0 0 %(_wi) 22] %(_nameshow)\__q\n"
    }
    _ret += '\f[height,default]\_q\e'
    _ret
}
'''
PORT_NOTE = f"""BalloonSelector 2.4 / Utatane port 1
Original: Don / https://github.com/nikolat/balloonselector
Upstream commit: {UPSTREAM_COMMIT}

Utataneの未リリース開発版と、Modulesから導入したYAYAが必要です。
macOS版YAYAのFENUMは親ディレクトリを含まないため、列挙の先頭を飛ばさないよう修正しています。
自由座標配置の互換差を避け、1ページ9件のプレビュー付き一列リストで表示します。
プラグインID、ページ切替・キャンセル処理、選択時のゴースト通知は原版を使用します。
原版へのネットワーク更新で移植部分が消えないよう、homeurlを除いています。
Windows向けの配布物には原版を使ってください。
元の辞書はUnlicense、同梱yaya.dllはBSD-3-Clauseです。LICENSEを参照してください。
"""


def build(source: Path, output: Path):
    source = source.resolve()
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != UPSTREAM_COMMIT:
        raise ValueError("Unexpected BalloonSelector revision; audit the upstream change first")
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise ValueError("Upstream checkout has modified tracked files")
    if output.resolve().is_relative_to(source):
        raise ValueError("Write the NAR outside the upstream checkout")
    util = (source / "yaya_plugin_util.dic").read_bytes()
    if hashlib.sha256(util).hexdigest() != UTIL_SHA256:
        raise ValueError("BalloonSelector utility dictionary differs from the audited source")
    anchor = b"StructBalloonList.Index = 0"
    if util.count(anchor) != 1:
        raise ValueError("BalloonSelector enumeration patch is ambiguous")
    util = util.replace(anchor, b"StructBalloonList.Index = -1")
    util = util.replace(b"_name = CUTSPACE(_line[1])", b"_name = CUTSPACE(SUBSTR(_line,STRSTR(_line,',',0) + 1,STRLEN(_line)))")
    main = (source / "yaya_plugin_main.txt").read_bytes()
    if hashlib.sha256(main).hexdigest() != MAIN_SHA256:
        raise ValueError("BalloonSelector main dictionary differs from the audited source")
    main = main.decode("utf-8").replace("\r\n", "\n")
    start = main.index("ShowBalloonView\n{\n")
    end = main.index("\n//-------------------------------------------------------\n// バージョン", start)
    main = main[:start] + NATIVE_VIEW + main[end:]
    main = main.replace("'\\![change,balloon,' + _argv[0] + ']'", "'\\![change,balloon,\"' + REPLACE(_argv[0],'\"','\"\"') + '\"]'")
    files = subprocess.check_output(["git", "-C", str(source), "ls-files", "-z"], text=True).split("\0")
    payload = {}
    for name in files:
        if not name or name.startswith((".github/", ".git")) or name in ("updates.txt", "delete.txt"):
            continue
        path = source / name
        if not path.resolve().is_relative_to(source) or path.is_symlink():
            raise ValueError(f"Unsafe upstream file: {name}")
        payload[name] = path.read_bytes()
    for name in ("descript.txt", "install.txt", "LICENSE", "yaya.dll", "yaya.txt", "system/yaya_plugin2.dic", "readme.txt"):
        if name not in payload:
            raise ValueError(f"Missing required upstream file: {name}")
    payload["yaya_plugin_util.dic"] = util
    payload["yaya_plugin_main.txt"] = main.encode("utf-8")
    descriptor = payload["descript.txt"].decode("utf-8")
    payload["descript.txt"] = ("\n".join(line for line in descriptor.splitlines()
        if line.split(",", 1)[0].strip().lower() != "homeurl") + "\n").encode("utf-8")
    payload["readme.txt"] += ("\n\n" + PORT_NOTE).encode("utf-8")
    payload["Utatane-Port.txt"] = PORT_NOTE.encode("utf-8")
    # Stable metadata keeps repeated local builds byte-identical.
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(payload.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 16, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(build(args.source, args.output))


if __name__ == "__main__":
    main()
