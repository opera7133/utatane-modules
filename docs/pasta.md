# pasta

Pastaスクリプトを使うゴースト向けの、macOS移植版SHIORIです。LuaJITと標準スクリプトも配布物に含まれています。更新する場合は、下の互換範囲を確認してください。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の `pasta/lib/libpasta.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,pasta.dll
```

他のベースウェアで必要なら`shiori.macos,libpasta.dylib`を追加してください。

`LICENSES/` も含めて同梱してください。共通導入の場合は、ZIP内の `pasta/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

## 互換範囲

Pastaの辞書に対応し、LuaJITと標準スクリプトを同梱します。Windows専用の拡張は対象外です。

0.4.2以前の保存形式は引き継げません。更新前にゴースト内の `profile/pasta/save/` をバックアップしてください。0.5.0以降は一部の辞書の解釈が変わります。[上流の移行案内](https://github.com/ekicyou/pasta/releases/tag/v0.5.0)
