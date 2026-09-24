# Utatane MISAKA Native

美坂の辞書を実行するmacOS 14以降向けのSHIORIです。

## Utataneへ導入

ZIP内の `misaka-native/` を次の場所へ置きます。

```text
~/Library/Application Support/Utatane/NativeShiori/misaka-native/
```

`misaka.ini` を持つゴースト・プラグインで使われます。

## ゴーストへ同梱

ZIP内の `misaka-native/lib/libmisaka.dylib` を `ghost/master/` へ入れ、`descript.txt` に追記します。Windows用の `shiori` 指定はそのまま残します。

```text
shiori.macos,libmisaka.dylib
```

同梱版を優先し、共通導入版のダウンロードは不要です。プラグインではプラグインのフォルダへ入れ、`filename.macos,libmisaka.dylib` と指定します。再配布時はZIP内の `LICENSES/` も含めてください。

Utataneでの変数保存先はApplication Supportです。Windows DLLや暗号化辞書の実行には対応しません。同時に使用できる美坂の配布版は1種類です。異なる版へ切り替える際はUtataneを再起動してください。

通常の入口は `loadu` / `load`・`request`・`unload`。パスと電文はUTF-8、長さは32ビット符号付き整数です。入力はモジュールが、応答は呼び出し側が `free` します。この入口はライブラリごとに1セッションで、保存先は辞書フォルダです。Utataneは内部接続でセッション・保存先・SAORIを管理します。

## ライセンス

MIT License
