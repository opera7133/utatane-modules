# D.N.Proxy（Portable C#）

[D.N.Proxy](https://github.com/nikolat/dnproxy)の公開インターフェイスに合わせた独立実装です。古い.NET FrameworkのAppDomainやWindows用DLLを書き換える方式は使わず、ゴーストごとに.NETの子プロセスを起動します。

**対象はWindows APIに依存しないC#ソースまたは現行.NET向けDLL、UTF-8、SHIORI/3.0です。** 原作の全ゴーストがそのまま動くという意味ではありません。

## 必要なものと導入

- macOS 14以降と.NET 10ランタイム
- `dnproxy.ini`から実行時コンパイルする場合は.NET 10 SDK

.NETは同梱しません。公式の[.NETダウンロード](https://dotnet.microsoft.com/download/dotnet/10.0)から導入してください。SDKにはランタイムも含まれます。

ZIPの`dnproxy/`を丸ごと共通導入先`~/Library/Application Support/Utatane/NativeShiori/dnproxy/`へ置くか、ゴースト内へ展開します。**`libdnproxy.dylib`だけをコピーせず、同じ階層の`bin/`も保持してください。** `bin/`には.NETホストとインターフェイス定義を収録しています。手動配置の例:

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
