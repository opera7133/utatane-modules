# SHIORI・SAORIの実行方式

Utataneは辞書や設定からSHIORIを判別し、macOS向けの実装へ接続します。DLLそのものをmacOSで実行する仕組みではありません。配布物と導入方法は[一覧](../README.md)、自作・移植の接続方法は[SHIORI開発](shiori-development.md)を参照してください。

## SHIORIの選択

ゴーストが `shiori.macos` で指定したモジュールは自動判定より優先します。美坂・偽栞・ese-shiori・minato・pasta・kagari・aosoraの同梱ライブラリの破損や関数の欠落を検出すると、同じSHIORIの共通導入版を試します。設定で無効にできます。辞書や保存データのエラーでは切り替えません。指定がなければ `shiori` と辞書・設定を使って判別します。`shiori` の省略時は `shiori.dll` が既定です。

[美坂](misaka.md)・[偽栞](nise-shiori.md)・[ese-shiori](ese-shiori.md)・[minato](minato.md)・[pasta](pasta.md)・[kagari](kagari.md)の配布版は、ゴースト同梱、Application Support、アプリ内の順に探します。`UTATANE_MISAKA_MODULE` / `UTATANE_NISE_SHIORI_MODULE` / `UTATANE_ESE_SHIORI_MODULE` / `UTATANE_MINATO_MODULE` / `UTATANE_PASTA_MODULE` / `UTATANE_KAGARI_MODULE` は開発時の明示的な上書きです。

## 辞書エンジン

| SHIORI | 読み込み・制約 |
| --- | --- |
| YAYA / AYA | `yaya.txt`、`aya5.txt`、`aya.txt`。旧AYAのすべての版との互換性は保証しません |
| 里々 | ネイティブ実装。SSUは里々内蔵のものを使用 |
| 華和梨 | 64-bit macOS向け修正を含むネイティブ実装 |
| 美坂 | `misaka.ini` と辞書をSwiftで実行。暗号化辞書は対象外 |
| 灯 | `res/*.txt`、`.azr`、amb.exe 1.1形式の `main.amb`。例外、クラス、Windows固有操作等は対象外 |
| ese-shiori | `eseai.ini`、平文・難読化辞書。SAORI構文は対象外 |
| 偽栞 | `ai*.txt` / `ai*.dtx`。単語間チェイン、TEACH全体、SAORI構文等は対象外 |
| 忍 | Shift_JISの `ai*.txt`。Windowsのプロセス・HWND等は対象外 |
| 翡翠 | TLK、設定、単語辞書、変数と感情値。クリック等からの独自の感情学習やSAORI構文は対象外 |
| FIRST | 対応する原版 `first.dll` の文字列・リソースを読む専用人格。DLLは実行せず、会話本文は配布しません |
| 結奈 | 非暗号化YDF/1.07のイベント・条件・選択肢・変数。任意の式・関数、編集機能、SAORI構文は対象外 |

YAYA / AYA、里々、華和梨、美坂、灯、忍は共通SAORIブリッジへ接続します。Utataneが管理する変数・学習データはApplication Supportに保存します。

## 外部SHIORI

通常のSHIORI入口を持つdylibは、ゴースト・プラグインごとに別プロセスで実行します。[minato](minato.md)もこの方式です。独立したセッションと共通SAORIを使う美坂は、アプリ内で実行します。

| 経路 | 条件 |
| --- | --- |
| kagari | Lua 5.4を使うmacOSモジュール。[導入手順](kagari.md) |
| 蒼空 | 利用者が用意するmacOSモジュール。[ビルド・導入](aosora.md) |
| SHIOLINK | `SHIOLINK.utatane.ini` または `SHIOLINK.INI` で外部プロセスを指定 |
| 里珠 / Proxy | `rishu_proxy.dll` と `rishu_remote.pl` を識別し、Perlプロセスへ接続 |
| 汎用macOSモジュール | `loadu` / `load`、`request`、`unload` を持つdylib等 |
| Windows DLL | Wineと汎用DLLホストが設定されている場合に外部プロセスで実行 |

外部SHIORIのSAORIは、そのSHIORIが管理します。共通SAORIへ自動転送しません。LuaやSHIOLINKの外部プロセスはサンドボックス化されません。Windows用SAORIや補助DLLも個別に対応が必要です。

## 共通SAORIブリッジ

| 名前 | 機能 |
| --- | --- |
| `mciaudior.dll` | load、play、loop、stop |
| `wmove.dll` | MOVETO、MOVETO_INSIDE、GET_POSITION、GET_DESKTOP_SIZE |
| `textcopy2.dll` | macOSのクリップボードへの書き込み |
| `saori_cpuid.dll` | macOS、CPU、メモリ情報 |
| `kenonoke.dll` | 同じフォルダの `keyword.txt` による分類 |

`wmove.dll` はHWNDの代わりにUtataneのサーフェスを操作します。MOVE、ZMOVE、WAIT、NOTIFY、CLEAR、STANDBYは対象外です。未知のSAORIはmacOS用なら標準ABI、Windows用なら設定済みWineとDLLホストへ渡します。相対パスは `ghost/master` 内に制限します。

## MAKOTO

`[ParticleMakoto]` の助詞変換と、Makoto Basicの `makoto0.lst` / `makoto1.lst` による文字列置換をSwiftで処理します。旧SakuraScriptの `\h` / `\u` による辞書切替にも対応します。select / repeatの専用記法は対象外です。
