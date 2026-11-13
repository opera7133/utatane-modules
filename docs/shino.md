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

## 互換範囲

忍 0.9.7の辞書で、基本の会話・クリック反応・macOS用SAORIに対応します。Windows固有の操作は対象外です。

共通導入版SAORIの場所を手動で指定する場合は、`UTATANE_SAORI_ROOT`に格納先の絶対パスを設定してください。

再配布時はZIPの`LICENSES/`も含めてください。
