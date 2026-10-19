# 華和梨

ZIP内の`kawari/lib/libkawari.dylib`を`ghost/master/`に置きます。Utataneでは、`kawarirc.kis`または`kawari.ini`があれば既存の`descript.txt`を変更せずに使えます。

他のベースウェアで必要なら`shiori.macos,libkawari.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応し、辞書は華和梨のShift_JIS形式を読み込みます。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibには華和梨のmacOS向けC++移植を含みます。元のWindows版の全機能との互換性は保証しません。再配布時はZIPの`LICENSES/`を同梱してください。


配布版は[ukatech/kawari 9.1.0](https://github.com/ukatech/kawari/releases/tag/v9.1.0)を基準にしています。内部文字列はUnicodeで、UTF-8辞書・絵文字を含むパス・`lambda`・新しい正規表現コマンドを利用できます。UTF-8辞書はBOM付きで保存すると文字コードを明示できます。従来のShift_JIS辞書と`kawari.ini`の互換変換も維持しています。

macOS用フォークにはNative SAORIへの接続フックと、macOSのiconvに合わせた文字コード変換の修正を残しています。正規表現エンジンuka_regexpのUnlicenseもZIPに同梱します。Windowsの本体内蔵モジュールをDirectSSTPで呼ぶ機能などは、Utataneでの対応を意味しません。
