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

## 互換範囲

結奈 SecondEdition Unit 10の非暗号化辞書（YDF/1.07）に対応します。基本の会話・イベント・整数の四則演算を使えます。編集機能とSAORIは対象外です。

再配布時はZIPの`LICENSES/`も含めてください。
