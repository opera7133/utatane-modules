# ese-shiori (Native)

ZIP内の`ese-shiori/lib/libese-shiori.dylib`を`ghost/master/`に置き、`descript.txt`に次を指定します。

```text
shiori,ese-shiori.dll
shiori.macos,libese-shiori.dylib
```

SHIORI/3.0の`loadu`・`load`・`request`・`unload`で読み込めます。電文はUTF-8・Shift_JIS・EUC-KRに対応します。辞書には`eseai.ini`と`eseai_*.txt`または`.dic`が必要です。

状態は既定で`ghost/master/ese-shiori-state.json`へ保存します。ベースウェアから`ESE_SHIORI_STATE_PATH`に絶対パスを渡すと保存先を変更できます。`$WRITEFILE`の出力は保存先と同じ親フォルダの`ese-shiori-files/`に置きます。

このdylibはWindows版ese-shiori 3.03の独自再実装であり、すべての辞書機能や旧SHIORI/2.x電文との互換性は保証しません。再配布時はZIPの`LICENSES/`も確認してください。
