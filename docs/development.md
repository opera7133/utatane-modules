# ビルド

macOS 14以降、Xcodeの開発ツール、Swift 6以降、Python 3.12以降、[uv](https://docs.astral.sh/uv/getting-started/installation/)が必要です。以下はリポジトリのルートで実行します。

```sh
git submodule update --init --recursive
uv sync --locked
uv run --locked python scripts/catalog.py validate
uv run --locked python -m unittest discover -s tests -v
swift test --package-path native

uv run --locked python scripts/build.py yaya --archs arm64 x86_64
uv run --locked python scripts/build.py yaya-6 --archs arm64 x86_64
uv run --locked python scripts/build.py satori --archs arm64 x86_64
uv run --locked python scripts/build.py kagari --archs arm64 x86_64
uv run --locked python scripts/build.py misaka-native --archs arm64 x86_64
uv run --locked python scripts/build.py nise-shiori --archs arm64 x86_64
uv run --locked python scripts/build.py ese-shiori --archs arm64 x86_64
for module in saori-cpuid kenonoke textcopy2 mciaudior wmove proxy-ex; do
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

署名済みスナップショットは、OpenSSL 3と管理外のEd25519秘密鍵を使って作ります。正式版はABI検証済みの同一ZIPを再ビルドせずに昇格します。任意のUI確認記録は `catalog/ui-verification.json` にZIPのSHA-256と版・リビジョンを付けて保存できます。

```sh
uv run --locked python scripts/sign_catalog.py sign catalog/generated /path/to/signed-catalog \
  --private-key /path/to/private.pem
uv run --locked python scripts/sign_catalog.py verify /path/to/signed-catalog \
  --public-key /path/to/public.pem
uv run --locked python scripts/sign_catalog.py promote /path/to/signed-catalog /path/to/stable-catalog \
  --private-key /path/to/private.pem --ui-evidence catalog/ui-verification.json
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
  --yaya /path/to/yaya.zip --yaya-6 /path/to/yaya-6.zip --satori /path/to/satori.zip \
  --saori /path/to/saori-cpuid.zip --keyword /path/to/kenonoke.zip
uv run --locked python scripts/test_saori_host.py \
  --host /path/to/Utatane.app/Contents/Helpers/utatane-shiori-host \
  --package /path/to/saori-cpuid.zip /path/to/kenonoke.zip \
            /path/to/textcopy2.zip /path/to/mciaudior.zip /path/to/wmove.zip /path/to/proxy-ex.zip
```

## 上流更新の一括確認

Python 3.12以降と[GitHub CLI](https://cli.github.com/)を使います。初回は `gh auth login` でGitHubへログインしてください。Pythonの追加依存やsubmoduleの初期化は不要です。

```sh
python3 scripts/check_upstream.py
python3 scripts/check_upstream.py --module yaya-6 --module satori
python3 scripts/check_upstream.py --json > /tmp/utatane-upstream.json
python3 scripts/check_upstream.py --fail-on-update
```

カタログの固定版・配布リビジョンと、上流の正式版・試験版・未取り込みコミットを一覧にします。現在の対象はYAYA 5/6、里々、minato、pasta、kagari、華和梨です。Nativeのlocal実装、SAORI、ソースを固定していない案内のみの項目は除外します。カタログやsubmoduleを書き換えず、fetch・ビルド・インストール・公開も行いません。

正式版と試験版は分けて表示します。ブランチ更新には資料・CIなどの変更も含まれるので、表示は更新候補であり、互換性を確認した更新推奨ではありません。タグは数値順で比較し、公開日の並び順には依存しません。

通常は更新候補があっても終了コード0です。`--fail-on-update` を付けると更新候補（試験版・ブランチ更新を含む）がある場合は1、確認失敗がある場合は2を返します。1件の取得に失敗しても残りを確認します。GitHubの認証・通信・API利用制限のエラーも確認失敗として表示します。

追跡設定は `catalog/upstream-watch.json` にあります。YAYAは500/600、里々はunicodeを指定し、タグも系列別に絞ります。その他は上流の既定ブランチを参照します。里々のvendorはsubtreeで履歴が異なるため、取り込み済みの本流コミットを `baseline`、対応するカタログの固定コミットを `baseline_for_source` に記録します。里々を更新したらこの2項目も合わせて更新してください。対応が古い場合は、誤って「更新なし」とせず確認失敗にします。

## ソースと依存の更新

移植元は `sources/` のsubmodule、独自実装は `native/`、ビルド手順は `recipes/` に置きます。submoduleを更新したら `catalog/modules/` の固定コミットも更新してください。

YAYA 6は上流 `YAYA-shiori/yaya-shiori` の `600` ブランチを直接参照します。既存checkoutで参照元を変更した場合は `git submodule sync sources/yaya-6` を実行してから再帰更新してください。依存のDEELX・Gumboもsubmoduleとして固定します。Utatane用の32ビットABI・SAORI接続は `recipes/cpp/` とビルド時パッチで維持し、上流に取り込まれたコンパイラ修正は重複させません。YAYA 5と里々は引き続き移植用forkを参照します。

Python依存は `uv add` または `uv lock --upgrade-package 名前` で変更し、`pyproject.toml` と `uv.lock` を一緒に管理します。

## Utataneアプリへの組み込み

`uv run --locked python scripts/bundle_kagari.py --output /path/to/app/Contents/Resources/NativeShiori/kagari --archs arm64 x86_64` で、同じ固定ソースからアプリ用の配置を作ります。キャッシュは `build/app-bundle/` です。

検査は `sh scripts/verify-bundled-kagari.sh /path/to/Utatane.app arm64 x86_64`、Utatane側の実ロード試験は `sh scripts/test-bundled-kagari.sh /path/to/utatane /path/to/Utatane.app arm64 x86_64` で実行します。

## CIのパッケージ再利用

CIはNative・C++・minato・pastaの4グループを並列に処理します。
`scripts/ci_packages.py` はモジュールごとにソース、カタログ、レシピ、ビルド・検証スクリプト、テスト、ツールチェーン、SDK、対象CPUの入力をハッシュ化します。一致した場合はキャッシュ内のZIPのSHA-256とパッケージ契約を確認し、元のZIPをそのまま再利用します。元のビルドコミットも保持します。

変更があったモジュールだけをビルドし、再利用したZIPも含めてarm64・IntelのABI検証を実行します。キャッシュがない場合は通常どおりビルドします。破損したキャッシュは検証エラーになります。再ビルドを強制するときはGitHub Actionsの対応する `packages-v1-` キャッシュを削除してください。

minatoのテストはCIで最適化を無効にし、v0形式のシンボル名を使います。旧形式で長くなりすぎたシンボル名によるAppleリンカーの失敗を避けます。最適化なしで増えるパーサーのスタック使用量に合わせ、テストスレッドのスタックを32 MiBに設定します。テスト用のデバッグ情報を省き、minatoのテストと配布ビルドは同時コンパイルを1つに抑えて、標準ランナーでのメモリ使用量を減らします。配布用レシピはThin LTOと16個のコード生成単位を使います。ソース側のパニック処理設定は維持します。バイナリのビルド設定を変えるときは、配布リビジョンも上げてください。
