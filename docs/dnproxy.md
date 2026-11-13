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

Utatane 0.2.19では、ZIPの`dnproxy/`を丸ごとゴーストの`ghost/master/`へ置き、下の`shiori.macos`を指定してください。この配置は0.2.20以降でも使えます。同じZIPの`lib/`と`bin/`を一緒に配置してください。

```text
shiori.macos,dnproxy/lib/libdnproxy.dylib
```

.NETが標準の場所にない場合は`UTATANE_DOTNET`へ`dotnet`の絶対パスを指定します。開発時は`UTATANE_DNPROXY_HOST`でホストDLLも変更できます。

## 互換範囲

Windows APIに依存しないC#ソースと、.NET 10向けDLLのSHIORI/3.0に対応します。旧.NET FrameworkやWindows Formsを使うゴーストは対象外です。

起動できないときは、Utatane 0.2.21以降の「SHIORI読み込み診断」で.NETの導入状況を確認できます。
