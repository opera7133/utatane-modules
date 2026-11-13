# 里々

里々Unicode版Mc206-5を元にした、macOS 14以降向けのSHIORIです。更新前にゴーストのセーブデータをバックアップしてください。Unicode版はUTF-8で保存するため、旧版に戻したときに文字化けする場合があります。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

里々Unicode版 Mc206-5を元にしたmacOS 14以降向けのSHIORIです。ZIPの`satori/lib/libsatori.dylib`を`ghost/master/`へ置き、`descript.txt`に追記します。

```text
shiori.macos,libsatori.dylib
```

Windows用の`shiori`指定は残してください。再配布時は`LICENSES/`も同梱します。

## 互換範囲

CP932・UTF-8の辞書、従来のセーブデータ、macOS用SAORIに対応します。保存はUTF-8です。旧版との辞書の違いは公式資料で確認できます。[里々Unicode版の変更点](https://ukatech.github.io/satori-docs/other/unicode-changes/)

SAORIの配置方法は共通の案内を参照してください。[SAORIの導入](saori.md)
