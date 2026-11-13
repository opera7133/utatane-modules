# kagari

Luaを使うSHIORI「kagari」のmacOS移植版です。macOS 14以降で利用でき、Lua 5.4も配布物に含まれています。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

### 共通導入

ZIP内の `kagari/` を `~/Library/Application Support/Utatane/NativeShiori/` へ置きます。

### ゴーストへの同梱

ZIP内の `kagari/lib/` にある `libkagari.dylib` と `liblua5.4.dylib` を `ghost/master/` へ入れます。`descript.txt` の指定はWindows版と共通です。

```text
shiori,kagari.dll
```

Utataneは同梱版を共通導入版より優先します。macOSでの実行にWindows DLLは不要です。kagari専用ABIを使うため、汎用dylib用の `shiori.macos` は指定しません。

`libkagari.dylib` と `liblua5.4.dylib` は同じフォルダに保ち、再配布時は `LICENSES/` を含めてください。

開発時に別の配置を使う場合は、Utataneの起動環境で `UTATANE_KAGARI_MODULE` にdylibの絶対パスを指定します。

## 互換範囲

Lua 5.4を使うkagariの辞書に対応します。Windows用の拡張は対象外です。
