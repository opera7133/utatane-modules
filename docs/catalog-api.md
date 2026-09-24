# カタログAPI v1

生成した `index.json` を読みます。形式はリポジトリの `schemas/index.schema.json`、ZIP内の `module.json` は `schemas/package.schema.json` を参照してください。

`schemaVersion` は1。`modules` にモジュール情報と成果物を列挙します。`instructions` と成果物の `path` は `index.json` からの相対パスです。ZIPのファイル名には内容ハッシュの先頭16桁を付けます。生成先のディレクトリ全体を配布単位にします。`index.html` には検索・種類別の絞り込み・ダウンロードリンクがあり、配布先のディレクトリ名には依存しません。

| `availability` | 内容 |
| --- | --- |
| `instructions-only` | 導入手順のみ |
| `not-built` | このカタログに成果物がない |
| `candidate` | 検証済みの候補ZIPがある |

成果物を選ぶ際はOS、CPU、ABIを照合します。`architectures` は収録CPU、`verification.nativeABI` は実行確認したCPUです。

`module.json` の `source` と `build` にソース・ビルド条件、`files` に各ファイルのSHA-256を記録します。SHA-256とad-hoc署名は配布元の認証にはなりません。`signed: false` のカタログを信頼済みの自動導入元として扱わないでください。

`staging` と `stable` は `signed: true` とし、`index.json` のバイト列に対するEd25519署名を64バイトの `index.sig` に保存します。検証側は組み込みの公開鍵で署名を確認してから、各ZIPのサイズとSHA-256を照合します。Utataneの自動導入対象は `stable` だけです。署名済みの一覧とファイル一式を同じディレクトリに配置してください。
