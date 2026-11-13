# proxy_exと音声メタデータ

ゴーストからmacOS用の補助プログラムを呼び出すためのSAORIです。macOS 14以降で利用できます。音声ファイルの曲名や再生時間を取得する`mp3tag`も付属しています。
`proxy_ex.dll`を宣言するゴーストから、SAORI BASICの補助プログラムを呼び出せます。

## 導入する

Utataneの「モジュール」→「モジュールカタログ…」からproxy_exをダウンロードし、ゴーストを再読み込みします。手動の場合はZIPを展開し、`proxy-ex/`フォルダを`~/Library/Application Support/Utatane/NativeSaori/`へ置いてください。`lib/libproxy_ex.dylib`と`bin/mp3tag`は、ZIP内のフォルダ構成を保って配置します。
Utataneの共通SAORI格納先に導入すると、対応するすべてのゴーストで利用できます。
華和梨では、preload時のUTF-8交渉に対応した9.1.0-r3以降を使ってください。

## 互換範囲

macOS用の補助プログラムを呼び出せます。同梱の`mp3tag`は曲名・アーティスト名・再生時間などを読み取ります。Windows用の実行ファイルは対象外です。
