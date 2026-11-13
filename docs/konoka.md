# 此栞（Konoka）

此栞の公開技術メモと、回収できたカスタム版DLLの動作を元にしたmacOS用SHIORIです。0.2.0-r1は部分互換の試験版です。

## Utataneで使う

1. 「モジュール」→「モジュールカタログ…」で此栞を導入します。
2. 「機能」→「復旧操作」→「現在のゴーストを再読み込み」で読み込み直します。
3. 「SHIORI読み込み診断」で、此栞のNative版が選ばれたことを確認します。

配布カタログへの公開後に選択できます。手動で試す場合は、ZIPの`konoka/lib/libkonoka.dylib`をゴーストの`ghost/master/`へ置き、`descript.txt`に次を追加します。`LICENSES/`も同梱してください。

```text
shiori.macos,libkonoka.dylib
```

設定は`konoka.ini`、Windows用DLLと同名の`.ini`、`ks_cfg.txt`の順で探します。設定で`ai.txt`を指定していて実体が`ai.xdc`または`ai.xdi`だけの場合も読み込めます。辞書はUTF-8またはCP932です。

## 互換範囲

辞書・会話・TeachBoxに部分対応します。XDI・XDC形式の辞書を読み込めます。原作の保存データは初回に取り込み、以後はNative版の保存を使います。チェイン会話とSAORIは対象外です。
