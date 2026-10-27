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
| `libplaywavsound.dylib` | WAVEファイルの非同期再生、`hwnd`、システム音の対応付け |
| `libtotp_saori.dylib` | `keygen`、HMAC-SHA1の`totp`。RFC 6238の既知値で検証 |
| `libxpath.dylib` | `open`・`close`・`get`。文書ID、ノード集合・数値・真偽値・文字列 |
| `libtimebkn.dylib` | `time`・`system`・`tick`・`fromdate`・`local`・`strftime`。`qreki`は非対応 |

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

## PlayWavSound

カタログIDは`playwavsound`、原版の呼び出し名は`PlayWavSound.dll`です。引数なしは400、`hwnd`は204、その他の呼び出しは200でResultに再生受付の成功`1`／失敗`0`を返します。音声の再生終了通知はありません。

第1引数にWAVEファイルのパスを渡します。相対パスはSAORIのロード先フォルダ基準で、Windows形式の区切りと`%変数名%`によるmacOS環境変数の展開に対応します。Windows固有の`%SystemRoot%`などをmacOSへ置き換える機能はありません。通常ファイルかつ64MiB以下のRIFF/WAVEをAVFoundationで再生し、同じモジュールの次の再生で前の音を止めます。アンロード時も停止します。元のWindowsデコーダーと対応コーデックが一致するとは限りません。

`system:SystemAsterisk`→Glass、`SystemDefault`→Funk、`SystemExclamation`・`SystemHand`→Basso、`SystemQuestion`→PopとしてmacOSのシステム音へ対応付けます。大文字小文字は区別しません。その他のWindowsシステム音は`0`です。

パス・成功／失敗・終了処理・UTF-8/Shift_JISの電文と両CPUのABIを自動検証します。ビルド時の検査では音を鳴らさず、実際の音声出力は利用環境で確認してください。

## totp_saori

カタログIDは`totp-saori`、呼び出し名は`totp_saori.dll`です。

- `keygen [, バイト数]`: OSの乱数で鍵を生成し、パディングなしのBase32で返します。既定30バイト、1〜1024バイト。
- `totp, Base32鍵 [, Unix秒 [, 桁数 [, 更新間隔秒]]]`: HMAC-SHA1でコードを生成します。既定は現在時刻・6桁・30秒間隔。桁数は1〜9、間隔は1〜4294967295秒、Unix秒は非負64ビット整数です。

成功は200。不正な引数・Base32・ゼロの間隔は400、乱数生成失敗は500です。コマンド名は原版と同じく小文字。鍵は英字の大小と正しい末尾`=`パディングの有無に対応し、最大8192文字です。秘密鍵を保存・ログ出力しません。引数の省略と空文字は異なり、空の数値引数は400です。

原版のコマンドと引数順を維持した独立実装です。原版ソースには鍵生成・Base32・桁埋めの不具合があるため、その結果や未定義動作は再現しません。Base32は正しい末尾ビットとパディングを検査し、末尾ゼロの鍵バイトを保持します。指定した桁数へゼロ埋めし、2038年以降も扱います。[RFC 6238 Appendix B](https://www.rfc-editor.org/rfc/rfc6238#appendix-B)のSHA-1の6つの既知値を検証します。

## XPath

カタログIDは`xpath`、原版の呼び出し名は`XPath.dll`です。macOSのlibxml2による独立実装で、TinyXPathそのものは同梱しません。

- `open, ファイル名`: XMLを開き、整数の文書IDをResultへ返します。同じパス文字列を再度開くと同じID・読み込み済み文書を再利用します。ファイルの変更を反映するには閉じてから開き直します。
- `close, 文書ID`: 文書を閉じて204。アンロード時はすべての文書を解放します。
- `get, 文書ID, XPath`: ノード集合は各テキストをValue0以降へ返し、ResultにはそれらをSOH（U+0001）で結合します。原版に合わせ、要素は単一のテキスト／CDATAの子を持つ場合のみ対象とし、子要素を含む要素や空要素は飛ばします。属性とテキストノードも扱います。数値・真偽値・文字列はResultとValue0へ同じ値を返し、真偽値は`1`／`0`です。空集合も200です。

無効な引数・文書ID・読み込み失敗は400。式の評価失敗や資源上限は500です。相対ファイルはSAORIのロード先フォルダ基準で、Windows形式の区切りに対応します。環境変数展開は非対応。XML宣言にある文字コードを読み、XPathの文字列はSAORI要求の文字コードからUnicodeへ変換します。

XMLは1文書8MiB・同時32文書・入力合計32MiBまで、式はUTF-8で4096バイトまで。評価は100万操作、選択ノードは8192個、値の合計はUTF-8で2MiBまでです。DTD付き文書、外部実体、XInclude、XQueryの`doc()`等による追加のファイル・ネットワーク取得は対応しません。XPath 1.0を使い、名前空間接頭辞の登録機能はありません。TinyXPathと数値表現・空白処理等の細部まで一致する保証はありません。

## timebkn（通常日時のみ）

カタログIDと呼び出し名は`timebkn`／`timebkn.dll`です。通常の日時処理を独立実装しています。

| 引数 | 結果 |
| --- | --- |
| `time` | 現在のUnix秒 |
| `tick` | OS起動からのミリ秒を32ビット符号なしで返す。約49.7日で折り返す |
| `system` | 上記の折り返し後のミリ秒を1000で割った秒数 |
| `fromdate, 年 [, 月 [, 日 [, 時 [, 分 [, 秒]]]]]` | ローカル日時からUnix秒。月は既定1、日・時・分・秒は0。原版同様に月日等の繰り上がり・繰り下がりと標準時指定を用いる |
| `local [, Unix秒]` | Resultにasctime形式の日時、Value0〜7に年・月・日・時・分・秒・曜日（日曜0）・年内日数（元日0） |
| `strftime, Unix秒, 書式` | macOSのstrftimeによる文字列。Unicodeのリテラルを含む。出力はUTF-8で8191バイトまで |

成功は200。不正な引数・範囲外の日付は400、書式出力の上限超過等は500です。コマンド名は大小を区別しません。日時はmacOSのローカルタイムゾーンで解釈し、年は1〜9999、Unix秒は符号付き64ビットを使います。Windowsの32ビット時刻値・数値文字列の不正入力や書式指定の挙動までは再現しません。Resultの改行はSAORI電文では空白へ置換します。

`qreki`（旧暦・六曜）は501で、**未対応**です。原版のqreki.cppが要求する別の原典QRSAMPの再配布条件を確認できていないため、そのコードを取り込みません。

## 掲載元と次の調査候補

2026-10-27に、[ukatech/csaori](https://github.com/ukatech/csaori/tree/1ddb8c9024bb4716fa3ac25d05c819fad224e459/impl_saori)、[SSPの互換SAORI一覧](https://ukatech.shillest.net/ukadoc-spec/spec/saori-ex/)、[SSPの開発リンク集](https://ukatech.shillest.net/ukadoc-ssp/dev/links/)と[伺かwikiのSAORI分類](https://w.atwiki.jp/ua-ks/pages/31.html)を起点に調査しました。掲載実績を候補選定の基準とし、利用率の実測順位ではありません。

今回の原版ソースはCSAORI commit `1ddb8c9024bb4716fa3ac25d05c819fad224e459`へ固定して取得しました。`impl_saori/PlayWavSound/PlayWavSound.cpp`・`readme.txt`・`license.txt`、`impl_saori/totp_saori/totp_saori.cpp`・`totp.cpp`・`LICENSE`を確認しています。前者はCSAORIのゴースト用／修正BSD条件、後者はWTFPL v2を掲示しています。この配布物へ原版コード・Windows DLLは含めず、独立実装をMITで提供します。

同じ固定コミットの`impl_saori/XPath/XPath.cpp`・`license.txt`、`impl_saori/timebkn/timebkn.cpp`・`qreki.cpp`・`license.txt`も確認しました。両ディレクトリの基本条件はCSAORIのゴースト用／修正BSD条件ですが、旧暦計算には追加の原典条件があります。今回の独立実装へ原版ソースは含めません。`timebkn/readme.txt`は別機能の説明が残っているため、コマンドと返却値は実際のソースを根拠にしています。

| 候補 | 掲載・根拠 | 次に確認すること |
| --- | --- | --- |
| `string`・`cpuusage`・`houchi`・`hanayu` | SSPの互換SAORI一覧。`cpuusage`等は[中文偽春菜Wikiの一覧](https://sikan.moe/ukagaka/%E9%96%8B%E7%99%BC%E6%96%87%E4%BB%B6_SAORI_%E4%BA%BA%E6%A0%BC%E5%A5%97%E4%BB%B6%E5%88%97%E8%A1%A8%20-%20%E4%B8%AD%E6%96%87%E5%81%BD%E6%98%A5%E8%8F%9C%E5%BE%8C%E6%8F%B4%E6%9C%83%20Wiki)にも記載 | 原配布先が到達不能。原版の資料・再配布条件・イベント契約を確定する |
| `timebkn`の`qreki` | CSAORIから別の原典QRSAMPを参照 | 原典の利用条件。2026-10-27時点でVectorの旧配布URLは企業ページへ転送され、条件未確認 |
| `XPath`の追加互換 | 今回は通常のXPath 1.0を対応 | TinyXPathとの細部・配布作品の確認は継続する |
| `KeywordReg` | CSAORIにソースあり | `kenonoke`とは別物。Windows IME依存の読み・漢字変換をどう扱うか |
| `HandUtil` | 中文偽春菜Wikiに記載 | FMO・HWND・SAKURA API等のWindows依存とmacOSへの対応範囲 |

候補への掲載は未実装機能の対応を示しません。原版資料はreadmeの取り違えもあるため、実際のソースと照合します。
