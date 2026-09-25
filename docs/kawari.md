# 華和梨

ZIP内の`kawari/lib/libkawari.dylib`を`ghost/master/`に置きます。Utataneでは、`kawarirc.kis`または`kawari.ini`があれば既存の`descript.txt`を変更せずに使えます。

他のベースウェアで必要なら`shiori.macos,libkawari.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応し、辞書は華和梨のShift_JIS形式を読み込みます。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibには華和梨のmacOS向けC++移植を含みます。元のWindows版の全機能との互換性は保証しません。再配布時はZIPの`LICENSES/`を同梱してください。
