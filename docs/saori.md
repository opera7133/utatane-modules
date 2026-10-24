# ネイティブSAORI

macOS用の独立したSAORIライブラリです。macOS 14以降で使えます。

| ライブラリ | 対応内容 |
| --- | --- |
| `libsaori_cpuid.dylib` | `os.*`、`cpu.*`、`mem.*`の一部。macOSの情報を返します |
| `libkenonoke.dylib` | `GETKEYWORD`。同じフォルダの`keyword.txt`で語句を分類します |
| `libtextcopy2.dylib` | Argument0をクリップボードへコピー。Argument1が`1`ならコピーした文字列を返します |
| `libmciaudior.dylib` | `load`、`play`、`loop`、`stop`による音声再生 |
| `libproxy_ex.dylib` | SAORI BASICの実行と標準出力の取得。[音声メタデータヘルパーを同梱](proxy-ex.md) |
| `libwmove.dylib` | `GET_POSITION`、`GET_DESKTOP_SIZE`、`MOVETO`、`MOVETO_INSIDE`。ホストとのウィンドウ接続が必要です |

CPUクロックなど取得しない項目は`0`、メモリ値は搭載容量です。Windows版とすべての値・機能が一致するわけではありません。`wmove`は接続がない場合、実行要求に`501 Not Implemented`を返します。

## 同梱

ZIPの`lib/`にあるdylibと`LICENSES/`をゴーストへ含めます。SAORIを置くフォルダは辞書側の設定に合わせてください。SHIORIの`shiori.macos`指定とは別です。

`kenonoke`の`keyword.txt`はdylibと同じフォルダへ置きます。例：

```text
飲み物＝日本酒、酒
場所＝酒場
```

`mciaudior`の相対音声パスは、`loadu`で渡されたフォルダを基準にします。

## 呼び出し

入口は`loadu` / `load`、`request`、`unload`。パスはUTF-8、長さは32ビット符号付き整数です。入力はライブラリが、応答は呼び出し側が`free`します。同じライブラリで同時に使えるセッションは1つです。

電文はSAORI/1.0の`GET Version`と`EXECUTE`に対応します。`Charset`には`UTF-8`か`Shift_JIS`を指定します。省略時はShift_JISです。応答の文字コードは要求に合わせます。

独自実装のライセンスはMITです。


## httpc

`httpc.dll`用の共通モジュールは`libhttpc.dylib`です。次の同期処理に対応します。

- 引数なし: 現在のネットワーク到達可能性を`1`/`0`で返す。個別サイトへの接続成功を保証しない。
- URLのみ: HTTP/HTTPSで取得した本文を文字列として返す。改行とNULは除去する。
- URL、保存先: バイナリのまま保存し、成功`1`/失敗`0`を返す。相対保存先はSAORIの配置フォルダ基準。
- URL、開始文字列、終了文字列: 囲まれた部分を返す。同じ引数で続けて呼ぶと次の範囲へ進む。

文字列取得ではURLの前に`euc`/`jis`/`sjis`/`utf-8`/`utf-16be`/`utf-16le`を指定できます。
元のhttpcの配布物に含まれるreadmeも確認してください。
`bg`によるOnHttpcNotify、HTMLタグ変換、Windowsのプロキシ設定継承は未対応です。
応答は32MBまで、取得は最大約30秒です。大きなファイルの取得や常用の非同期通信には
ベースウェアのHTTP命令を使ってください。保存先を指定した失敗は既存ファイルを上書きしません。
