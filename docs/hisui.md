# 翡翠 (Native)

ZIP内の`hisui/lib/libhisui.dylib`を`ghost/master/`に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,hisui.dll
```

他のベースウェアで必要なら`shiori.macos,libhisui.dylib`を追加してください。

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8とShift_JISに対応します。辞書と設定には`.tlk`・`.mem`、`hisuiconf.xml`または`hisui_preference.def`を使います。

状態は既定で`ghost/master/hisui-state.json`へ保存します。ベースウェアから`UTATANE_GHOST_STATE_DIR`に絶対パスを渡すと、そのフォルダに保存します。このdylibは翡翠 phase00.20の独自再実装で、元のWindows DLLと完全互換ではありません。再配布時はZIPの`LICENSES/`も確認してください。
