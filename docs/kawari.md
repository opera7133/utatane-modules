# 華和梨

ZIP内の`kawari/lib/libkawari.dylib`を`ghost/master/`に置きます。Utataneでは、`kawarirc.kis`または`kawari.ini`があれば既存の`descript.txt`を変更せずに使えます。

他のベースウェアで必要なら`shiori.macos,libkawari.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応し、辞書はUTF-8・従来のShift_JIS形式を読み込みます。内部とファイルパスはUnicodeで扱います。共通導入版SAORIを使う場合は`UTATANE_SAORI_ROOT`に、`<名前>/lib/lib<名前>.dylib`を含むフォルダの絶対パスを指定してください。

このdylibには華和梨のmacOS向けC++移植を含みます。元のWindows版の全機能との互換性は保証しません。再配布時はZIPの`LICENSES/`を同梱してください。


配布版は[ukatech/kawari 9.1.0](https://github.com/ukatech/kawari/releases/tag/v9.1.0)を基準にしています。内部文字列はUnicodeで、UTF-8辞書・絵文字を含むパス・`lambda`・新しい正規表現コマンドを利用できます。UTF-8辞書はBOM付きで保存すると文字コードを明示できます。従来のShift_JIS辞書と`kawari.ini`の互換変換も維持しています。

macOS用フォークにはNative SAORIへの接続フックと、macOSのiconvに合わせた文字コード変換の修正を残しています。正規表現エンジンuka_regexpのUnlicenseもZIPに同梱します。Windowsの本体内蔵モジュールをDirectSSTPで呼ぶ機能などは、Utataneでの対応を意味しません。
9.1.0の配布リビジョン2では、ファイル選択とドロップのパスを辞書向けのWindows式区切りで渡し、絶対パスをmacOSのパスへ正規化します。`isexist`はOSの存在判定を使い、濁点の結合・分解形式が違っても同じファイルを認識します。日本語・空白・絵文字入りのファイル名と、CLDSP2+のimport・MP3ドロップによるプレイリスト追加を自動テストしています。旧イベント`OnFileDropEx`へのフォールバックには、対応するUtatane本体も必要です。ID3タグ取得用のWindows EXE、UTF-8プレイリスト用EXE、実際のマウス操作はこの確認に含みません。

上流の`utatane-unicode`ブランチ（`5778bafb72f344e405192d91f372e4d3d063656b`）と、その固定済み`uka_regexp`を使用します。ゴースト名による特別処理はありません。共通導入した同じdylibをすべての華和梨ゴーストで利用できます。

9.1.0-r3ではpreloadするSAORIのUTF-8交渉を辞書ロード時から接続し、日本語の分解文字や絵文字を含む引数を維持します。共通SAORIのカタログIDはアンダースコアをハイフンへ正規化して検索します。

## 内蔵SAORI接続

9.1.0-r4以降とUtatane 0.2.17以降を組み合わせると、DLLを配置せずに`internal_system`・`internal_text`・`internal_random`・`internal_data`・`internal_crypto`の対応関数を呼べます。対応関数と非同期通知の仕様は[Utataneの案内](https://github.com/opera7133/Utatane/blob/main/Docs/Support/Native-SHIORI.md)を確認してください。

接続はSHIORIホストと親アプリの専用IPCです。WindowsのWM_COPYDATAによるDirectSSTP、TCP/HTTP経由のSAORI実行には対応していません。以前の配布リビジョンでは利用できません。共通導入版を更新した後、起動中のゴーストを再読み込みしてください。合成した実辞書で同期呼び出し・非同期完了通知をarm64とx86_64で確認しています。実ゴーストの画面操作は未確認です。
