# YAYA 6

YAYA 6 系（Tc605-1）の macOS 14 以降向け SHIORI です。YAYA 5 系は別モジュールとして残ります。
Utatane 0.2.14以降では、DLLの版情報に関係なくYAYA 6を既定で使用します。
YAYA 5へは自動で切り戻しません。5系を使う場合は、そのdylibを配置し、`shiori.macos,libyaya.dylib`を明示指定してください。

ZIP の `yaya-6/lib/libyaya-6.dylib` を `ghost/master/` に置き、`descript.txt` に次を追記すると明示的に選べます。

```text
shiori.macos,libyaya-6.dylib
```

Windows 用の `shiori` 指定は残してください。再配布時は `LICENSES/` も同梱します。
YAYA 6 でハッシュや入れ子の変数を保存すると、YAYA 5 へ戻した際にその変数が崩れます。切り替える前にセーブファイルをバックアップしてください。

通常の `loadu` / `load`・`request`・`unload` で呼び出せます。パス・電文は UTF-8、長さは 32 ビット符号付き整数です。1 プロセスにつき 1 セッションです。

ライセンスは BSD 3-Clause。接続部分は MIT です。出典と固定コミットは ZIP 内の `module.json` に記録しています。

YAYA 6は本流の`600`ブランチを固定コミットで直接参照し、Utatane用の接続・SAORI対応をビルド時に追加します。Tc605-1後の上流Macビルド修正も含みます。HTML解析のGumbo（Apache-2.0）と正規表現のDEELXの通知もZIPへ同梱します。
