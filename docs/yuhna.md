# 結奈

結奈の辞書を使うゴースト向けの、macOS用SHIORIです。SecondEdition Unit 10を元にした独立実装です。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の`yuhna/lib/libyuhna.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,yuhna.dll
```

他のベースウェアで必要なら`shiori.macos,libyuhna.dylib`を追加してください。

開発者向けには、SHIORI/3.0の標準的な呼び出し口（`loadu`・`load`・`request`・`unload`）を用意しています。電文はUTF-8とShift_JISに対応します。辞書には`dic.ydf`（YDF/1.07形式）が必要です。

状態は既定で`ghost/master/yuhna-state.json`へ保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。このdylibは結奈SecondEdition Unit 10の独自再実装で、編集機能などすべての機能は再現していません。再配布時はZIPの`LICENSES/`も確認してください。
