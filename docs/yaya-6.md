# YAYA 6

YAYA 6 系（Tc603-2）の macOS 14 以降向け SHIORI です。YAYA 5 系は別モジュールとして残ります。
ゴースト内の `yaya.dll` に含まれる FileVersion が 6 の場合に使用します。
判定できない場合は、既存の YAYA 5 系を使用します。

ZIP の `yaya-6/lib/libyaya-6.dylib` を `ghost/master/` に置き、`descript.txt` に次を追記すると明示的に選べます。

```text
shiori.macos,libyaya-6.dylib
```

Windows 用の `shiori` 指定は残してください。再配布時は `LICENSES/` も同梱します。
YAYA 6 でハッシュや入れ子の変数を保存すると、YAYA 5 へ戻した際にその変数が崩れます。切り替える前にセーブファイルをバックアップしてください。

通常の `loadu` / `load`・`request`・`unload` で呼び出せます。パス・電文は UTF-8、長さは 32 ビット符号付き整数です。1 プロセスにつき 1 セッションです。

ライセンスは BSD 3-Clause。接続部分は MIT です。出典と固定コミットは ZIP 内の `module.json` に記録しています。
