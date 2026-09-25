# minato

ZIP内の `minato/lib/libminato.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,minato.dll
```

他のベースウェアで必要なら`shiori.macos,libminato.dylib`を追加してください。

ZIP内の `LICENSES/` も含めて同梱してください。同梱せず共通導入する場合は、`minato/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

辞書は `config.toml` と `talks/main.mnt`、保存先はゴースト内の `save.json` です。SAORIはmacOS用dylibが必要です。台本内の `echo.dll` は同じ場所の `echo.dylib` を読み込みます。

通常のSHIORI入口を使い、文字列はUTF-8です。Utataneではゴーストごとにプロセスを分けて実行します。
