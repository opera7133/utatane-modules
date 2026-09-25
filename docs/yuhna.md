# 結奈 (Native)

ZIP内の`yuhna/lib/libyuhna.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,yuhna.dll
```

他のベースウェアで必要なら`shiori.macos,libyuhna.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応します。辞書には`dic.ydf`（YDF/1.07形式）が必要です。

状態は既定で`ghost/master/yuhna-state.json`へ保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。このdylibは結奈SecondEdition Unit 10の独自再実装で、編集機能などすべての機能は再現していません。再配布時はZIPの`LICENSES/`も確認してください。
