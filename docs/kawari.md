# 華和梨

華和梨の辞書を使うゴースト向けの、macOS移植版SHIORIです。UTF-8と従来のShift_JISの辞書を読み込めます。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

ZIP内の`kawari/lib/libkawari.dylib`を`ghost/master/`に置きます。Utataneでは、`kawarirc.kis`または`kawari.ini`があれば既存の`descript.txt`を変更せずに使えます。

他のベースウェアで必要なら`shiori.macos,libkawari.dylib`を追加してください。

## 互換範囲

UTF-8・Shift_JISの辞書、旧`kawari.ini`、macOS用SAORIに対応します。内蔵SAORIにはUtatane 0.2.17以降が必要です。`getproperty` はUtatane 0.2.22以降と華和梨9.2.0-r5以降の組み合わせで使えます。

共通導入版SAORIの場所を手動で指定する場合は、`UTATANE_SAORI_ROOT`に格納先の絶対パスを設定してください。再配布時はZIPの`LICENSES/`を同梱してください。
