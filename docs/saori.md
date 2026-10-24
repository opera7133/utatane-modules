# ネイティブSAORI

macOS用の独立したSAORIライブラリです。macOS 14以降で使えます。

| ライブラリ | 対応内容 |
| --- | --- |
| `libsaori_cpuid.dylib` | `os.*`、`cpu.*`、`mem.*`の一部。macOSの情報を返します |
| `libkenonoke.dylib` | `GETKEYWORD`。同じフォルダの`keyword.txt`で語句を分類します |
| `libtextcopy.dylib` / `libtextcopy2.dylib` | Argument0をコピー。Argument1が数値で非ゼロなら元の文字列を返す。Argument2の区切りはコピー先で改行へ置換 |
| `libclipcopy.dylib` | 全引数を改行で結合し、文字列中の`\n`も改行へ変換してコピー |
| `libsaori_ip.dylib` | `GetLocalIP`・`GetLocalHostname`。`GetInternetIP`は非対応（501） |
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
- URL、開始文字列、終了文字列: 囲まれた部分を先頭から最大254件返す。最初の一致はResult、残りはValue0以降。呼び出すたびに再取得し、先頭から調べる。

文字列取得ではURLの前に`euc`/`jis`/`sjis`/`utf-8`/`utf-16be`/`utf-16le`を指定できます。
元のhttpcの配布物に含まれるreadmeも確認してください。
httpc 0.1.0-r4とUtatane 0.2.18以降の本体では、`bg`、識別子、通常の引数の順で非同期実行できます。
例: `bg`、`取得1`、`https://example.com/data.txt`。
受付時は空の結果を返し、呼び出したゴースト・プラグインへ`OnHttpcNotify`を送ります。
Reference0は識別子、Reference1は`-`、Reference2は上記の最初の結果です。複数の抽出結果はReference3以降へ返します。
原作readmeではReference1が空欄ですが、実際のソースに合わせて`-`としています。
失敗時は文字列取得・抽出なら空文字、ファイル保存なら`0`を通知します。
Utataneの通常ネイティブホストへの専用接続を使うため、本体とモジュールの両方を更新してください。
その他のホストでの`bg`は利用できず、同期呼び出しのみです。華和梨を使う場合は9.1.0-r5以降も導入してください。
古い華和梨では、元のWindows DLLがないhttpcなどを内蔵機能と誤認する場合があります。
YAYA 5/6・里々は、この非同期接続のための個別更新は不要です。

ゴーストの終了・再読み込み・SAORIのアンロード時は通信を取り消し、保留中の通知も破棄します。
受付はホストごとに64件まで、処理は全ホスト共通の2〜4ワーカーで行います。
応答は32MB、非同期の文字列結果はUTF-8で2MBまで、取得は最大約30秒です。
httpc 0.1.0-r5ではURLの前に`erase_tag`・`translate_tag`を文字コード指定と並べて指定できます。両方ある場合は`translate_tag`が優先です。`bg`では識別子の後へ置き、Utatane 0.2.18以降の本体も更新してください。
`erase_tag`は`<...>`を除去します。`translate_tag`は原作の簡易変換に合わせ、`br`・`p`・`/tr`・`/li`を改行、`hr`を水平線、`a href`をリンク、`img alt`を代替テキストにします。`&nbsp;`・`&lt;`・`&gt;`・`&amp;`・`&copy;`も変換します。HTML全体の解釈・CSS・スクリプト実行は行いません。原作の半角48桁換算・120行の切り詰めも適用します。保存モードはバイト列のままです。
Windowsのプロキシ設定継承は未対応です。
大きなファイルの取得にはベースウェアのHTTP命令を使ってください。
保存先を指定した失敗は既存ファイルを上書きしません。

## 通常SAORIの診断

Utatane 0.2.18以降の開発用パレットで「通常SAORIの呼び出しを記録」をオンにすると、選択したdylib、呼び出し元、ロード・呼び出し・アンロードの状態、所要時間、応答バイト数を確認できます。引数・本文は記録せず、初期状態はオフです。
SHIORI内部からの呼び出しには、YAYA 5/6 r3、里々Mc205-5-r1、華和梨9.2.0-r1、忍・灯r3以降が必要です。通常のSHIORI/SAORI ABIは変わらず、他のホストで診断接続がなければ何も送信しません。Wine内のWindows SHIORIが直接読み込むDLLの内部呼び出しは対象外です。

## 追加の互換SAORI

`clipcopy`・`textcopy`・`saori-ip`は、SSPが互換機能を持つ従来SAORIを起点にした追加です。利用率の順位を表すものではありません。
引数は[CSAORIの公開ソース](https://github.com/ukatech/csaori/tree/1ddb8c9024bb4716fa3ac25d05c819fad224e459/impl_saori)のclipcopy・textcopy2・saori_ip実装を確認し、macOSの機能で独立実装しています。原作のソース・Windowsバイナリは同梱しません。これらの独立実装のライセンスはMITです。

`clipcopy`は引数がなければ400、成功は200（結果なし）。`textcopy`とtextcopy2 r6は空の第1引数を400にし、返却指定なしの成功は204、返却指定ありは200で元の第1引数を返します。コピー先の改行はCRLFで、macOSのUnicodeクリップボードへ書き込みます。第3引数が空なら置換しません。

`saori-ip`のカタログIDはハイフン、dylib名は`libsaori_ip.dylib`です。`saori_ip.dll`と原作の配布名`ip.dll`に対応します。`GetLocalIP`は有効な非ループバックIPv4の先頭、`GetLocalHostname`はOSのホスト名です。取得できない場合は500。複数NICの選択はWindowsと一致するとは限りません。原作の`GetInternetIP`は外部HTTPサービスを利用しますが、この互換実装では501を返します。外部へのIP照会は行いません。

共有配置の名前解決にはYAYA 5/6 r4、里々Mc205-5-r2、華和梨9.2.0-r2、忍・灯r4以降を使ってください。原版Windows DLLを使う場合はWineの設定が必要です。
