# proxy_exと音声メタデータ

macOS 14以降向けの独立実装です。ゴースト名による処理の分岐はありません。
`proxy_ex.dll`を宣言するゴーストから、SAORI BASICの補助プログラムを呼び出せます。

ZIPを`NativeSaori/proxy-ex/`へ展開し、`lib/libproxy_ex.dylib`と`bin/mp3tag`の配置を保ちます。
Utataneの共通SAORI格納先に導入すると、対応するすべてのゴーストで利用できます。
華和梨では、preload時のUTF-8交渉に対応した9.1.0-r3以降を使ってください。

Argument0は実行ファイル、Argument1以降は個々の引数です。シェルによる解釈はしません。
`loadu`で渡されたフォルダとその`saori/`を探し、WindowsのPE実行ファイルは読み飛ばします。
区切りを含まない名前なら、配布パッケージの`bin/`に同名のmacOS用補助プログラムを探します。
この際`.exe`を取り除きます。Windows EXEの実行やPATH検索は行いません。

標準出力の改行は既定で空白へ置換します。`/delim,文字列`で変更できます。
`/charset`はUTF-8（既定）、Shift_JIS、EUC-JP、ISO-2022-JPに対応します。
`hwnd`は何もしません。10秒または標準出力1MiBを超える実行は打ち切ります。

同梱`mp3tag`は独立実装の読み取り専用ヘルパーです。音声出力は行いません。
引数に音声ファイルを1つ指定すると、`Title`、`Artist`、`Album`、`Year`、`Genre`、
`Time`（分:秒）、`Milliseconds`を`名前:値|`形式のUTF-8で返します。
タグがない項目は`Unknown`です。Windows式区切りの絶対パスにも対応します。
対応形式はmacOSのAudioToolbox/AVFoundationに依存し、TagLibSharpと同一ではありません。
日本語のタグは取得できますが、ゴースト自身の画像フォントに日本語の字形がなければ表示できません。

proxy_exの仕様確認元は[公式ソース](https://github.com/ukatech/csaori/tree/1ddb8c9024bb4716fa3ac25d05c819fad224e459/impl_saori/proxy_ex)です。
既存ソースやTagLibSharpのコード・バイナリは配布に含めず、独立実装部分はMITです。
