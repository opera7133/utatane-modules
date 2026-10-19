# minato

ZIP内の `minato/lib/libminato.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,minato.dll
```

他のベースウェアで必要なら`shiori.macos,libminato.dylib`を追加してください。

ZIP内の `LICENSES/` も含めて同梱してください。同梱せず共通導入する場合は、`minato/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

辞書は `config.toml` と `talks/main.mnt`、保存先はゴースト内の `save.json` です。SAORIはmacOS用dylibが必要です。台本内の `echo.dll` は同じ場所の `echo.dylib` を読み込みます。

通常のSHIORI入口を使い、文字列はUTF-8です。Utataneではゴーストごとにプロセスを分けて実行します。

今回の配布元は[上流0.2.0（pre-release）](https://github.com/mizuki-yura/minato/releases/tag/v0.2.0)です。macOS版の応答も上流の文字コード付与処理へ統一し、UTF-8の本文とCharsetヘッダが一致するようにしています。
