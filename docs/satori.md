# 里々

里々Unicode版 Mc203-3を元にしたmacOS 14以降向けのSHIORIです。ZIPの`satori/lib/libsatori.dylib`を`ghost/master/`へ置き、`descript.txt`に追記します。

```text
shiori.macos,libsatori.dylib
```

Windows用の`shiori`指定は残してください。再配布時は`LICENSES/`も同梱します。

通常の`loadu` / `load`・`request`・`unload`で呼び出せます。パス・電文はUTF-8、長さは32ビット符号付き整数。入力はライブラリが、応答は呼び出し側が`free`します。1プロセスにつき1セッションです。内部もUnicodeで、絵文字などCP932にない文字も扱えます。

従来のCP932辞書とセーブデータ（暗号化した`.sat`を含む）は読み込めます。UTF-8辞書も自動判定で読み込みます。**更新前にセーブデータをバックアップしてください。** Unicode版はUTF-8で保存するため、旧版へ戻すと文字化けする場合があります。

通常の辞書はそのまま使えますが、完全に同じ挙動ではありません。`（バイト値、n）`はnをUnicodeコードポイントとして1文字を返し、文字列長の比較や括弧展開サイズ制限はバイト数から文字数へ変わります。計算式の`^`や`sprintf`の一部など、旧版の不具合修正で結果が変わる処理もあります。該当する辞書は[公式のACP版との違い](https://ukatech.github.io/satori-docs/other/unicode-changes/)を確認してください。

SAORIのWindows DLL指定に対して、同じフォルダの`lib名前.dylib`を読み込みます。共通導入先は`~/Library/Application Support/Utatane/NativeSaori/<ID>/lib/`です。`saori_cpuid`のIDは`saori-cpuid`です。`UTATANE_SAORI_ROOT`で共通導入先を変更できます。辞書側のSAORIフォルダに置く設定・辞書ファイルは、共通導入時もそのまま使います。

[ネイティブSAORIの対応内容](saori.md)も確認してください。

SAORIへの電文は基本UTF-8です。`GET Version`の応答に`Charset`がないSAORIへは、従来どおりCP932で送信します。

里々本体のライセンスはBSD 2-Clause。接続部分はMITです。正規表現エンジンDEELXは作者が個人・商用利用を無償としています。各出典と通知はZIP内の`LICENSES/`、固定コミットは`module.json`とソースのsubmoduleに記録しています。

配布カタログは本流の版名`Mc203-3`を表示します。更新判定にはUtatane 0.2.14以降を使用してください。旧表記`2.3.2`からの更新も判定できます。
