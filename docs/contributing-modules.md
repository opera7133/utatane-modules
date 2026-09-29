# このカタログにSHIORIを載せる

まず[掲載相談のIssue](https://github.com/opera7133/utatane-modules/issues/new?template=module-listing.md)を開いてください。実装まで用意できている場合はPull Requestでも構いません。掲載とビルド対応は、ライセンスと検証方法を確認して決めます。

| やりたいこと | 方法 |
| --- | --- |
| 入手先や手動導入を案内したい | `instructions-only` で掲載 |
| このカタログからZIPを配りたい | ビルド・検証処理を追加して掲載 |
| macOS版の移植やビルドを頼みたい | ソースとビルド情報を添えて相談 |

外部ZIPのURLだけでは自動導入できません。自動導入するZIPは、このカタログと同じ配布先へ置き、索引の署名とZIPの検証に含めます。外部サイトへのリンクは案内用に載せられます。

## Issueに書くこと

- 名前・作者・ソースまたは配布URL
- ライセンスと再配布の可否（依存物も含む）
- macOS版の有無、対応CPU、最低macOS、Windows版のDLL名
- ビルド手順、試せるゴースト、既知の制限（分かる範囲で）

ゴーストや辞書に再配布許可がない場合は、テスト用に添付せず入手先を示してください。

## Pull Requestを出す場合

**手順のみ:** `catalog/modules/<id>.json` と `docs/<id>.md` を追加します。[蒼空](../catalog/modules/aosora.json)が例です。`delivery` は `instructions-only`。入手先、導入方法、制限、未確認事項を書いてください。

**ZIP配布:** [YAYA](../catalog/modules/yaya.json)を例に、固定ソース、`recipes/` のビルド処理、`scripts/build.py` の分岐、ABIテスト、[CIのビルド対象](../.github/workflows/check.yml)を追加します。新しいIDは自動ではビルドされません。ZIPには `module.json`、dylib、ライセンスを含めます。詳しくは[ビルド手順](development.md)を参照してください。

```sh
uv sync --locked
uv run --locked python scripts/catalog.py validate
uv run --locked python -m unittest discover -s tests -v
```

ZIP配布では、収録する各CPUのABI確認も必要です。Utataneでの起動確認は別に記録してください。秘密鍵はPRへ入れないでください。公開は採用後に配布者が行います。

自分で配布先を管理するなら[独自カタログの作り方](self-hosted-catalog.md)へ。
