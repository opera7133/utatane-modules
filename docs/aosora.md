# 蒼空の手動導入

[蒼空](https://github.com/kanadelab/aosora-shiori)はライセンスの都合により導入手順のみ掲載します。

上流の[利用条件](https://github.com/kanadelab/aosora-shiori/blob/HEAD/license.txt)を確認し、[macOS対応ソース](https://github.com/opera7133/aosora-shiori)を用意してください。以下はこのリポジトリのルートで実行します。

```sh
brew install pkg-config openssl@3 jsoncpp
sh recipes/aosora/build.sh /path/to/aosora-shiori
```

スクリプトは渡したソース内で `make clean` を実行します。専用の作業コピーを使ってください。標準の出力先は次のとおりです。

```text
~/Library/Application Support/Utatane/NativeShiori/aosora/libaosora.dylib
```

別の配置を使う場合は、Utataneの起動環境で `UTATANE_AOSORA_MODULE` に絶対パスを指定します。
