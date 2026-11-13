# ネイティブSAORI

ゴーストから呼び出して、音声の再生、クリップボードへのコピー、システム情報の取得などを行う追加モジュールです。macOS 14以降で利用できます。使うSAORIはゴーストの辞書や設定によって決まります。

## Utataneへ導入する

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. ゴーストが必要とするSAORIを選び、ダウンロードします。
3. 「機能」→「復旧操作」→「現在のゴーストを再読み込み」でゴーストを読み込み直し、そのSAORIを使う機能を試します。

手動で導入する場合は、ダウンロードしたZIPを展開し、モジュール名のフォルダを丸ごと次の場所へ置きます。例えばtextcopy2なら、`NativeSaori/textcopy2/lib/libtextcopy2.dylib`という構成になります。

```text
~/Library/Application Support/Utatane/NativeSaori/
```

ゴースト側に設定ファイルや辞書を用意するSAORIもあります。以下の説明と、ゴーストの案内に従って配置してください。

## 同梱

ZIPの`lib/`にあるdylibと`LICENSES/`をゴーストへ含めます。SAORIを置くフォルダは辞書側の設定に合わせてください。SHIORIの`shiori.macos`指定とは別です。

`kenonoke`の`keyword.txt`はdylibと同じフォルダへ置きます。例：

```text
飲み物＝日本酒、酒
場所＝酒場
```

## 互換範囲

| モジュール | できること |
| --- | --- |
| saori-cpuid | macOS・CPU・メモリの情報を取得 |
| kenonoke | `keyword.txt`に沿って語句を分類 |
| textcopy / textcopy2 / clipcopy | 文字列をクリップボードへコピー |
| saori-ip | ローカルIPv4アドレスとホスト名を取得 |
| mciaudior | 音声の再生・ループ・停止 |
| playwavsound | WAVE音声と一部のシステム音を再生 |
| httpc | Web上のデータを取得・保存。非同期通知にはUtatane 0.2.18以降が必要 |
| wmove | ゴーストの位置の取得・移動。対応するベースウェアが必要 |
| totp-saori | ワンタイムパスワードの生成 |
| XPath | XMLからXPath 1.0で値を取得 |
| timebkn | 時刻の取得・変換。旧暦・六曜は対象外 |

[proxy_exと音声メタデータ](proxy-ex.md)は個別の案内を参照してください。
