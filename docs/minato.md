# minato

ZIP内の `minato/lib/libminato.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,minato.dll
```

他のベースウェアで必要なら`shiori.macos,libminato.dylib`を追加してください。

ZIP内の `LICENSES/` も含めて同梱してください。同梱せず共通導入する場合は、`minato/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

辞書は `config.toml` と `talks/main.mnt`、保存先はゴースト内の `save.json` です。SAORIはmacOS用dylibが必要です。台本内の `echo.dll` は同じ場所の `echo.dylib` を読み込みます。

通常のSHIORI入口を使い、文字列はUTF-8です。Utataneではゴーストごとにプロセスを分けて実行します。

今回の配布元は[上流0.4.0（pre-release）](https://github.com/mizuki-yura/minato/releases/tag/v0.4.0)です。macOS版の応答も上流の文字コード付与処理へ統一し、UTF-8の本文とCharsetヘッダが一致するようにしています。

## 0.2.2から0.4.0への更新

**引き続き試験版です。0.3.0をまたぐ更新には互換差があります。** 呼び出した関数・トークから呼び出し元の`let`変数は見えず、代入しても呼び出し元の変数は変わりません。必要な値は引数で渡すか`global`へ移してください。`null`・`true`・`false`も変数名等には使えません。更新前にゴーストと`save.json`をバックアップし、上流の`minato_check`で台本を確認してください。詳細は[0.3.0の互換性の注意](https://github.com/mizuki-yura/minato/releases/tag/v0.3.0)を参照してください。

0.4.0では`pick`・`shuffle`・`draw`・`talk_count`を追加しました。`draw`は渡した変数の配列を書き換えます。`draw`の引数・条件式中での使用は静的チェックでも調べられます。0.4.0単独の「互換性変更なし」は、0.2.2からの更新全体には当てはまりません。
