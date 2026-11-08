# D.N.Proxy（Portable C#）

[D.N.Proxy](https://github.com/nikolat/dnproxy)の公開インターフェイスに合わせた独立実装です。古い.NET FrameworkのAppDomainやWindows用DLLを書き換える方式は使わず、ゴーストごとに.NETの子プロセスを起動します。

**対象はWindows APIに依存しないC#ソースまたは現行.NET向けDLL、UTF-8、SHIORI/3.0です。** 原作の全ゴーストがそのまま動くという意味ではありません。

## 必要なものと導入

- macOS 14以降と.NET 10ランタイム
- `dnproxy.ini`から実行時コンパイルする場合は.NET 10 SDK

.NETは同梱しません。公式の[.NETダウンロード](https://dotnet.microsoft.com/download/dotnet/10.0)から導入してください。SDKにはランタイムも含まれます。

### Utatane 0.2.20以降

Utatane 0.2.20以降では、メニューバーの「モジュール」→「モジュールカタログ…」からD.N.Proxyをダウンロードできます。導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直してください。`ghost/master/`に`dnproxy.ini`または`dnproxy.dll.config`があれば、Windows用の指定が`shiori.dll`という汎用名でも判別します。通常は`shiori.macos`の追加は不要です。

共通導入では`NativeShiori/dnproxy/`の`lib/`と`bin/`を一組で保持します。ゴースト側の設定・C#ソースはそのまま使います。既存の手動配置から切り替える場合は、追加した`shiori.macos`指定を外し、古いゴースト内のmacOS用ライブラリを別の場所へ退避してから再読み込みしてください。明示指定やゴースト内のライブラリが共通導入版より優先されます。ゴーストの設定・ソース・保存データは移動する必要はありません。

### Utatane 0.2.19での導入・手動配置

Utatane 0.2.19では、ZIPの`dnproxy/`を丸ごとゴーストの`ghost/master/`へ置き、下の`shiori.macos`を指定してください。この配置は0.2.20以降でも利用できます。**`libdnproxy.dylib`だけをコピーせず、同じパッケージの`bin/`も保持してください。** `bin/`には.NETホストとインターフェイス定義を収録しています。手動配置の例:

```text
master/
  dnproxy/lib/libdnproxy.dylib
  dnproxy/bin/DnProxyHost.dll
  dnproxy/bin/DnProxyHost.runtimeconfig.json
  dnproxy/bin/DnProxyHost.deps.json
  dnproxy/bin/Ukagaka.NET.Interfaces.dll
  dnproxy.dll.config
  dnproxy.ini
  src/Ghost.cs
```

```text
shiori.macos,dnproxy/lib/libdnproxy.dylib
```

.NETが標準の場所にない場合は`UTATANE_DOTNET`へ`dotnet`の絶対パスを指定します。開発時は`UTATANE_DNPROXY_HOST`でホストDLLも変更できます。

## 対応する設定とコード

`dnproxy.dll.config`の`AssemblyName`・`MainClass`・`Protocol`・`PrivateBinPath`を読みます。`Protocol`は`SHIORI/3.0`にしてください。

`dnproxy.ini`では`Language: C#`・`SourceFiles`・`MainClass`・`OutputAssembly`・`ReferencedAssemblies`に対応します。SourceFilesはコンマ区切り、続きの行、ワイルドカードを利用できます。コンパイル結果は`profile/dnproxy-macos/`へ置き、元のWindows用`user.dll`は上書きしません。コンパイル済みの現行.NET DLLを使う場合は`dnproxy.ini`を省き、AssemblyNameを指定します。

クラスは`Ukagaka.NET.Interfaces`の`ILoad`・`IRequest`・`IUnload`を実装します。load/requestの入力メモリはユーザーコードが`Marshal.FreeHGlobal`で解放し、応答も同じアロケータで確保します。**長さはUTF-8のバイト数**です。macOSの`PtrToStringAnsi`はWindowsのCP932と同じ意味ではないので、`PtrToStringUTF8`や`Encoding.UTF8`を明示する形を推奨します。

## 制限と検証

VB/JScript、WinForms、COM、Windows DLL、原作dnutil、Win32Resource・EmbeddedResources・LinkedResources・CompilerOptions、SHIORI以外のPLUGIN/SAORI等は未対応です。コンパイル済み.NET Framework DLLの無変更動作やCP932のメモリ契約も保証しません。非対応の設定はエラーとして止めます。

C#の実行時コンパイル、日本語・絵文字の応答、保存・再読込、コンパイル済みDLL、dylibとホストの移設を合成ゴーストで確認しています。原作付属サンプルはWindows Formsに依存するため、この対応範囲には含みません。実ゴーストの画面操作は未確認です。

## Utatane 0.2.21以降の事前診断

「SHIORI読み込み診断」で、実際に使うdotnetの絶対パス・そのdotnetのCPU・.NET 10 runtime・必要な場合だけSDKを照会します。「再診断」で入れ直した環境を確認し、ゴーストを再読み込みしてください。診断ではゴーストのC#をコンパイル・ロードしません。

- モジュール未導入とbin不足は、Modulesの再導入またはlib/binを一組で配置することで直してください。
- runtime不足なら選ばれたdotnetと同じCPU向けの.NET 10 runtimeを、`dnproxy.ini`があるソース方式でSDK不足なら.NET 10 SDK（またはnet10を対象にできる新しい安定版SDK）を導入してください。コンパイル済みDLL方式ではSDKを要求しません。
- `UTATANE_DOTNET`を指定した場合は、その実行ファイルを検査・使用します。無効な指定を別のdotnetへ黙って切り替えません。実行できるx64版dotnetをRosetta経由で使うことは、arm64アプリとCPUが違うというだけでは拒否しません。
- 設定不正・非対応設定と、起動時のコンパイル/assembly解決/ユーザーload失敗は区別します。詳しい起動段階のエラーを本体へ返すにはModules **0.1.0-r2以降**とUtatane 0.2.21以降が必要です。旧本体でもr2を実行できますが、起動失敗の詳細は表示されません。
- 「実行準備OK」は依存確認が通った意味です。Windows Forms/COM/旧.NET Framework全体の互換や、ユーザーコードの動作成功を保証しません。

照会方法は[公式dotnet CLI](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet)の`--info`・`--list-runtimes`・`--list-sdks`に従います。.NETの自動導入・同梱は行いません。
