# 偽栞

偽栞の辞書を使うゴースト向けの、macOS用SHIORIです。Windows版を元にした独立実装です。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の`nise-shiori/lib/libniseshiori.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,niseshiori.dll
```

他のベースウェアで必要なら`shiori.macos,libniseshiori.dylib`を追加してください。

開発者向けには、SHIORI/3.0の標準的な呼び出し口（`loadu`・`load`・`request`・`unload`）を用意しています。UTF-8とShift_JISの電文に対応します。同一プロセス内の同時セッションは1つです。

`ai*.txt`と`ai*.dtx`を読み込み、状態を`ghost/master/nise-shiori-state.json`に保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。保存先には書き込み権限が必要です。元のWindows版が持つすべての機能を再現するものではありません。

同梱・再配布時はZIPの`LICENSES/`も確認してください。
