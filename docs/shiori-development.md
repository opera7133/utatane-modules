# SHIORIのmacOS対応

dylibとして読み込む方法と、SHIOLINKで外部プロセスにつなぐ方法があります。Windows用DLLの改名だけでは対応できません。C/C++やRust等の実装はmacOS向けにビルドし、Windows APIへの依存も置き換えます。

## WindowsとmacOSを同じゴーストで配布する

両方のライブラリを `ghost/master` に含め、`descript.txt` で指定します。

```text
shiori,example.dll
shiori.macos,libexample.dylib
```

Utataneは `shiori.macos` を優先します。対応するSHIORIの同梱版が破損している場合は、設定に従って同じSHIORIの共通導入版を試します。DLLの同梱はmacOSでの実行には不要です。依存dylibも含め、`@loader_path` 等で配置先から相対参照できるようにしてください。プラグインは同じ考え方で `filename` / `filename.macos` を指定します。

[美坂](misaka.md)・[minato](minato.md)・[pasta](pasta.md)・[kagari](kagari.md)の配布版を使う場合は各ページの配置に従ってください。kagari・蒼空は専用ABIを使います。

## 通常のdylibの入口

C++では `extern "C"` を付けます。他の言語も同じC互換の型と所有権に合わせます。

```c
#include <stdint.h>
int32_t loadu(void *directory, int32_t length);
int32_t unload(void);
void *request(void *message, int32_t *length);
```

- `loadu` がない場合は同じ型の `load` を使います。UTF-8のmasterパスを長さ付きで受け取り、非0で成功を返します。
- `request` はUTF-8の要求を受け取ります。`*length` を応答のバイト数へ書き換え、応答バッファを返します。NULLは失敗です。
- `unload` は保存・終了処理を行い、非0で成功を返します。`OnClose` の終了会話とは別です。
- 入力はモジュールが、応答はホストが `free` します。入力のNUL終端は保証されません。応答に静的領域や `new[]` の領域を返さないでください。

Utataneは通常のSHIORIをゴーストごとの子プロセスで実行します。作業ディレクトリはmasterですが、ファイル参照には渡された絶対パスを使ってください。異常終了したセッションへの要求は再送しません。

## 電文

次の例の改行はCRLF、末尾は空行です。長さは文字数ではなくバイト数です。

```text
GET SHIORI/3.0
Charset: UTF-8
Sender: Utatane
SecurityLevel: local
ID: OnBoot

```

```text
SHIORI/3.0 200 OK
Charset: UTF-8
Value: \0起動しました。\e

```

会話がない場合は204を返せます。GETだけでなくNOTIFY、未知のイベント・ヘッダーも受け取れるようにします。応答は約8 MiBまで。会話内の改行はSakuraScriptの `\n` を使います。

[SHIORIイベント](https://github.com/opera7133/utatane/blob/main/Docs/Reference/UKADOC-SHIORI-Event-Compatibility.md)と[SakuraScript](https://github.com/opera7133/utatane/blob/main/Docs/Reference/UKADOC-SakuraScript-Compatibility.md)の対応はUtatane側の資料を参照してください。

## ビルドと確認

Cの例です。macOSのXcode開発ツール、またはGitHub ActionsのmacOS runnerで実行します。

```sh
clang -dynamiclib -arch arm64 -arch x86_64 example.c -o libexample.dylib
lipo -archs libexample.dylib
nm -gU libexample.dylib
otool -L libexample.dylib
```

`_loadu`（または `_load`）、`_request`、`_unload` と対象CPUを確認します。依存ライブラリも同じCPUに対応させ、開発機だけの絶対パスを残さないでください。

Utataneの「SHIORI読み込み診断…」で初期化結果を確認できます。完成したNARから新規導入し、日本語・空白を含むパス、起動・会話・選択肢・再読込・終了・状態保存を確認します。同梱版の確認時は共通導入版がなくても動くことを確認してください。

## SHIOLINK

`shiori,shiolink.dll` を指定し、masterへ次の `SHIOLINK.utatane.ini` を置きます。指定がなければ `SHIOLINK.INI` を読みます。

```ini
[SHIOLINK]
commandline = "/absolute/path/to/my-shiori" "./dictionary.txt"
charmode = UTF-8
```

1. 起動後に `*L:<masterの絶対パス>/\r\n` を受け取ります。
2. `*S:<取引ID>\r\n` を受けたら同じ行を返してflushします。
3. 続くSHIORI要求を空行まで読み、応答をCRLFと終端空行付きで返してflushします。
4. `*U:\r\n` またはEOFで終了します。

標準出力は通信専用です。ログは標準エラーへ出します。要求待ちは10秒、フレームは約8 MiBまで。シェル展開は行わないため、実行ファイルは絶対パスで指定します。

## SAORIと保存

独自SHIORIのSAORI読み込みと状態保存は、そのSHIORIで管理します。Utataneの共通ブリッジやApplication Supportへの保存が自動適用されるわけではありません。辞書の読み込み先と可変データの保存先を分け、再読み込みでも状態が続くようにしてください。
