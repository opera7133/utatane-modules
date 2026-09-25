# 偽栞

ZIP内の`nise-shiori/lib/libniseshiori.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,niseshiori.dll
```

他のベースウェアで必要なら`shiori.macos,libniseshiori.dylib`を追加してください。

通常のSHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。UTF-8とShift_JISの電文に対応します。同一プロセス内の同時セッションは1つです。

`ai*.txt`と`ai*.dtx`を読み込み、状態を`ghost/master/nise-shiori-state.json`に保存します。ベースウェア側で`NISESHIORI_STATE_PATH`に絶対パスを指定すれば保存先を変更できます。保存先には書き込み権限が必要です。元のWindows版が持つすべての機能を再現するものではありません。

同梱・再配布時はZIPの`LICENSES/`も確認してください。
