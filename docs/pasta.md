# pasta

ZIP内の `pasta/lib/libpasta.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,pasta.dll
```

他のベースウェアで必要なら`shiori.macos,libpasta.dylib`を追加してください。

`LICENSES/` も含めて同梱してください。共通導入の場合は、ZIP内の `pasta/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

LuaJITと標準Pastaスクリプトはdylibに含まれます。辞書・保存先は `pasta.toml` に従い、保存データの既定位置はゴースト内の `profile/pasta/save/` です。Windows専用のLua FFI呼び出しやDLLは実行できません。

文字列はUTF-8です。Utataneではゴーストごとに別プロセスで実行します。

0.3.8ではシーン登録名を「名前_通し番号」へ変更し、Call後の文脈復元、タグのみの段落区切りなどを修正しています。内部のシーン名を直接指定する辞書や段落区切りに依存する辞書は、[上流の変更内容](https://github.com/ekicyou/pasta/releases/tag/v0.3.8)を確認してください。


0.4.1ではアクターごとの文字装飾、縦書きのbudoux改行、仮想時刻に追従する時報などが追加・修正されています。0.3系から更新すると、選択肢の改行位置やbudouxの折り返し位置が変わる場合があります。また、値のない変数やCallの失敗などをバルーンへ表示し、Luaエラー時にも途中までの台詞を返す動作が既定です。従来のエラー応答を使う場合は`pasta.toml`の`[logging] balloon_warning = false`を指定します。詳しくは[0.4.0の互換差](https://github.com/ekicyou/pasta/blob/v0.4.1/doc/release-notes/v0.4.0.md)と[0.4.1の互換差](https://github.com/ekicyou/pasta/blob/v0.4.1/doc/release-notes/v0.4.1.md)を確認してください。

0.4.2では自動トークの停止・再開、外部からのシーン再生・関数呼び出し・変数代入、イベントハンドラの重ね登録が追加されています。台詞を出さないイベントではチェイントークの続きを維持し、自動ウェイトと改行は絵文字・結合文字を分断しない単位になります。[0.4.2の変更内容](https://github.com/ekicyou/pasta/releases/tag/v0.4.2)を確認してください。
