# YAYA

YAYA 5 系（Tc574-9）の macOS 14以降向けSHIORIです。ZIPの`yaya/lib/libyaya.dylib`を`ghost/master/`へ置き、`descript.txt`に追記します。

```text
shiori.macos,libyaya.dylib
```

Utatane 0.2.14以降では通常のゴーストにYAYA 6を使います。5系は、この明示指定で使う互換用です。6系で保存した後に5系へ戻す場合は、ゴーストを終了してから導入前の保存ファイルを復元してください。詳しくは[UtataneのSHIORI案内](https://dl.wmsci.com/utatane/docs/support/engines/)を確認してください。

Windows用の`shiori`指定は残してください。再配布時は`LICENSES/`も同梱します。

通常の`loadu` / `load`・`request`・`unload`で呼び出せます。パス・電文はUTF-8、長さは32ビット符号付き整数。入力はライブラリが、応答は呼び出し側が`free`します。1プロセスにつき1セッションです。

SAORIのWindows DLL指定に対して、同じフォルダの`lib名前.dylib`を読み込みます。共通導入先は`~/Library/Application Support/Utatane/NativeSaori/<ID>/lib/`です。`saori_cpuid`のIDは`saori-cpuid`です。`UTATANE_SAORI_ROOT`で共通導入先を変更できます。辞書側のSAORIフォルダに置く設定・辞書ファイルは、共通導入時もそのまま使います。

[ネイティブSAORIの対応内容](saori.md)も確認してください。

ライセンスはBSD 3-Clause。接続部分はMITです。出典と固定コミットはZIP内の`module.json`に記録しています。

Tc574-9の配布リビジョン2では、空文字列の文字コード変換でMacのメモリ領域外へ書き込む問題に、上流6系と同じ修正を適用しています。
