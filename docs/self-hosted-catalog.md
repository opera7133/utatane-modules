# 自分のカタログを作る

このリポジトリをフォークして、カタログを生成・署名できます。Utataneへ登録するのは、HTTPSの `index.json` URLとEd25519公開鍵です。

## 1. 掲載内容を選ぶ

- `catalog/modules/` から配布しない項目を外し、自分の項目を追加する。最低1件必要。
- ZIPなしなら[蒼空の定義](../catalog/modules/aosora.json)を参考に `instructions-only` とし、`docs/<id>.md` を書く。
- ZIPを配るなら[ZIP配布の手順](contributing-modules.md#pull-requestを出す場合)に従い、ビルド・検証・CIを自分の項目に合わせる。

ビルド済みZIPの外部URLだけでは自動導入できません。ZIPがない `binary` 項目は、Utataneが索引を読み込めない原因になります。

## 2. 生成・署名する

以下は**手順のみ**のカタログの例です。フォークのルートで実行します。生成先は既存ディレクトリを上書きしません。

```sh
git submodule update --init --recursive
uv sync --locked
uv run --locked python scripts/catalog.py validate
uv run --locked python scripts/catalog.py generate --output catalog/my-development

openssl genpkey -algorithm Ed25519 -out /path/to/private.pem
openssl pkey -in /path/to/private.pem -pubout -out /path/to/public.pem
uv run --locked python scripts/sign_catalog.py sign catalog/my-development catalog/my-stable \
  --private-key /path/to/private.pem --channel stable
uv run --locked python scripts/sign_catalog.py verify catalog/my-stable \
  --public-key /path/to/public.pem --channel stable
```

秘密鍵はフォークと公開先の外で保管します。ZIPを含む場合は、各CPUのABI確認を記録してから署名します。[ビルド手順](development.md)を参照してください。

Utataneに入力する公開鍵は次のコマンドで表示します。PEMファイルの本文は入力しません。

```sh
openssl pkey -pubin -in /path/to/public.pem -outform DER | tail -c 32 | base64 | tr -d '\n'
```

## 3. 公開・切り替え

1. `catalog/my-stable/` の中身をHTTPSで公開する。`index.json`、`index.sig`、`docs/`、ZIPがあれば `artifacts/` を同じ構成で置く。
2. 公開URLでこれらのファイルを取得できることを確認する。
3. Utataneの「設定」→「SHIORI」→「カタログの接続先（上級者向け）」へ `https://example.com/modules/index.json` のようなURLと公開鍵のBase64を入力し、「接続先を保存」を押す。
4. 「モジュール」→「モジュールカタログ…」で一覧を確認する。ZIPがあれば導入・起動も試す。

通常の独自接続先で使えるのは署名済みの `stable` カタログです。更新時は再生成・再署名し、ZIPを同じ名前で上書きしないでください。「標準に戻す」でUtatane既定の接続先に戻せます。
