# minato

minatoの台本を使うゴースト向けの、macOS移植版SHIORIです。配布中の0.4.0は試験版です。更新する場合は、下の互換範囲も確認してください。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の `minato/lib/libminato.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,minato.dll
```

他のベースウェアで必要なら`shiori.macos,libminato.dylib`を追加してください。

ZIP内の `LICENSES/` も含めて同梱してください。同梱せず共通導入する場合は、`minato/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

辞書は `config.toml` と `talks/main.mnt`、保存先はゴースト内の `save.json` です。SAORIはmacOS用dylibが必要です。台本内の `echo.dll` は同じ場所の `echo.dylib` を読み込みます。

## 互換範囲

minato 0.4.0の試験版です。0.2系から更新すると一部の台本の動作が変わります。更新前に台本と保存データをバックアップしてください。[上流の互換性の注意](https://github.com/mizuki-yura/minato/releases/tag/v0.3.0)
