# YAYA 6

YAYA 6 系（Tc606-5）の macOS 14 以降向け SHIORI です。YAYA 5 系は別モジュールとして残ります。
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

YAYA 6は本流の`600`ブランチを固定コミットで直接参照し、Utatane用の接続・SAORI対応をビルド時に追加します。HTML解析のGumbo（Apache-2.0）と正規表現のDEELXの通知もZIPへ同梱します。


Tc607-2では正規表現エンジンをuka_regexpへ更新しています。パターンの互換差やバックトラック抑制の変更は上流のリリース情報を確認してください。uka_regexpのUnlicenseは配布ZIPに同梱します。

## 内蔵SAORI接続（開発版）

今回のソースから再ビルドしたモジュールと、対応するUtatane開発版を組み合わせると、DLLを配置せずに`internal_system`・`internal_text`・`internal_random`・`internal_data`・`internal_crypto`の対応関数を呼べます。対応関数と非同期通知の仕様は[Utataneの案内](https://github.com/opera7133/Utatane/blob/main/Docs/Support/Native-SHIORI.md)を確認してください。

接続はSHIORIホストと親アプリの専用IPCです。WindowsのWM_COPYDATAによるDirectSSTP、TCP/HTTP経由のSAORI実行には対応していません。既存の公開済みZIPだけでは利用できません。合成した実辞書で同期呼び出し・非同期完了通知をarm64とx86_64で確認しています。実ゴーストの画面操作は未確認です。
