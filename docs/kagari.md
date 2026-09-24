# kagari

[Tatakinov/kagari_shiori](https://github.com/Tatakinov/kagari_shiori)の[macOS移植版](https://github.com/opera7133/kagari_shiori)。macOS 14以降、Lua 5.4に対応しています。

## 共通導入

ZIP内の `kagari/` を `~/Library/Application Support/Utatane/NativeShiori/` へ置きます。

## ゴーストへの同梱

ZIP内の `kagari/lib/` にある `libkagari.dylib` と `liblua5.4.dylib` を `ghost/master/` へ入れます。`descript.txt` の指定はWindows版と共通です。

```text
shiori,kagari.dll
```

Utataneは同梱版を共通導入版より優先します。macOSでの実行にWindows DLLは不要です。kagari専用ABIを使うため、汎用dylib用の `shiori.macos` は指定しません。

`libkagari.dylib` と `liblua5.4.dylib` は同じフォルダに保ち、再配布時は `LICENSES/` を含めてください。Windows用SAORIやDLLは直接実行できません。

開発時に別の配置を使う場合は、Utataneの起動環境で `UTATANE_KAGARI_MODULE` にdylibの絶対パスを指定します。ソースの版は `module.json`、依存の版は `dependencies.json` に記録しています。
