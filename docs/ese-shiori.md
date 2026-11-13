# ese-shiori

ese-shioriの辞書を使うゴースト向けの、macOS用SHIORIです。Windows版3.03を元にした独立実装です。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の`ese-shiori/lib/libese-shiori.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,ese-shiori.dll
```

他のベースウェアで必要なら`shiori.macos,libese-shiori.dylib`を追加してください。

## 互換範囲

ese-shiori 3.03の平文・難読化辞書で基本の会話やイベントを扱います。SAORIと旧SHIORI/2.x電文は対象外です。

再配布時はZIPの`LICENSES/`も含めてください。
