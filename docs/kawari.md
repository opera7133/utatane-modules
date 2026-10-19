# 華和梨

ZIP内の`kawari/lib/libkawari.dylib`を`ghost/master/`に置きます。Utataneでは、`kawarirc.kis`または`kawari.ini`があれば既存の`descript.txt`を変更せずに使えます。

他のベースウェアで必要なら`shiori.macos,libkawari.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応し、辞書はUTF-8・従来のShift_JIS形式を読み込みます。内部とファイルパスはUnicodeで扱います。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibには華和梨のmacOS向けC++移植を含みます。元のWindows版の全機能との互換性は保証しません。再配布時はZIPの`LICENSES/`を同梱してください。

9.1.0の配布リビジョン2では、ファイル選択とドロップのパスを辞書向けのWindows式区切りで渡し、絶対パスをmacOSのパスへ正規化します。`isexist`はOSの存在判定を使い、濁点の結合・分解形式が違っても同じファイルを認識します。日本語・空白・絵文字入りのファイル名と、CLDSP2+のimport・MP3ドロップによるプレイリスト追加を自動テストしています。旧イベント`OnFileDropEx`へのフォールバックには、対応するUtatane本体も必要です。ID3タグ取得用のWindows EXE、UTF-8プレイリスト用EXE、実際のマウス操作はこの確認に含みません。

上流の`utatane-unicode`ブランチ（`5778bafb72f344e405192d91f372e4d3d063656b`）と、その固定済み`uka_regexp`を使用します。ゴースト名による特別処理はありません。共通導入した同じdylibをすべての華和梨ゴーストで利用できます。
