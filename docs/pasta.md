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
