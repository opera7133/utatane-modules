# YAYA 5

YAYA 5系（Tc574-11）のmacOS 14以降向けSHIORIです。通常はYAYA 6を使い、5系が必要なゴーストでこちらを選んでください。

## 導入と選択

Utataneの「モジュール」→「モジュールカタログ…」からYAYA 5をダウンロードします。「SHIORI読み込み診断」でゴーストが使うSHIORIとして5系を選択し、ゴーストを再読み込みしてください。

## 手動で配置する・ゴーストへ同梱する

ZIPの`yaya/lib/libyaya.dylib`を`ghost/master/`へ置き、`descript.txt`に追記します。

```text
shiori.macos,libyaya.dylib
```

Utatane 0.2.14以降では通常のゴーストにYAYA 6を使います。5系は、この明示指定で使う互換用です。6系で保存した後に5系へ戻す場合は、ゴーストを終了してから導入前の保存ファイルを復元してください。詳しくは[UtataneのSHIORI案内](https://dl.wmsci.com/utatane/docs/support/engines/)を確認してください。

Windows用の`shiori`指定は残してください。再配布時は`LICENSES/`も同梱します。

## 互換範囲

YAYA 5の辞書とmacOS用SAORIに対応します。内蔵SAORIを使うにはUtatane 0.2.17以降が必要です。[内蔵SAORIの案内](https://github.com/opera7133/Utatane/blob/main/Docs/Support/Native-SHIORI.md)

SAORIの配置方法は共通の案内を参照してください。[SAORIの導入](saori.md)
