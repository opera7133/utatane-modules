# 忍

忍の辞書を使うゴースト向けの、macOS用SHIORIです。忍0.9.7を元にした独立実装です。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の`shino/lib/libshino.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,shino.dll
```

他のベースウェアで必要なら`shiori.macos,libshino.dylib`を追加してください。

開発者向けには、SHIORI/3.0の標準的な呼び出し口（`loadu`・`load`・`request`・`unload`）を用意しています。電文はUTF-8とShift_JISに対応します。辞書は`ai*.txt`を読み込みます。

状態は既定で`ghost/master/shino-state.json`へ保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。`%saori`はゴースト直下の`filename.dylib`または`libfilename.dylib`を読み込みます。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibは忍 0.9.7の独自再実装で、元のWindows DLLと完全互換ではありません。再配布時はZIPの`LICENSES/`も確認してください。
