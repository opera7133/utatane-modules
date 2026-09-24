# ビルド

macOS 14以降、Xcodeの開発ツール、Swift 6以降、Python 3.12以降、[uv](https://docs.astral.sh/uv/getting-started/installation/)が必要です。以下はリポジトリのルートで実行します。

```sh
git submodule update --init --recursive
uv sync --locked
uv run --locked python scripts/catalog.py validate
uv run --locked python -m unittest discover -s tests -v
swift test --package-path native

uv run --locked python scripts/build.py yaya --archs arm64 x86_64
uv run --locked python scripts/build.py satori --archs arm64 x86_64
uv run --locked python scripts/build.py kagari --archs arm64 x86_64
uv run --locked python scripts/build.py misaka-native --archs arm64 x86_64
for module in saori-cpuid kenonoke textcopy2 mciaudior wmove; do
  uv run --locked python scripts/build.py "$module" --archs arm64 x86_64
done
rustup toolchain install 1.93.0 --profile minimal
rustup target add --toolchain 1.93.0 aarch64-apple-darwin x86_64-apple-darwin
uv run --locked python scripts/build.py minato --archs arm64 x86_64
uv run --locked python scripts/build.py pasta --archs arm64 x86_64
uv run --locked python scripts/catalog.py generate \
  --output catalog/generated --package dist/*.zip
```

ZIPは `dist/`、カタログは `catalog/generated/` に出力します。`catalog/generated/` は `index.html` を含む静的な配布単位です。既存の出力は上書きしません。再実行時は `--output` で別の場所を指定してください。

署名済みの検証用スナップショットは、OpenSSL 3と管理外のEd25519秘密鍵を使って作ります。`--channel stable` は全バイナリのABI・Utatane UI検証が記録された場合だけ通ります。

```sh
uv run --locked python scripts/sign_catalog.py sign catalog/generated /path/to/signed-catalog \
  --private-key /path/to/private.pem
uv run --locked python scripts/sign_catalog.py verify /path/to/signed-catalog \
  --public-key /path/to/public.pem
```

ビルドはZIPを展開してABIテストまで実行します。実行するのはホストのCPU側です。依存アーカイブは `build/cache/downloads/` に保存し、再利用時もハッシュを照合します。

## Utataneとの結合テスト

```sh
uv run --locked python scripts/test_utatane.py \
  --utatane ../utatane --package /path/to/misaka-native.zip
uv run --locked python scripts/test_utatane.py \
  --utatane ../utatane --module minato --package /path/to/minato.zip
uv run --locked python scripts/test_utatane.py \
  --utatane ../utatane --module pasta --package /path/to/pasta.zip
```

ZIPを検証してから、Utatane側で読み込み・保存・再読み込みを確認します。

YAYA・里々とSAORIを実際のUtataneヘルパーで検証する場合：

```sh
uv run --locked python scripts/test_cpp_host.py \
  --host /path/to/Utatane.app/Contents/Helpers/utatane-shiori-host \
  --yaya /path/to/yaya.zip --satori /path/to/satori.zip \
  --saori /path/to/saori-cpuid.zip --keyword /path/to/kenonoke.zip
uv run --locked python scripts/test_saori_host.py \
  --host /path/to/Utatane.app/Contents/Helpers/utatane-shiori-host \
  --package /path/to/saori-cpuid.zip /path/to/kenonoke.zip \
            /path/to/textcopy2.zip /path/to/mciaudior.zip /path/to/wmove.zip
```

## ソースと依存の更新

移植元は `sources/` のsubmodule、独自実装は `native/`、ビルド手順は `recipes/` に置きます。submoduleを更新したら `catalog/modules/` の固定コミットも更新してください。

Python依存は `uv add` または `uv lock --upgrade-package 名前` で変更し、`pyproject.toml` と `uv.lock` を一緒に管理します。

## Utataneアプリへの組み込み

`uv run --locked python scripts/bundle_kagari.py --output /path/to/app/Contents/Resources/NativeShiori/kagari --archs arm64 x86_64` で、同じ固定ソースからアプリ用の配置を作ります。キャッシュは `build/app-bundle/` です。

検査は `sh scripts/verify-bundled-kagari.sh /path/to/Utatane.app arm64 x86_64`、Utatane側の実ロード試験は `sh scripts/test-bundled-kagari.sh /path/to/utatane /path/to/Utatane.app arm64 x86_64` で実行します。
