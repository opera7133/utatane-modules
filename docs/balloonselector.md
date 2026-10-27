# BalloonSelector

Donさん作の、インストール済みバルーンを画像一覧から選べるプラグインです。移植版はプレビュー付きの一列リストを1ページ9件で表示し、選んだバルーンへ切り替えます。

この移植は**Utatane 0.2.16以降**を対象にします。Utatane ModulesからmacOS版YAYAを導入しておきます。プラグインIDと、`OnBalloonSelectMenu`・`OnBalloonSelectExec`・`OnBalloonSelectCancel`は原版のままです。

## NARの生成と導入

このリポジトリのルートで実行します。作業フォルダが既にある場合は、別の空のフォルダを指定してください。

```sh
git clone https://github.com/nikolat/balloonselector.git ~/ws/balloonselector-port-source
git -C ~/ws/balloonselector-port-source checkout 04ac6c086a03f1394c572d0748e4bdd190046c77
python3 scripts/port_balloonselector.py --source ~/ws/balloonselector-port-source --output dist/balloonselector-utatane.nar
```

生成したNARをUtataneへ導入し、ゴーストの右クリックメニューのプラグインからBalloonSelectorを実行します。対応ゴーストなら、`\![raiseplugin,BalloonSelector,OnMenuExec]`でも呼べます。カタログからの自動導入や配布サーバーへのNAR掲載はまだありません。

## 移植内容

- 自由座標を使う原版の3×3配置は、Utataneの文字配置との互換差を避けるため一列のリストに変更します。
- 原版のYAYA辞書を使用し、macOS版YAYAのフォルダ列挙で先頭のバルーンを飛ばす箇所を修正します。
- 原版へのネットワーク更新で修正が消えないよう、`homeurl`を除きます。移植版の更新はNARの再生成で行います。
- 本体側では、プラグインへバルーンの格納先を通知し、サイズ取得の結果と選択肢のクリックを発信元プラグインへ返します。
- 原版のWindows DLLはファイル名によるYAYA判定用に残します。macOS上の実行には、導入済みのmacOS版YAYAを使います。

元の辞書はUnlicense、同梱のWindows用YAYAはBSD-3-Clauseです。NARに原版の`LICENSE`を含めます。

[原版とライセンス](https://github.com/nikolat/balloonselector)

## 回帰確認

Utataneの`Scripts/test-real-plugins.py`へ、このModules checkoutと固定コミットの原版checkoutを指定できます。移植NARの生成、実YAYAによるページ送り・全件列挙・選択・キャンセル、一時コピーの削除まで確認します。実プラグインの配布物はfixtureへ同梱せず、取得元とハッシュをレポートへ残します。実行例は[本体のプラグイン開発資料](https://github.com/opera7133/Utatane/blob/main/Docs/Creators/Native-Plugins.md#実プラグインの回帰確認)を参照してください。移植ツールの更新後はNARを再生成してください。
