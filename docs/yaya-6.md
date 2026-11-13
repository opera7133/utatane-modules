# YAYA 6

YAYA 6系（Tc608-3）のmacOS用SHIORIです。この版を使う場合は、先にUtatane本体を0.2.21以降へ更新してください。Utataneは通常、YAYAを使うゴーストに6系を選びます。5系が必要な場合は、別モジュールのYAYA 5を利用できます。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

YAYA 5を使う場合は、そのdylibを配置し、`shiori.macos,libyaya.dylib`を明示指定してください。

ZIP の `yaya-6/lib/libyaya-6.dylib` を `ghost/master/` に置き、`descript.txt` に次を追記すると明示的に選べます。

```text
shiori.macos,libyaya-6.dylib
```

Windows 用の `shiori` 指定は残してください。再配布時は `LICENSES/` も同梱します。
YAYA 6 でハッシュや入れ子の変数を保存すると、YAYA 5 へ戻した際にその変数が崩れます。切り替える前にセーブファイルをバックアップしてください。

## 互換範囲

YAYA 6の辞書とmacOS用SAORIに対応します。ワーカーから本体連携のSAORIを使う処理には制限があります。[内蔵SAORIの案内](https://github.com/opera7133/Utatane/blob/main/Docs/Support/Native-SHIORI.md)

SAORIの配置方法は共通の案内を参照してください。[SAORIの導入](saori.md)
