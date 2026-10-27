# 灯 (Native)

ZIP内の`akari/lib/libakari.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,akari.dll
```

他のベースウェアで必要なら`shiori.macos,libakari.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応します。`.txt`と`.azr`の辞書を読み込みます。

変数は既定で`ghost/master/akari-vars.json`へ保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。灯のSAORI関数はゴースト直下の`filename.dylib`または`libfilename.dylib`を読み込みます。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibは灯 2.003の独自再実装で、元のWindows DLLと完全互換ではありません。再配布時はZIPの`LICENSES/`も確認してください。

## PLUGIN/2.0

r5以降は通常のdylib入口から`GET/NOTIFY PLUGIN/2.0`を受け付け、AZRのプラグイン処理へ配送します。r4以前はこの入口がSHIORI/3.0に限定されていたため、辞書のプラグイン処理があっても外部モジュール経由では実行できませんでした。終了時にはプラグインの`unload`（なければ`unloadPlugin`）を一度だけ実行し、保存します。

画像付きメニューのロード・表示・キャンセルを実辞書の一時コピーで確認します。外部サービス認証・投稿・独自Windows SAORIの全動作を確認した意味ではありません。
