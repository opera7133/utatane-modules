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

## 互換範囲

平文と暗号化された偽栞の辞書を読み込み、基本の会話やイベントに対応します。単語間のチェインやSAORIには制限があります。

再配布時はZIPの`LICENSES/`も含めてください。
